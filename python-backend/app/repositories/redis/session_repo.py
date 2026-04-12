"""Redis repository for live voice session state (working memory layer).

Key pattern : voice_session:{session_id}    TTL = REDIS_TTL_SESSION (3 h)
Key pattern : user_ctx:{uid}                TTL = REDIS_TTL_CTX (30 min)
Key pattern : voice_lock:{uid}              TTL = 1800 s (prevents double-open)

The repo is a singleton — call get_session_repo() to obtain the shared instance.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Optional

import redis.asyncio as aioredis

from app.config import settings
from app.models.voice_session import SessionState

logger = logging.getLogger(__name__)

_redis_client: Optional[aioredis.Redis] = None


def _get_client() -> aioredis.Redis:
    global _redis_client
    if _redis_client is None:
        _redis_client = aioredis.from_url(
            settings.REDIS_URL,
            encoding="utf-8",
            decode_responses=True,
        )
    return _redis_client


class VoiceSessionRepo:
    """Async Redis repository for SessionState objects."""

    _KEY_PREFIX = "voice_session"
    _CTX_PREFIX = "user_ctx"
    _LOCK_PREFIX = "voice_lock"

    def __init__(self) -> None:
        self._r = _get_client()

    # ── Session state ────────────────────────────────────────────────

    async def get(self, session_id: str) -> Optional[SessionState]:
        raw = await self._r.get(f"{self._KEY_PREFIX}:{session_id}")
        if not raw:
            return None
        try:
            return SessionState.model_validate_json(raw)
        except Exception as exc:
            logger.warning(f"[session_repo] Deserialise failed for {session_id}: {exc}")
            return None

    async def set(
        self,
        session_id: str,
        state: SessionState,
        ttl: Optional[int] = None,
    ) -> None:
        ttl = ttl or settings.REDIS_TTL_SESSION
        await self._r.setex(
            f"{self._KEY_PREFIX}:{session_id}",
            ttl,
            state.model_dump_json(),
        )

    async def delete(self, session_id: str) -> None:
        await self._r.delete(f"{self._KEY_PREFIX}:{session_id}")

    # ── User context (active screen / symbol / lesson) ───────────────

    async def set_user_ctx(self, uid: str, ctx: dict) -> None:
        await self._r.setex(
            f"{self._CTX_PREFIX}:{uid}",
            settings.REDIS_TTL_CTX,
            json.dumps(ctx),
        )

    async def get_user_ctx(self, uid: str) -> dict:
        raw = await self._r.get(f"{self._CTX_PREFIX}:{uid}")
        return json.loads(raw) if raw else {}

    # ── Session lock (prevents double-open) ──────────────────────────

    async def acquire_lock(self, uid: str, session_id: str, ttl: int = 1800) -> bool:
        """Returns True if lock was acquired (no active session for this user)."""
        key = f"{self._LOCK_PREFIX}:{uid}"
        # SET NX — only sets if key doesn't exist
        result = await self._r.set(key, session_id, ex=ttl, nx=True)
        return result is True

    async def release_lock(self, uid: str) -> None:
        await self._r.delete(f"{self._LOCK_PREFIX}:{uid}")

    async def get_lock(self, uid: str) -> Optional[str]:
        return await self._r.get(f"{self._LOCK_PREFIX}:{uid}")


# Singleton
_repo: Optional[VoiceSessionRepo] = None


def get_session_repo() -> VoiceSessionRepo:
    global _repo
    if _repo is None:
        _repo = VoiceSessionRepo()
    return _repo
