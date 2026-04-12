"""Firebase token validation for voice endpoints.

All /api/voice/* routes depend on get_verified_uid() to resolve a Firebase
ID token to a MarketCoach user ID.  firebase_admin is initialised once (lazy,
guarded by _apps check) so this module is safe to import from multiple routers.
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


def _ensure_firebase_app() -> None:
    """Initialise firebase_admin exactly once."""
    if firebase_admin._apps:
        return

    import base64
    import json

    if settings.FIREBASE_CREDENTIALS_JSON:
        # Railway / production: base64-encoded service account JSON in env var
        raw = base64.b64decode(settings.FIREBASE_CREDENTIALS_JSON)
        cred_dict = json.loads(raw)
        cred = firebase_admin.credentials.Certificate(cred_dict)
    elif settings.FIREBASE_CREDENTIALS_PATH:
        cred = firebase_admin.credentials.Certificate(settings.FIREBASE_CREDENTIALS_PATH)
    else:
        # No credentials — fall back to application default (local dev with gcloud)
        cred = firebase_admin.credentials.ApplicationDefault()

    firebase_admin.initialize_app(cred, {"projectId": settings.FIREBASE_PROJECT_ID})
    logger.info(f"[voice_auth] Firebase initialised for project {settings.FIREBASE_PROJECT_ID}")


async def get_verified_uid(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
) -> str:
    """FastAPI dependency: validates Firebase ID token → returns uid.

    Usage::

        @router.post("/session/create")
        async def create_session(uid: str = Depends(get_verified_uid)):
            ...
    """
    _ensure_firebase_app()
    try:
        decoded = firebase_admin.auth.verify_id_token(credentials.credentials)
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
        logger.error(f"[voice_auth] Token verification failed: {exc}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token verification failed.",
        )
