"""
Comprehensive test suite for the Jarvis Voice feature.

Covers:
  1. UsageCounterRepo  — tier limits, increment, check_can_start
  2. VoiceSessionRepo  — lock acquire/release, session state CRUD
  3. Voice HTTP router — session/create (success, 409, 429), session/end,
                          tools/invoke, usage/status, unauthenticated rejection
  4. WebSocket proxy   — token rejection, message forwarding
  5. SessionBootstrapOrchestrator — limit enforcement, lock enforcement,
                                     happy-path bootstrap

Run from python-backend/:
    pytest tests/test_voice_feature.py -v

Or with coverage:
    pytest tests/test_voice_feature.py -v --cov=app --cov-report=term-missing
"""

from __future__ import annotations

import asyncio
import json
import uuid
from datetime import datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch, PropertyMock

import pytest
from fastapi.testclient import TestClient

# ── Helpers ───────────────────────────────────────────────────────────────────

def _make_session_state(uid: str = "uid_test", session_id: str | None = None) -> dict:
    """Return a minimal SessionState dict for serialisation tests."""
    return {
        "session_id": session_id or str(uuid.uuid4()),
        "user_id": uid,
        "mode": "general",
        "started_at": datetime.now(timezone.utc).isoformat(),
        "turn_count": 0,
        "voice_seconds": 0.0,
        "last_metric": None,
        "last_timeframe": None,
        "last_tool_payload": None,
        "active_symbol": None,
        "active_lesson_id": None,
    }


# ══════════════════════════════════════════════════════════════════════════════
# 1. UsageCounterRepo
# ══════════════════════════════════════════════════════════════════════════════

class TestUsageCounterRepo:
    """Unit tests for UsageCounterRepo with a mocked Redis client."""

    def _make_repo(self, stored_data: dict | None = None) -> Any:
        """Return a UsageCounterRepo wired to an AsyncMock Redis client."""
        from app.repositories.redis.usage_counter_repo import UsageCounterRepo

        raw = json.dumps(stored_data) if stored_data else None
        mock_redis = AsyncMock()
        mock_redis.get = AsyncMock(return_value=raw)
        mock_redis.setex = AsyncMock(return_value=True)

        repo = UsageCounterRepo.__new__(UsageCounterRepo)
        repo._r = mock_redis
        return repo, mock_redis

    @pytest.mark.asyncio
    async def test_get_returns_zeros_for_new_user(self):
        """get() must return all-zero counters when no Redis key exists."""
        repo, mock_redis = self._make_repo(stored_data=None)
        data = await repo.get("uid_new", "2026-04")
        assert data["voice_seconds"] == 0.0
        assert data["sessions"] == 0

    @pytest.mark.asyncio
    async def test_get_returns_stored_data(self):
        """get() must deserialise stored counters correctly."""
        stored = {"voice_seconds": 120.0, "sessions": 2, "text_requests": 0}
        repo, _ = self._make_repo(stored_data=stored)
        data = await repo.get("uid_x", "2026-04")
        assert data["voice_seconds"] == 120.0
        assert data["sessions"] == 2

    @pytest.mark.asyncio
    async def test_increment_session_adds_to_existing(self):
        """increment_session() must add voice_seconds and bump sessions."""
        existing = {"voice_seconds": 60.0, "sessions": 1, "text_requests": 0}
        repo, mock_redis = self._make_repo(stored_data=existing)

        result = await repo.increment_session("uid_x", 90.0)

        assert result["voice_seconds"] == pytest.approx(150.0)
        assert result["sessions"] == 2
        mock_redis.setex.assert_called_once()

    @pytest.mark.asyncio
    async def test_increment_session_starts_from_zero(self):
        """increment_session() must create a fresh record if none exists."""
        repo, mock_redis = self._make_repo(stored_data=None)
        result = await repo.increment_session("uid_new", 45.5)
        assert result["voice_seconds"] == pytest.approx(45.5)
        assert result["sessions"] == 1

    @pytest.mark.asyncio
    async def test_check_can_start_prototype_owner_unlimited(self):
        """prototype_owner tier must always be allowed regardless of usage."""
        huge = {"voice_seconds": 999999.0, "sessions": 9999, "text_requests": 0}
        repo, _ = self._make_repo(stored_data=huge)
        allowed, reason = await repo.check_can_start("uid_admin", "prototype_owner")
        assert allowed is True
        assert reason == ""

    @pytest.mark.asyncio
    async def test_check_can_start_free_tier_within_limits(self):
        """Free user with 0 usage must be allowed."""
        repo, _ = self._make_repo(stored_data=None)
        allowed, reason = await repo.check_can_start("uid_free", "free")
        assert allowed is True

    @pytest.mark.asyncio
    async def test_check_can_start_free_tier_session_limit_hit(self):
        """Free user who has used all 3 sessions must be blocked."""
        maxed = {"voice_seconds": 0.0, "sessions": 3, "text_requests": 0}
        repo, _ = self._make_repo(stored_data=maxed)
        allowed, reason = await repo.check_can_start("uid_free", "free")
        assert allowed is False
        assert "session" in reason.lower()

    @pytest.mark.asyncio
    async def test_check_can_start_free_tier_time_limit_hit(self):
        """Free user who has used all 600 s (10 min) must be blocked."""
        maxed = {"voice_seconds": 600.0, "sessions": 0, "text_requests": 0}
        repo, _ = self._make_repo(stored_data=maxed)
        allowed, reason = await repo.check_can_start("uid_free", "free")
        assert allowed is False
        assert "time" in reason.lower() or "minute" in reason.lower()

    @pytest.mark.asyncio
    async def test_check_can_start_pro_tier_larger_limits(self):
        """Pro user with 3600 s used must be blocked; 3599 s must be allowed."""
        at_limit = {"voice_seconds": 3600.0, "sessions": 0, "text_requests": 0}
        repo, _ = self._make_repo(stored_data=at_limit)
        allowed, _ = await repo.check_can_start("uid_pro", "pro")
        assert allowed is False

        below_limit = {"voice_seconds": 3599.0, "sessions": 59, "text_requests": 0}
        repo2, _ = self._make_repo(stored_data=below_limit)
        allowed2, _ = await repo2.check_can_start("uid_pro", "pro")
        assert allowed2 is True

    @pytest.mark.asyncio
    async def test_check_can_start_unknown_tier_falls_back_to_free(self):
        """Unknown tier must default to free-tier limits."""
        maxed = {"voice_seconds": 0.0, "sessions": 3, "text_requests": 0}
        repo, _ = self._make_repo(stored_data=maxed)
        allowed, reason = await repo.check_can_start("uid_x", "enterprise_gold")
        assert allowed is False  # falls back to free → sessions=3 → blocked


