"""WebSocket proxy: Flutter ↔ Backend ↔ OpenAI Realtime API

Why a proxy?
──────────────────────────────────────────────────────────────────────────────
  1. Browsers (Flutter Web / Chrome) cannot send custom HTTP headers during the
     WebSocket handshake — it is a browser security restriction, not a bug.
  2. IOWebSocketChannel (dart:io) does not compile on Flutter Web.
  3. Android emulator network stacks are fragile when connecting directly to
     external WS endpoints with custom headers.

Solution: Flutter connects to this endpoint using a plain WebSocket (passing
the Firebase token as a query param, which all platforms support).  The backend
then opens the privileged connection to OpenAI adding the Authorization header
server-side — keeping the OPENAI_API_KEY out of the client entirely.

Works identically on: Android emulator, iOS simulator, Chrome, Safari,
physical device, and production Railway deployment.
──────────────────────────────────────────────────────────────────────────────
"""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Optional

import aiohttp
from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect

from app.config import settings
from app.services.voice_auth_service import (
    _decode_uid_from_token,
    _try_init_firebase_admin,
    _verify_with_google_auth,
)

router = APIRouter()
logger = logging.getLogger(__name__)

_OPENAI_REALTIME_URL = "wss://api.openai.com/v1/realtime"
_DEFAULT_MODEL = "gpt-4o-mini-realtime-preview-2024-12-17"


# ── Token verification (query-param version, no HTTP Bearer header) ────────────

async def _verify_ws_token(token: str) -> Optional[str]:
    """Verify a raw Firebase ID token (passed as query param). Returns uid or None."""
    if not token:
        return None

    # Dev bypass — decodes payload without signature check
    if getattr(settings, "ENVIRONMENT", "") == "development" and getattr(
        settings, "DEV_BYPASS_AUTH", False
    ):
        uid = _decode_uid_from_token(token)
        logger.info(f"[voice_ws] DEV_BYPASS_AUTH uid={uid}")
        return uid

    # Try firebase_admin (full verification, prefers service account)
    if _try_init_firebase_admin():
        try:
            import firebase_admin.auth
            decoded = firebase_admin.auth.verify_id_token(token)
            uid = decoded.get("uid") or decoded.get("sub")
            if uid:
                return uid
        except Exception as exc:
            logger.warning(f"[voice_ws] firebase_admin verify failed: {exc}, trying google-auth")

    # Fallback: google-auth lightweight verification
    if getattr(settings, "FIREBASE_PROJECT_ID", ""):
        try:
            return _verify_with_google_auth(token)
        except Exception as exc:
            logger.warning(f"[voice_ws] google-auth verify failed: {exc}")

    return None


# ── Conversation history injection ────────────────────────────────────────────

async def _inject_conversation_history(
    openai_ws: aiohttp.ClientWebSocketResponse,
    uid: str,
    max_turns: int = 8,
) -> None:
    """Fetch the last N transcript turns from Firestore and inject them into
    the OpenAI Realtime session as conversation.item.create events.

    This gives Jarvis contextual memory of recent sessions without requiring
    the user to re-explain their situation every time.
    """
    try:
        if not _try_init_firebase_admin():
            logger.debug("[voice_ws] Firebase not ready — skipping history injection")
            return

        import firebase_admin.firestore

        db = firebase_admin.firestore.client()
        loop = asyncio.get_event_loop()

        def _fetch_turns() -> list[dict]:
            """Synchronous Firestore read — run in executor to avoid blocking."""
            try:
                docs = (
                    db.collection("voice_sessions")
                    .where("user_id", "==", uid)
                    .order_by("started_at", direction="DESCENDING")
                    .limit(3)
                    .stream()
                )
                all_turns: list[dict] = []
                for doc in docs:
                    data = doc.to_dict() or {}
                    turns = data.get("transcript_turns", [])
                    # Only keep completed sessions that have transcript data
                    if turns and data.get("ended_at"):
                        # Take at most 4 turns per session to stay within context
                        all_turns.extend(turns[-4:])
                    if len(all_turns) >= max_turns:
                        break
                return all_turns[-max_turns:]
            except Exception as exc:
                logger.warning(f"[voice_ws] Firestore history fetch failed: {exc}")
                return []

        turns = await loop.run_in_executor(None, _fetch_turns)

        if not turns:
            logger.debug(f"[voice_ws] No history found for uid={uid[:8]}…")
            return

        logger.info(f"[voice_ws] Injecting {len(turns)} history turns for uid={uid[:8]}…")

        for turn in turns:
            role = turn.get("role", "user")
            text = (turn.get("text") or "").strip()
            if not text:
                continue
            # Map to OpenAI Realtime conversation item
            # User turns use input_text; assistant turns use text
            content_type = "input_text" if role == "user" else "text"
            await openai_ws.send_json({
                "type": "conversation.item.create",
                "item": {
                    "type": "message",
                    "role": role,
                    "content": [{"type": content_type, "text": text}],
                },
            })

    except Exception as exc:
        # Non-fatal — log and continue without history
        logger.warning(f"[voice_ws] History injection failed (non-fatal): {exc}")


# ── Main WebSocket endpoint ────────────────────────────────────────────────────

