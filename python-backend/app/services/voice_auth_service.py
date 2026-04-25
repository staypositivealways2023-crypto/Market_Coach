"""Firebase token validation for voice endpoints.

All /api/voice/* routes depend on get_verified_uid() to resolve a Firebase
ID token to a MarketCoach user ID.

Two verification paths:

1. **Full firebase_admin** (preferred, production):
   Set FIREBASE_CREDENTIALS_JSON (base64-encoded service account JSON) or
   FIREBASE_CREDENTIALS_PATH on the host/Railway environment.

2. **google-auth lightweight** (fallback, Railway without service account):
   Uses google.oauth2.id_token.verify_firebase_token which only needs
   FIREBASE_PROJECT_ID — no service account certificate required.
   This verifies the JWT signature against Google's public keys directly.
"""

from __future__ import annotations

import logging
from functools import lru_cache

import firebase_admin
import firebase_admin.auth
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import settings

logger = logging.getLogger(__name__)
_bearer = HTTPBearer(auto_error=True)

# Whether firebase_admin was successfully initialised with real credentials
_firebase_admin_ready = False
_auth_validation_attempted = False
_auth_path_available = False


def validate_auth_config() -> bool:
    """
    Validate that at least one auth path (firebase_admin or google-auth) is available.
    Call this at startup to ensure the app can authenticate voice requests.

    Returns True if at least one path is available, False otherwise.
    Logs warnings if both paths will fail.
    """
    global _auth_validation_attempted, _auth_path_available

    if _auth_validation_attempted:
        return _auth_path_available

    _auth_validation_attempted = True

    # Check if firebase_admin can be initialized
    if _try_init_firebase_admin():
        logger.info("[voice_auth] firebase_admin initialized — auth ready")
        _auth_path_available = True
        return True

    # Check if google-auth fallback can work (requires project ID)
    if settings.FIREBASE_PROJECT_ID:
        logger.info(
            "[voice_auth] firebase_admin unavailable; google-auth fallback available "
            f"(project={settings.FIREBASE_PROJECT_ID})"
        )
        _auth_path_available = True
        return True

    # Both paths unavailable
    logger.error(
        "[voice_auth] NO AUTH PATHS AVAILABLE. Both firebase_admin and google-auth "
        "fallback are unavailable. Voice endpoints will fail authentication. "
        "Set either FIREBASE_CREDENTIALS_JSON/FIREBASE_CREDENTIALS_PATH or FIREBASE_PROJECT_ID."
    )
    _auth_path_available = False
    return False


def _try_init_firebase_admin() -> bool:
    """Attempt to initialise firebase_admin with a service account.

    Returns True if initialised (or already initialised), False otherwise.
    """
    global _firebase_admin_ready

    if firebase_admin._apps:
        _firebase_admin_ready = True
        return True

    import base64
    import json

    try:
        if settings.FIREBASE_CREDENTIALS_JSON:
            raw = base64.b64decode(settings.FIREBASE_CREDENTIALS_JSON)
            cred_dict = json.loads(raw)
            cred = firebase_admin.credentials.Certificate(cred_dict)
        elif settings.FIREBASE_CREDENTIALS_PATH:
            cred = firebase_admin.credentials.Certificate(
                settings.FIREBASE_CREDENTIALS_PATH
            )
        else:
            # No service account available — skip firebase_admin init
            logger.debug(
                "[voice_auth] No service account credentials found. "
                "Will use google-auth lightweight verification instead."
            )
            return False

        firebase_admin.initialize_app(
            cred, {"projectId": settings.FIREBASE_PROJECT_ID}
        )
        logger.info(
            f"[voice_auth] firebase_admin initialised for project "
            f"{settings.FIREBASE_PROJECT_ID}"
        )
        _firebase_admin_ready = True
        return True

    except Exception as exc:
        logger.debug(
            f"[voice_auth] firebase_admin init failed ({exc}). "
            "Falling back to google-auth lightweight verification."
        )
        return False


def _verify_with_google_auth(id_token: str) -> str:
    """Verify a Firebase ID token using google-auth (no service account needed).

    Validates the JWT against Google's public keys and checks the audience
    matches FIREBASE_PROJECT_ID.  Returns the uid on success.
    """
    try:
        from google.auth.transport import requests as grequests
        from google.oauth2 import id_token as google_id_token

        request = grequests.Request()
        decoded = google_id_token.verify_firebase_token(
            id_token,
            request,
            audience=settings.FIREBASE_PROJECT_ID,
        )
        uid = decoded.get("uid") or decoded.get("sub")
        if not uid:
            raise ValueError("Token missing uid/sub field")
        return uid
    except Exception as exc:
        logger.warning(f"[voice_auth] google-auth verification failed: {exc}")
        raise


def _decode_uid_from_token(token: str) -> str:
    """
    Extract the uid from a Firebase JWT without verifying the signature.
    Used only for DEV_BYPASS_AUTH mode — never call in production.
    Firebase ID tokens encode uid as 'user_id' in the payload; anonymous
    tokens use 'sub'.
    """
    import base64
    import json as _json

    try:
        parts = token.split(".")
        if len(parts) != 3:
            return "dev_user"
        # JWT payload is URL-safe base64 — pad to multiple of 4
        padded = parts[1] + "=" * (-len(parts[1]) % 4)
        payload = _json.loads(base64.urlsafe_b64decode(padded))
        uid = payload.get("user_id") or payload.get("sub") or "dev_user"
        return uid
    except Exception:
        return "dev_user"


async def get_verified_uid(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
) -> str:
    """FastAPI dependency: validates Firebase ID token → returns uid.

    Tries firebase_admin first (full verification); falls back to
    google-auth lightweight verification when no service account is present.

    In development mode with DEV_BYPASS_AUTH=true, decodes the JWT payload
    without signature verification so local testing works without needing a
    working service account or network access to Google.

    Usage::

        @router.post("/session/create")
        async def create_session(uid: str = Depends(get_verified_uid)):
            ...
    """
    token = credentials.credentials

    # ── Dev bypass (local development only) ──────────────────────────────────
    if settings.ENVIRONMENT == "development" and settings.DEV_BYPASS_AUTH:
        uid = _decode_uid_from_token(token)
        logger.info(f"[voice_auth] DEV_BYPASS_AUTH active — uid={uid} (no sig verify)")
        return uid

    # ── Path 1: firebase_admin (service account present) ─────────────────────
    if _try_init_firebase_admin():
        try:
            decoded = firebase_admin.auth.verify_id_token(token)
            return decoded["uid"]
        except firebase_admin.auth.ExpiredIdTokenError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Firebase token has expired — please refresh and retry.",
            )
        except firebase_admin.auth.InvalidIdTokenError as exc:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Invalid Firebase token: {exc}",
            )
        except Exception as exc:
            logger.error(f"[voice_auth] firebase_admin verification error: {exc}")
            logger.info("[voice_auth] Retrying with google-auth fallback...")

    # ── Path 2: google-auth lightweight (project ID only) ────────────────────
    if not settings.FIREBASE_PROJECT_ID:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Server misconfiguration: FIREBASE_PROJECT_ID not set.",
        )

    try:
        uid = _verify_with_google_auth(token)
        return uid
    except Exception as exc:
        error_msg = str(exc).lower()
        if "expir" in error_msg:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Firebase token has expired — please refresh and retry.",
            )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token verification failed. Ensure you are signed in.",
        )