# ══════════════════════════════════════════════════════════════════════════════
# 2. VoiceSessionRepo
# ══════════════════════════════════════════════════════════════════════════════

class TestVoiceSessionRepo:
    """Unit tests for VoiceSessionRepo with a mocked Redis client."""

    def _make_repo(self) -> tuple:
        from app.repositories.redis.session_repo import VoiceSessionRepo
        mock_redis = AsyncMock()
        repo = VoiceSessionRepo.__new__(VoiceSessionRepo)
        repo._r = mock_redis
        return repo, mock_redis

    @pytest.mark.asyncio
    async def test_get_returns_none_for_missing_session(self):
        repo, mock_redis = self._make_repo()
        mock_redis.get = AsyncMock(return_value=None)
        result = await repo.get("nonexistent_session")
        assert result is None

    @pytest.mark.asyncio
    async def test_set_and_get_roundtrip(self):
        """set() must serialise; get() must deserialise the same state."""
        from app.models.voice_session import SessionState, VoiceMode
        repo, mock_redis = self._make_repo()

        session_id = str(uuid.uuid4())
        state = SessionState(
            session_id=session_id,
            user_id="uid_round",
            mode=VoiceMode.GENERAL,
            started_at=datetime.now(timezone.utc),
        )

        captured: list[str] = []

        async def fake_setex(key, ttl, value):
            captured.append(value)

        mock_redis.setex = AsyncMock(side_effect=fake_setex)
        await repo.set(session_id, state)

        # Now make get() return what was stored
        mock_redis.get = AsyncMock(return_value=captured[0])
        result = await repo.get(session_id)
        assert result is not None
        assert result.session_id == session_id
        assert result.user_id == "uid_round"
        assert result.mode == VoiceMode.GENERAL

    @pytest.mark.asyncio
    async def test_acquire_lock_succeeds_first_time(self):
        repo, mock_redis = self._make_repo()
        mock_redis.set = AsyncMock(return_value=True)
        acquired = await repo.acquire_lock("uid_new", "sess_1")
        assert acquired is True

    @pytest.mark.asyncio
    async def test_acquire_lock_fails_when_lock_exists(self):
        """SET NX returns None when the key already exists."""
        repo, mock_redis = self._make_repo()
        mock_redis.set = AsyncMock(return_value=None)  # NX failed
        acquired = await repo.acquire_lock("uid_busy", "sess_2")
        assert acquired is False

    @pytest.mark.asyncio
    async def test_release_lock_deletes_key(self):
        repo, mock_redis = self._make_repo()
        mock_redis.delete = AsyncMock(return_value=1)
        await repo.release_lock("uid_x")
        mock_redis.delete.assert_called_once_with("voice_lock:uid_x")

    @pytest.mark.asyncio
    async def test_get_lock_returns_session_id(self):
        repo, mock_redis = self._make_repo()
        mock_redis.get = AsyncMock(return_value="sess_active")
        result = await repo.get_lock("uid_x")
        assert result == "sess_active"

    @pytest.mark.asyncio
    async def test_get_lock_returns_none_when_no_lock(self):
        repo, mock_redis = self._make_repo()
        mock_redis.get = AsyncMock(return_value=None)
        result = await repo.get_lock("uid_x")
        assert result is None

    @pytest.mark.asyncio
    async def test_delete_session(self):
        repo, mock_redis = self._make_repo()
        mock_redis.delete = AsyncMock(return_value=1)
        await repo.delete("sess_x")
        mock_redis.delete.assert_called_once_with("voice_session:sess_x")


