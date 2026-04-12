"""Redis repository for voice usage counters (metering layer).

Key pattern: usage:{uid}:{YYYY-MM}   TTL = REDIS_TTL_USAGE (35 days)

Counters are also mirrored to Firestore at session-end for durable reporting,
but Redis is the authoritative source for real-time tier enforcement.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Optional

import redis.asyncio as aioredis

from app.config import settings
from app.repositories.redis.session_repo import _get_client

logger = logging.getLogger(__name__)

_KEY = "usage"

# Tier limits — keyed by the subscription_tier values Flutter writes to Firestore.
# Flutter writes "free" or "pro".  "paid" is kept for backward compatibility.
TIER_LIMITS = {
    "free":             {"voice_seconds": 600,  "sessions": 3},    # 10 min / month
    "pro":              {"voice_seconds": 3600, "sessions": 60},   # 60 min / month
    "paid":             {"voice_seconds": 3600, "sessions": 60},   # legacy alias for "pro"
    "prototype_owner":  {"voice_seconds": None, "sessions": None}, # unlimited
}


class UsageCounterRepo:
    def __init__(self) -> None:
        self._r = _get_client()

    def _key(self, uid: str, period: str) -> str:
        return f"{_KEY}:{uid}:{period}"

    def _current_period(self) -> str:
        return datetime.now(timezone.utc).strftime("%Y-%m")

    async def get(self, uid: str, period: Optional[str] = None) -> dict:
        period = period or self._current_period()
        raw = await self._r.get(self._key(uid, period))
        if raw:
            return json.loads(raw)
        return {"voice_seconds": 0.0, "sessions": 0, "text_requests": 0}

    async def increment_session(self, uid: str, voice_seconds: float) -> dict:
        period = self._current_period()
        key = self._key(uid, period)
        raw = await self._r.get(key)
        data = json.loads(raw) if raw else {"voice_seconds": 0.0, "sessions": 0, "text_requests": 0}
        data["voice_seconds"] = round(data["voice_seconds"] + voice_seconds, 2)
        data["sessions"] += 1
        await self._r.setex(key, settings.REDIS_TTL_USAGE, json.dumps(data))
        return data

    async def check_can_start(self, uid: str, tier: str = "free") -> tuple[bool, str]:
        """Returns (allowed, reason).  reason is empty string if allowed."""
        limits = TIER_LIMITS.get(tier, TIER_LIMITS["free"])
        if limits["voice_seconds"] is None:
            return True, ""  # unlimited tier

        data = await self.get(uid)
        if data["sessions"] >= limits["sessions"]:
            return False, f"Daily session limit reached ({limits['sessions']} sessions)."
        if data["voice_seconds"] >= limits["voice_seconds"]:
            return False, f"Voice time limit reached ({limits['voice_seconds']//60:.0f} minutes)."
        return True, ""


_repo: Optional[UsageCounterRepo] = None


def get_usage_repo() -> UsageCounterRepo:
    global _repo
    if _repo is None:
        _repo = UsageCounterRepo()
    return _repo