@router.websocket("/realtime/ws")
async def realtime_proxy_ws(
    websocket: WebSocket,
    token: str = Query(default=""),
    model: str = Query(default=_DEFAULT_MODEL),
):
    """Proxy WebSocket traffic between the Flutter client and OpenAI Realtime API.

    Query params:
        token  — Firebase ID token (required)
        model  — OpenAI model string (optional, defaults to gpt-4o-realtime-preview)
    """
    # 1. Authenticate
    uid = await _verify_ws_token(token)
    if not uid:
        logger.warning("[voice_ws] Rejected unauthenticated connection")
        await websocket.close(code=4001, reason="Unauthorized")
        return

    # 2. Validate server config
    openai_key = getattr(settings, "OPENAI_API_KEY", "")
    if not openai_key:
        logger.error("[voice_ws] OPENAI_API_KEY is not configured")
        await websocket.close(code=4002, reason="Server misconfiguration: missing OpenAI key")
        return

    logger.info(f"[voice_ws] uid={uid} connecting, model={model}")
    await websocket.accept()

    # 3. Open privileged connection to OpenAI
    openai_url = f"{_OPENAI_REALTIME_URL}?model={model}"
    try:
        connector = aiohttp.TCPConnector(ssl=True)
        async with aiohttp.ClientSession(connector=connector) as http_session:
            async with http_session.ws_connect(
                openai_url,
                headers={
                    "Authorization": f"Bearer {openai_key}",
                    "OpenAI-Beta": "realtime=v1",
                },
                heartbeat=30,
            ) as openai_ws:
                logger.info(f"[voice_ws] uid={uid} — proxy open")

                # 4. Bidirectional pipe — both directions run concurrently
                results = await asyncio.gather(
                    _flutter_to_openai(websocket, openai_ws, uid),
                    _openai_to_flutter(openai_ws, websocket, uid),
                    return_exceptions=True,
                )
                for r in results:
                    if isinstance(r, Exception):
                        logger.debug(f"[voice_ws] pipe ended: {r}")

    except aiohttp.WSServerHandshakeError as exc:
        # OpenAI rejected the WebSocket upgrade (401 = bad key, 403 = tier/billing)
        logger.error(
            f"[voice_ws] OpenAI handshake rejected uid={uid} — "
            f"status={exc.status} message={exc.message!r} headers={dict(exc.headers or {})}"
        )
        try:
            await websocket.send_text(
                f'{{"type":"error","error":{{"message":"OpenAI rejected connection: '
                f'HTTP {exc.status} — check API key and billing tier."}}}}'
            )
            await websocket.close(code=1011)
        except Exception:
            pass
    except aiohttp.ClientConnectorError as exc:
        logger.error(f"[voice_ws] Cannot reach OpenAI for uid={uid}: {exc}")
        try:
            await websocket.send_text(
                '{"type":"error","error":{"message":"Cannot connect to OpenAI Realtime API. '
                'Check OPENAI_API_KEY and network."}}'
            )
            await websocket.close(code=1011)
        except Exception:
            pass
    except Exception as exc:
        logger.error(f"[voice_ws] Unexpected error uid={uid}: {exc}", exc_info=True)
        try:
            await websocket.close(code=1011, reason="Internal proxy error")
        except Exception:
            pass

    logger.info(f"[voice_ws] uid={uid} session closed")


async def _flutter_to_openai(
    websocket: WebSocket,
    openai_ws: aiohttp.ClientWebSocketResponse,
    uid: str,
) -> None:
    """Forward text/binary messages from the Flutter client to OpenAI."""
    try:
        while True:
            msg = await websocket.receive()
            msg_type = msg.get("type")
            if msg_type == "websocket.disconnect":
                break
            if msg_type == "websocket.receive":
                if msg.get("text"):
                    await openai_ws.send_str(msg["text"])
                elif msg.get("bytes"):
                    await openai_ws.send_bytes(msg["bytes"])
    except WebSocketDisconnect:
        pass
    except Exception as exc:
        logger.debug(f"[voice_ws] flutter→openai error uid={uid}: {exc}")
    finally:
        await openai_ws.close()


async def _openai_to_flutter(
    openai_ws: aiohttp.ClientWebSocketResponse,
    websocket: WebSocket,
    uid: str,
) -> None:
    """Forward messages from OpenAI back to the Flutter client.

    Special handling for session.created: we intercept it to inject conversation
    history before forwarding, so Jarvis has context of past sessions on startup.
    """
    _history_injected = False
    try:
        async for msg in openai_ws:
            if msg.type == aiohttp.WSMsgType.TEXT:
                # Intercept session.created to inject history
                if not _history_injected:
                    try:
                        payload = json.loads(msg.data)
                        if payload.get("type") == "session.created":
                            _history_injected = True
                            # Inject history BEFORE forwarding session.created to Flutter
                            # so the client never sees the session in a pre-history state.
                            await _inject_conversation_history(openai_ws, uid)
                    except (json.JSONDecodeError, Exception):
                        pass  # Malformed message — just forward it

                await websocket.send_text(msg.data)

            elif msg.type == aiohttp.WSMsgType.BINARY:
                await websocket.send_bytes(msg.data)
            elif msg.type == aiohttp.WSMsgType.ERROR:
                # Log the full JSON error body so we can diagnose Tier/Billing issues
                error_body = msg.data if msg.data else str(openai_ws.exception())
                logger.warning(
                    f"[voice_ws] OpenAI WS error uid={uid} — "
                    f"full_body={error_body!r} exception={openai_ws.exception()}"
                )
                break
            elif msg.type == aiohttp.WSMsgType.CLOSED:
                break
    except Exception as exc:
        logger.debug(f"[voice_ws] openai→flutter error uid={uid}: {exc}")
    finally:
        try:
            await websocket.close()
        except Exception:
            pass