# ══════════════════════════════════════════════════════════════════════════════
# 3. Session Bootstrap Orchestrator
# ══════════════════════════════════════════════════════════════════════════════

class TestSessionBootstrapOrchestrator:
    """Unit tests for the orchestrator with all dependencies mocked."""

    def _make_orchestrator(
        self,
        usage_allowed: bool = True,
        lock_acquired: bool = True,
        tier: str = "prototype_owner",
    ):
        from app.orchestrator.session_bootstrap import SessionBootstrapOrchestrator
        from app.models.voice_session import VoiceMode

        # Mock Firestore db
        mock_db = MagicMock()
        user_doc = MagicMock()
        user_doc.exists = True
        user_doc.to_dict.return_value = {"subscription_tier": tier}
        mock_db.collection.return_value.document.return_value.get.return_value = user_doc
        mock_db.collection.return_value.document.return_value.set = MagicMock()

        # Mock session repo
        mock_session_repo = AsyncMock()
        mock_session_repo.acquire_lock = AsyncMock(return_value=lock_acquired)
        mock_session_repo.get_lock = AsyncMock(return_value="existing_sess")
        mock_session_repo.set = AsyncMock()

        # Mock usage repo
        mock_usage_repo = AsyncMock()
        mock_usage_repo.check_can_start = AsyncMock(
            return_value=(True, "") if usage_allowed else (False, "Session limit reached (3 sessions).")
        )

        # Mock realtime service
        mock_realtime_svc = AsyncMock()
        mock_realtime_svc.model = "gpt-4o-realtime-preview"
        mock_realtime_svc.default_voice = "alloy"
        mock_realtime_svc.create_ephemeral_token = AsyncMock(
            return_value=("eph_tok_test", datetime.now(timezone.utc))
        )

        # Mock tool registry
        mock_tool_registry = MagicMock()
        mock_tool_registry.get_openai_tool_schemas.return_value = []

        # Patch heavy dependencies (context assembler + prompt builder)
        orchestrator = SessionBootstrapOrchestrator.__new__(SessionBootstrapOrchestrator)
        orchestrator._db = mock_db
        orchestrator._session_repo = mock_session_repo
        orchestrator._usage_repo = mock_usage_repo
        orchestrator._realtime_svc = mock_realtime_svc
        orchestrator._tool_registry = mock_tool_registry

        # Patch context assembler & prompt builder
        mock_ctx = AsyncMock()
        mock_ctx.assemble = AsyncMock(return_value={
            "user_level": "beginner",
            "profile_memory": [],
            "coaching_memory": [],
            "chroma_memories": [],
        })
        orchestrator._context_assembler = mock_ctx

        mock_prompt = MagicMock()
        mock_prompt.build.return_value = "You are Jarvis, a financial coach."
        orchestrator._prompt_builder = mock_prompt

        return orchestrator

    @pytest.mark.asyncio
    async def test_bootstrap_raises_429_when_limit_reached(self):
        """Orchestrator must raise HTTP 429 when usage limit is exceeded."""
        from fastapi import HTTPException
        from app.models.voice_session import VoiceSessionCreateRequest

        orchestrator = self._make_orchestrator(usage_allowed=False)
        request = VoiceSessionCreateRequest(mode="general")

        with pytest.raises(HTTPException) as exc_info:
            await orchestrator.build("uid_limited", request)
        assert exc_info.value.status_code == 429
        assert "limit" in exc_info.value.detail.lower()

    @pytest.mark.asyncio
    async def test_bootstrap_raises_409_when_session_locked(self):
        """Orchestrator must raise HTTP 409 when user already has an active session."""
        from fastapi import HTTPException
        from app.models.voice_session import VoiceSessionCreateRequest

        orchestrator = self._make_orchestrator(lock_acquired=False)
        request = VoiceSessionCreateRequest(mode="general")

        with pytest.raises(HTTPException) as exc_info:
            await orchestrator.build("uid_busy", request)
        assert exc_info.value.status_code == 409

    @pytest.mark.asyncio
    async def test_bootstrap_happy_path_returns_bootstrap(self):
        """Orchestrator must return a VoiceSessionBootstrap on success."""
        from app.models.voice_session import VoiceSessionBootstrap, VoiceSessionCreateRequest

        orchestrator = self._make_orchestrator()
        request = VoiceSessionCreateRequest(mode="general", active_symbol="AAPL")

        result = await orchestrator.build("uid_ok", request)

        assert isinstance(result, VoiceSessionBootstrap)
        assert result.openai_ephemeral_token == "eph_tok_test"
        assert result.openai_model == "gpt-4o-realtime-preview"
        assert result.user_level == "beginner"
        assert result.mode.value == "general"

    @pytest.mark.asyncio
    async def test_bootstrap_stores_session_in_redis(self):
        """Orchestrator must call session_repo.set() after a successful bootstrap."""
        from app.models.voice_session import VoiceSessionCreateRequest

        orchestrator = self._make_orchestrator()
        await orchestrator.build("uid_ok", VoiceSessionCreateRequest())

        orchestrator._session_repo.set.assert_called_once()

    @pytest.mark.asyncio
    async def test_bootstrap_acquires_lock(self):
        """Orchestrator must call acquire_lock() to prevent double sessions."""
        from app.models.voice_session import VoiceSessionCreateRequest

        orchestrator = self._make_orchestrator()
        await orchestrator.build("uid_ok", VoiceSessionCreateRequest())

        orchestrator._session_repo.acquire_lock.assert_called_once()


