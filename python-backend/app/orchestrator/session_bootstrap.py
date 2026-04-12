"""Session bootstrap orchestrator.

Coordinates all steps required to create a new voice session:
  1. Check usage limits (Redis)
  2. Assemble user context (Firestore)
  3. Rank coaching memories for prompt injection
  4. Build typed prompt blocks → instructions string
  5. Get OpenAI tool schemas for the requested mode
  6. Create OpenAI Realtime ephemeral token
  7. Persist SessionState to Redis
  8. Write voice_sessions/{session_id} doc to Firestore
  9. Return VoiceSessionBootstrap to the router

Returns VoiceSessionBootstrap ready to be sent to Flutter.
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, timezone

from app.models.voice_session import (
    SessionState,
    VoiceSessionBootstrap,
    VoiceSessionCreateRequest,
)
from app.orchestrator.context_assembler import ContextAssembler
from app.orchestrator.memory_ranker import rank as rank_memories
from app.orchestrator.prompt_builder import VoicePromptBuilder
from app.orchestrator.tool_registry import ToolRegistry
from app.repositories.redis.session_repo import VoiceSessionRepo
from app.repositories.redis.usage_counter_repo import UsageCounterRepo
from app.services.realtime_session_service import RealtimeSessionService

logger = logging.getLogger(__name__)


class SessionBootstrapOrchestrator:
    def __init__(
        self,
        db,
        session_repo: VoiceSessionRepo,
        usage_repo: UsageCounterRepo,
        realtime_svc: RealtimeSessionService,
        tool_registry: ToolRegistry,
    ) -> None:
        self._db = db
        self._session_repo = session_repo
        self._usage_repo = usage_repo
        self._realtime_svc = realtime_svc
        self._tool_registry = tool_registry
        self._context_assembler = ContextAssembler(db)
        self._prompt_builder = VoicePromptBuilder()

    async def build(
        self, uid: str, request: VoiceSessionCreateRequest
    ) -> VoiceSessionBootstrap:
        # ── 1. Usage check ────────────────────────────────────────────────────
        # Phase 1: prototype_owner tier = unlimited.  Wire tiers in Phase 4.
        tier = await self._get_user_tier(uid)
        allowed, reason = await self._usage_repo.check_can_start(uid, tier)
        if not allowed:
            from fastapi import HTTPException
            raise HTTPException(status_code=429, detail=reason)

        # ── 2. Acquire session lock (prevents double-open) ────────────────────
        session_id = str(uuid.uuid4())
        locked = await self._session_repo.acquire_lock(uid, session_id)
        if not locked:
            existing = await self._session_repo.get_lock(uid)
            logger.warning(f"[bootstrap] User {uid} already has active session {existing}")
            from fastapi import HTTPException
            raise HTTPException(
                status_code=409,
                detail="A voice session is already active. End the current session first.",
            )

        # ── 3. Assemble context ───────────────────────────────────────────────
        ctx = await self._context_assembler.assemble(uid, request)
        user_level: str = ctx["user_level"]
        profile_memory = ctx["profile_memory"]
        coaching_memory_raw = ctx["coaching_memory"]

        # ── 4. Rank coaching memories ─────────────────────────────────────────
        ranked_coaching = rank_memories(coaching_memory_raw, request.mode)

        # ── 5. Build instructions ─────────────────────────────────────────────
        instructions = self._prompt_builder.build(
            profile_memory=profile_memory,
            coaching_memory=ranked_coaching,
            user_level=user_level,
            mode=request.mode,
            screen_context=request.screen_context,
            active_symbol=request.active_symbol,
            active_lesson_id=request.active_lesson_id,
        )

        # ── 6. Get tool schemas ───────────────────────────────────────────────
        tools = self._tool_registry.get_openai_tool_schemas(request.mode)

        # ── 7. Create OpenAI ephemeral token ──────────────────────────────────
        ephemeral_token, expires_at = await self._realtime_svc.create_ephemeral_token(
            instructions=instructions,
            tools=tools,
        )

        # ── 8. Persist SessionState to Redis ──────────────────────────────────
        now = datetime.now(timezone.utc)
        state = SessionState(
            session_id=session_id,
            user_id=uid,
            mode=request.mode,
            started_at=now,
            active_symbol=request.active_symbol,
            active_lesson_id=request.active_lesson_id,
        )
        await self._session_repo.set(session_id, state)

        # ── 9. Write Firestore session doc ────────────────────────────────────
        try:
            from google.cloud.firestore import SERVER_TIMESTAMP
            self._db.collection("voice_sessions").document(session_id).set({
                "session_id": session_id,
                "user_id": uid,
                "mode": request.mode.value,
                "screen_context": request.screen_context,
                "active_symbol": request.active_symbol,
                "active_lesson_id": request.active_lesson_id,
                "started_at": SERVER_TIMESTAMP,
                "voice_seconds": 0,
                "turn_count": 0,
            })
        except Exception as exc:
            logger.warning(f"[bootstrap] Firestore write failed: {exc}")

        logger.info(
            f"[bootstrap] Session {session_id} created for uid={uid} "
            f"mode={request.mode.value} level={user_level}"
        )

        return VoiceSessionBootstrap(
            session_id=session_id,
            openai_ephemeral_token=ephemeral_token,
            openai_model=self._realtime_svc.model,
            openai_voice=self._realtime_svc.default_voice,
            instructions=instructions,
            tools=tools,
            mode=request.mode,
            user_level=user_level,
            expires_at=expires_at,
        )

    async def _get_user_tier(self, uid: str) -> str:
        """Read subscription tier from Firestore users/{uid}.subscription_tier."""
        try:
            doc = self._db.collection("users").document(uid).get()
            if doc.exists:
                return doc.to_dict().get("subscription_tier", "prototype_owner")
        except Exception:
            pass
        return "prototype_owner"   # Default to unlimited during prototype phase