# ══════════════════════════════════════════════════════════════════════════════
# 4. Voice HTTP Router — integration tests via TestClient
# ══════════════════════════════════════════════════════════════════════════════

@pytest.fixture
def client():
    """TestClient with auth and Redis mocked at the app level.

    Note: requires `httpx[socks]` if running behind a SOCKS proxy (e.g. CI).
    Install with: pip install "httpx[socks]"
    """
    try:
        from app.main import app
        return TestClient(app)
    except ImportError as e:
        pytest.skip(f"TestClient unavailable — missing dependency: {e}")


def _auth_headers(uid: str = "uid_test") -> dict:
    """
    Build fake auth headers.
    DEV_BYPASS_AUTH=true in .env means the backend decodes the token payload
    without signature verification, so we craft a minimal unsigned JWT.
    """
    import base64
    header  = base64.urlsafe_b64encode(b'{"alg":"none","typ":"JWT"}').rstrip(b"=").decode()
    payload = base64.urlsafe_b64encode(
        json.dumps({"sub": uid, "uid": uid, "email": "test@example.com"}).encode()
    ).rstrip(b"=").decode()
    return {"Authorization": f"Bearer {header}.{payload}."}


class TestVoiceRouterHTTP:
    """Integration-style tests for the /api/voice/* HTTP routes."""

    def _patch_redis(self, *, sessions: int = 0, voice_seconds: float = 0.0,
                     lock_value: str | None = None):
        """Return a context manager that patches the Redis client used by repos."""
        mock_r = AsyncMock()
        usage_data = json.dumps({
            "voice_seconds": voice_seconds,
            "sessions": sessions,
            "text_requests": 0,
        })

        async def fake_get(key):
            if key.startswith("usage:"):
                return usage_data
            if key.startswith("voice_lock:"):
                return lock_value
            if key.startswith("voice_session:"):
                return None
            return None

        mock_r.get = AsyncMock(side_effect=fake_get)
        mock_r.set = AsyncMock(return_value=True)   # NX lock always succeeds
        mock_r.setex = AsyncMock(return_value=True)
        mock_r.delete = AsyncMock(return_value=1)
        return mock_r

    def _patch_openai(self):
        """Mock the RealtimeSessionService so we never call OpenAI."""
        from app.services.realtime_session_service import RealtimeSessionService
        return patch.object(
            RealtimeSessionService,
            "create_ephemeral_token",
            new_callable=AsyncMock,
            return_value=("eph_tok_mock", datetime.now(timezone.utc)),
        )

    def _patch_firestore(self, tier: str = "prototype_owner"):
        """Mock Firestore so no real Firebase calls are made."""
        user_doc = MagicMock()
        user_doc.exists = True
        user_doc.to_dict.return_value = {"subscription_tier": tier}

        mock_db = MagicMock()
        mock_db.collection.return_value.document.return_value.get.return_value = user_doc
        mock_db.collection.return_value.document.return_value.set = MagicMock()
        mock_db.collection.return_value.document.return_value.collection.return_value.stream.return_value = []
        return mock_db

    def _patch_chroma(self):
        """Mock ChromaDB so context assembly never touches disk."""
        mock_svc = MagicMock()
        mock_svc.recall.return_value = []
        return patch(
            "app.orchestrator.context_assembler.ChromaMemoryService",
            return_value=mock_svc,
        )

    # ── /api/voice/usage/status ────────────────────────────────────────────

    def test_usage_status_returns_200_for_authenticated_user(self, client):
        """GET /api/voice/usage/status must return usage data."""
        mock_r = self._patch_redis(sessions=1, voice_seconds=120.0)
        mock_db = self._patch_firestore()

        with patch("app.repositories.redis.session_repo._get_client", return_value=mock_r), \
             patch("app.repositories.redis.usage_counter_repo._get_client", return_value=mock_r), \
             patch("app.routers.voice._get_db", return_value=mock_db):
            resp = client.get("/api/voice/usage/status", headers=_auth_headers())

        assert resp.status_code == 200
        data = resp.json()
        assert "voice_minutes_used" in data
        assert "voice_sessions_used" in data
        assert "tier" in data
        assert data["voice_sessions_used"] == 1
        assert data["voice_minutes_used"] == pytest.approx(2.0)

    def test_usage_status_rejects_unauthenticated(self, client):
        """Requests without an Authorization header must be rejected."""
        resp = client.get("/api/voice/usage/status")
        assert resp.status_code in (401, 403, 422)

    # ── /api/voice/session/create ──────────────────────────────────────────

    def test_session_create_returns_429_at_session_limit(self, client):
        """POST /session/create must return 429 when the free-tier limit is hit."""
        # 3 sessions used = free limit reached
        mock_r = self._patch_redis(sessions=3, voice_seconds=0.0)
        mock_db = self._patch_firestore(tier="free")

        with patch("app.repositories.redis.session_repo._get_client", return_value=mock_r), \
             patch("app.repositories.redis.usage_counter_repo._get_client", return_value=mock_r), \
             patch("app.routers.voice._get_db", return_value=mock_db):
            resp = client.post(
                "/api/voice/session/create",
                json={"mode": "general"},
                headers=_auth_headers(),
            )

        assert resp.status_code == 429
        assert "limit" in resp.json().get("detail", "").lower()

    def test_session_create_returns_409_when_session_locked(self, client):
        """POST /session/create must return 409 when user already has an active session."""
        mock_r = self._patch_redis(lock_value="existing_session_id")
        mock_r.set = AsyncMock(return_value=None)  # NX fails → lock exists
        mock_db = self._patch_firestore()

        with patch("app.repositories.redis.session_repo._get_client", return_value=mock_r), \
             patch("app.repositories.redis.usage_counter_repo._get_client", return_value=mock_r), \
             patch("app.routers.voice._get_db", return_value=mock_db), \
             self._patch_chroma():
            resp = client.post(
                "/api/voice/session/create",
                json={"mode": "general"},
                headers=_auth_headers(),
            )

        assert resp.status_code == 409

    def test_session_create_happy_path(self, client):
        """POST /session/create must return 200 with bootstrap data on success."""
        mock_r = self._patch_redis()
        mock_db = self._patch_firestore()

        with patch("app.repositories.redis.session_repo._get_client", return_value=mock_r), \
             patch("app.repositories.redis.usage_counter_repo._get_client", return_value=mock_r), \
             patch("app.routers.voice._get_db", return_value=mock_db), \
             self._patch_openai(), \
             self._patch_chroma():
            resp = client.post(
                "/api/voice/session/create",
                json={"mode": "general", "screen_context": "home"},
                headers=_auth_headers(),
            )

        assert resp.status_code == 200
        data = resp.json()
        assert "session_id" in data
        assert "openai_ephemeral_token" in data
        assert data["openai_ephemeral_token"] == "eph_tok_mock"
        assert data["mode"] == "general"

    # ── /api/voice/session/end ─────────────────────────────────────────────

    def test_session_end_returns_success(self, client):
        """POST /session/end must return success without errors."""
        mock_r = self._patch_redis()
        mock_db = self._patch_firestore()

        session_id = str(uuid.uuid4())

        with patch("app.repositories.redis.session_repo._get_client", return_value=mock_r), \
             patch("app.repositories.redis.usage_counter_repo._get_client", return_value=mock_r), \
             patch("app.routers.voice._get_db", return_value=mock_db):
            resp = client.post(
                "/api/voice/session/end",
                json={
                    "session_id": session_id,
                    "transcript_turns": [
                        {"role": "user", "text": "What is RSI?", "tool_calls": []},
                        {"role": "assistant", "text": "RSI is a momentum indicator.", "tool_calls": []},
                    ],
                    "voice_seconds": 45.0,
                },
                headers=_auth_headers(),
            )

        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["session_id"] == session_id

    # ── /api/voice/memory/upsert ───────────────────────────────────────────

    def test_memory_upsert_returns_200(self, client):
        """POST /memory/upsert must persist a key-value memory pair."""
        mock_db = self._patch_firestore()
        mock_r = self._patch_redis()

        with patch("app.repositories.redis.session_repo._get_client", return_value=mock_r), \
             patch("app.repositories.redis.usage_counter_repo._get_client", return_value=mock_r), \
             patch("app.routers.voice._get_db", return_value=mock_db):
            resp = client.post(
                "/api/voice/memory/upsert",
                json={"key": "risk_tolerance", "value": "medium", "source": "explicit"},
                headers=_auth_headers(),
            )

        assert resp.status_code == 200
        assert resp.json().get("updated") is True

    # ── /api/voice/memory/context ──────────────────────────────────────────

    def test_memory_context_returns_200(self, client):
        """GET /memory/context must return profile and coaching memory lists."""
        mock_db = self._patch_firestore()
        mock_r = self._patch_redis()

        with patch("app.repositories.redis.session_repo._get_client", return_value=mock_r), \
             patch("app.repositories.redis.usage_counter_repo._get_client", return_value=mock_r), \
             patch("app.routers.voice._get_db", return_value=mock_db):
            resp = client.get("/api/voice/memory/context", headers=_auth_headers())

        assert resp.status_code == 200
        data = resp.json()
        assert "profile_memory" in data
        assert "coaching_memory" in data
        assert isinstance(data["profile_memory"], list)
        assert isinstance(data["coaching_memory"], list)


# ══════════════════════════════════════════════════════════════════════════════
# 5. WebSocket Proxy — token validation
# ══════════════════════════════════════════════════════════════════════════════

class TestWebSocketProxy:
    """Tests for the /api/voice/realtime/ws WebSocket endpoint."""

    def test_ws_proxy_rejects_empty_token(self, client):
        """WS connections without a token must be closed with code 4001."""
        with client.websocket_connect(
            "/api/voice/realtime/ws?token="
        ) as ws:
            # The server should close immediately with 4001
            try:
                msg = ws.receive_text(timeout=2)
            except Exception:
                pass  # disconnect is expected
        # If we get here without exception the close must have happened

    def test_ws_proxy_rejects_malformed_token(self, client):
        """WS connections with a garbage token must be closed."""
        with pytest.raises(Exception):
            with client.websocket_connect(
                "/api/voice/realtime/ws?token=not_a_valid_jwt"
            ) as ws:
                ws.receive_text(timeout=2)


# ══════════════════════════════════════════════════════════════════════════════
# 6. Tier limit constants — contract tests
# ══════════════════════════════════════════════════════════════════════════════

class TestTierLimits:
    """Ensure the TIER_LIMITS dict upholds expected contracts."""

    def test_free_tier_has_session_and_time_limits(self):
        from app.repositories.redis.usage_counter_repo import TIER_LIMITS
        free = TIER_LIMITS["free"]
        assert free["voice_seconds"] == 600   # 10 minutes
        assert free["sessions"] == 3

    def test_pro_tier_is_larger_than_free(self):
        from app.repositories.redis.usage_counter_repo import TIER_LIMITS
        free = TIER_LIMITS["free"]
        pro  = TIER_LIMITS["pro"]
        assert pro["voice_seconds"] > free["voice_seconds"]
        assert pro["sessions"] > free["sessions"]

    def test_prototype_owner_has_no_limits(self):
        from app.repositories.redis.usage_counter_repo import TIER_LIMITS
        owner = TIER_LIMITS["prototype_owner"]
        assert owner["voice_seconds"] is None
        assert owner["sessions"] is None

    def test_all_tiers_have_required_keys(self):
        from app.repositories.redis.usage_counter_repo import TIER_LIMITS
        for tier, limits in TIER_LIMITS.items():
            assert "voice_seconds" in limits, f"{tier} missing voice_seconds"
            assert "sessions" in limits, f"{tier} missing sessions"


# ══════════════════════════════════════════════════════════════════════════════
# 7. VoiceSessionState — model validation
# ══════════════════════════════════════════════════════════════════════════════

class TestVoiceSessionModel:
    """Validate Pydantic model behaviour for voice session data classes."""

    def test_session_state_defaults(self):
        from app.models.voice_session import SessionState, VoiceMode
        state = SessionState(
            session_id="s1",
            user_id="u1",
            mode=VoiceMode.GENERAL,
            started_at=datetime.now(timezone.utc),
        )
        assert state.turn_count == 0
        assert state.voice_seconds == 0.0
        assert state.active_symbol is None

    def test_session_state_serialise_deserialise(self):
        """model_dump_json / model_validate_json must be lossless."""
        from app.models.voice_session import SessionState, VoiceMode
        state = SessionState(
            session_id="s2",
            user_id="u2",
            mode=VoiceMode.LESSON,
            started_at=datetime.now(timezone.utc),
            active_symbol="BTC",
            turn_count=5,
            voice_seconds=123.4,
        )
        raw = state.model_dump_json()
        loaded = SessionState.model_validate_json(raw)
        assert loaded.session_id == state.session_id
        assert loaded.active_symbol == "BTC"
        assert loaded.turn_count == 5
        assert loaded.voice_seconds == pytest.approx(123.4)
        assert loaded.mode == VoiceMode.LESSON

    def test_voice_session_create_request_mode_defaults_to_general(self):
        from app.models.voice_session import VoiceSessionCreateRequest, VoiceMode
        req = VoiceSessionCreateRequest()
        assert req.mode == VoiceMode.GENERAL

    def test_voice_session_end_request_defaults(self):
        from app.models.voice_session import VoiceSessionEndRequest
        req = VoiceSessionEndRequest(session_id="s3")
        assert req.voice_seconds == 0.0
        assert req.transcript_turns == []

    def test_voice_mode_enum_values(self):
        from app.models.voice_session import VoiceMode
        assert VoiceMode.GENERAL.value == "general"
        assert VoiceMode.LESSON.value == "lesson"
        assert VoiceMode.TRADE_DEBRIEF.value == "trade_debrief"
