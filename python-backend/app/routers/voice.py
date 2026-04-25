"""Voice router — /api/voice/* endpoints for Jarvis voice session system.

All routes require Firebase token authentication via get_verified_uid().

Route summary:
  POST /api/voice/session/create     Bootstrap a new voice session
  POST /api/voice/session/end        Close session + trigger background workers
  GET  /api/voice/session/{id}/context  Reconnect: fetch live SessionState
  POST /api/voice/tools/invoke       Execute a tool during a live session
  POST /api/voice/events/batch       Log behavior events from Flutter
  GET  /api/voice/memory/context     Read profile + coaching memories
  POST /api/voice/memory/upsert      Upsert a profile memory entry
  GET  /api/voice/usage/status       Current usage vs tier limits
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

import firebase_admin
import firebase_admin.firestore
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException

from app.models.memory import (
    BatchEventsRequest,
    MemoryContextResponse,
    MemoryUpsertRequest,
    ProfileMemoryEntry,
    CoachingMemoryEntry,
)
from app.models.voice_session import (
    SessionState,
    ToolInvokeRequest,
    ToolInvokeResponse,
    ToolPayload,
    UsageStatusResponse,
    VoiceSessionBootstrap,
    VoiceSessionCreateRequest,
    VoiceSessionEndRequest,
)
from app.orchestrator.session_bootstrap import SessionBootstrapOrchestrator
from app.orchestrator.tool_registry import ToolRegistry, extract_primary_metric
from app.repositories.redis.session_repo import VoiceSessionRepo, get_session_repo
from app.repositories.redis.usage_counter_repo import UsageCounterRepo, get_usage_repo
from app.services.claude_service import ClaudeService
from app.services.data_fetcher import MarketDataFetcher
from app.services.event_service import EventService
from app.services.fred_service import FredService
from app.services.indicator_service import TechnicalIndicatorService
from app.services.realtime_session_service import RealtimeSessionService
from app.services.signal_engine import SignalEngine
from app.services.voice_auth_service import get_verified_uid
from app.workers import session_summary_worker, memory_extraction_worker, behavior_analysis_worker

router = APIRouter()
logger = logging.getLogger(__name__)


# ── Dependency helpers ────────────────────────────────────────────────────────

def _get_db():
    """Return Firestore client, or None if firebase_admin is not yet ready."""
    try:
        # Ensure Firebase admin is initialised (idempotent — returns fast if already done)
        if not firebase_admin._apps:
            from app.services.voice_auth_service import _try_init_firebase_admin
            _try_init_firebase_admin()
        return firebase_admin.firestore.client()
    except Exception as exc:
        logger.warning(f"[voice] _get_db() failed — Firebase not configured: {exc}")
        return None


def _get_tool_registry(db=Depends(_get_db)) -> ToolRegistry:
    return ToolRegistry(
        data_fetcher=MarketDataFetcher(),
        indicator_svc=TechnicalIndicatorService(),
        signal_engine=SignalEngine(),
        fred_svc=FredService(),
        firestore_db=db,
    )


def _get_bootstrap_orchestrator(
    db=Depends(_get_db),
    tool_registry: ToolRegistry = Depends(_get_tool_registry),
    session_repo: VoiceSessionRepo = Depends(get_session_repo),
    usage_repo: UsageCounterRepo = Depends(get_usage_repo),
) -> SessionBootstrapOrchestrator:
    return SessionBootstrapOrchestrator(
        db=db,
        session_repo=session_repo,
        usage_repo=usage_repo,
        realtime_svc=RealtimeSessionService(),
        tool_registry=tool_registry,
    )


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/session/create", response_model=VoiceSessionBootstrap)
async def create_session(
    request: VoiceSessionCreateRequest,
    uid: str = Depends(get_verified_uid),
    orchestrator: SessionBootstrapOrchestrator = Depends(_get_bootstrap_orchestrator),
    event_svc: EventService = Depends(lambda db=Depends(_get_db): EventService(db)),
):
    """Bootstrap a new Jarvis voice session.

    Returns ephemeral OpenAI Realtime token + assembled instructions.
    Flutter uses the token to open the WebSocket directly.
    """
    bootstrap = await orchestrator.build(uid, request)
    await event_svc.log(
        uid,
        "voice_session_started",
        session_id=bootstrap.session_id,
        payload={"mode": request.mode.value, "screen": request.screen_context},
    )
    return bootstrap


@router.post("/session/end")
async def end_session(
    request: VoiceSessionEndRequest,
    background_tasks: BackgroundTasks,
    uid: str = Depends(get_verified_uid),
    session_repo: VoiceSessionRepo = Depends(get_session_repo),
    usage_repo: UsageCounterRepo = Depends(get_usage_repo),
    db=Depends(_get_db),
    event_svc: EventService = Depends(lambda db=Depends(_get_db): EventService(db)),
):
    """End a voice session: update Firestore, meter usage, trigger background workers."""
    session_id = request.session_id

    # Update Firestore session doc
    try:
        from google.cloud.firestore import SERVER_TIMESTAMP
        db.collection("voice_sessions").document(session_id).set(
            {
                "ended_at": SERVER_TIMESTAMP,
                "voice_seconds": int(request.voice_seconds),
            },
            merge=True,
        )
    except Exception as exc:
        logger.warning(f"[voice] session/end Firestore update failed: {exc}")

    # Increment usage counter
    try:
        await usage_repo.increment_session(uid, request.voice_seconds)
    except Exception as exc:
        logger.warning(f"[voice] usage increment failed: {exc}")

    # Release session lock
    try:
        await session_repo.release_lock(uid)
    except Exception as exc:
        logger.warning(f"[voice] lock release failed: {exc}")

    # Log voice_session_ended event
    await event_svc.log(
        uid,
        "voice_session_ended",
        session_id=session_id,
        payload={
            "voice_seconds": request.voice_seconds,
            "turns": len(request.transcript_turns),
        },
    )

    # Background workers — run after response is returned
    claude_svc = ClaudeService()
    background_tasks.add_task(
        session_summary_worker.run,
        session_id=session_id,
        uid=uid,
        transcript_turns=request.transcript_turns,
        db=db,
        claude_svc=claude_svc,
    )
    background_tasks.add_task(
        memory_extraction_worker.run,
        session_id=session_id,
        uid=uid,
        transcript_turns=request.transcript_turns,
        db=db,
        claude_svc=claude_svc,
    )
    background_tasks.add_task(
        behavior_analysis_worker.run,
        session_id=session_id,
        uid=uid,
        db=db,
    )

    return {"success": True, "session_id": session_id}


@router.get("/session/{session_id}/context")
async def get_session_context(
    session_id: str,
    uid: str = Depends(get_verified_uid),
    session_repo: VoiceSessionRepo = Depends(get_session_repo),
):
    """Return current working SessionState for reconnect / context inspection."""
    state = await session_repo.get(session_id)
    if not state:
        raise HTTPException(status_code=404, detail="Session not found or expired.")
    if state.user_id != uid:
        raise HTTPException(status_code=403, detail="Session does not belong to this user.")

    # Return a safe subset (exclude ephemeral token — it's already used)
    return {
        "session_id": state.session_id,
        "mode": state.mode.value,
        "active_symbol": state.active_symbol,
        "active_lesson_id": state.active_lesson_id,
        "last_metric": state.last_metric,
        "last_timeframe": state.last_timeframe,
        "turn_count": state.turn_count,
        "voice_seconds": state.voice_seconds,
    }


@router.post("/tools/invoke", response_model=ToolInvokeResponse)
async def invoke_tool(
    request: ToolInvokeRequest,
    uid: str = Depends(get_verified_uid),
    session_repo: VoiceSessionRepo = Depends(get_session_repo),
    tool_registry: ToolRegistry = Depends(_get_tool_registry),
    event_svc: EventService = Depends(lambda db=Depends(_get_db): EventService(db)),
):
    """Execute a tool call on behalf of the OpenAI Realtime model.

    Flow: OpenAI WS → Flutter (tool_call event) → POST /tools/invoke (this route)
          → Flutter sends function_call_output back to OpenAI WS.
    """
    # Validate session belongs to uid
    state = await session_repo.get(request.session_id)
    if not state:
        raise HTTPException(status_code=404, detail="Session not found or expired.")
    if state.user_id != uid:
        raise HTTPException(status_code=403, detail="Session does not belong to this user.")

    # Execute tool
    result = await tool_registry.dispatch(request.tool_name, uid, request.arguments)

    # Build ToolPayload
    payload = ToolPayload(
        tool_name=request.tool_name,
        arguments=request.arguments,
        result=result,
        called_at=datetime.now(timezone.utc),
        symbol=request.arguments.get("symbol"),
        timeframe=request.arguments.get("timeframe"),
        metric=extract_primary_metric(request.tool_name, result),
    )

    # Update SessionState in Redis
    state.last_tool_payload = payload
    state.last_metric = payload.metric
    state.last_timeframe = payload.timeframe
    if payload.symbol:
        state.active_symbol = payload.symbol
    state.turn_count += 1
    await session_repo.set(request.session_id, state)

    # Log tool_called event (non-blocking)
    await event_svc.log(
        uid,
        "tool_called",
        session_id=request.session_id,
        payload={
            "tool": request.tool_name,
            "symbol": payload.symbol,
            "metric": payload.metric,
        },
    )

    return ToolInvokeResponse(result=result, tool_payload=payload)


@router.post("/events/batch")
async def log_events_batch(
    request: BatchEventsRequest,
    uid: str = Depends(get_verified_uid),
    event_svc: EventService = Depends(lambda db=Depends(_get_db): EventService(db)),
):
    """Batch-log behavior events from Flutter (e.g. chart_opened, indicator_enabled)."""
    accepted = await event_svc.log_batch(uid, request.events)
    return {"accepted": accepted}


@router.get("/memory/context", response_model=MemoryContextResponse)
async def get_memory_context(
    uid: str = Depends(get_verified_uid),
    db=Depends(_get_db),
):
    """Return profile and coaching memories for display (e.g. Profile screen)."""
    profile_memory: list[ProfileMemoryEntry] = []
    coaching_memory: list[CoachingMemoryEntry] = []

    try:
        from datetime import datetime, timezone
        for doc in (
            db.collection("users").document(uid).collection("voice_profile_memory").stream()
        ):
            d = doc.to_dict()
            updated_raw = d.get("updated_at")
            updated_dt = (
                updated_raw.ToDatetime().replace(tzinfo=timezone.utc)
                if hasattr(updated_raw, "ToDatetime")
                else datetime.now(timezone.utc)
            )
            profile_memory.append(
                ProfileMemoryEntry(
                    key=d.get("key", doc.id),
                    value=d.get("value", ""),
                    source=d.get("source", "session_extraction"),
                    confidence=d.get("confidence", 1.0),
                    updated_at=updated_dt,
                )
            )
    except Exception as exc:
        logger.warning(f"[voice] get_memory_context profile read failed: {exc}")

    try:
        from datetime import datetime, timezone
        for doc in (
            db.collection("users")
            .document(uid)
            .collection("coaching_memory")
            .order_by("strength", direction="DESCENDING")
            .limit(10)
            .stream()
        ):
            d = doc.to_dict()
            seen_raw = d.get("last_seen_at")
            seen_dt = (
                seen_raw.ToDatetime().replace(tzinfo=timezone.utc)
                if hasattr(seen_raw, "ToDatetime")
                else datetime.now(timezone.utc)
            )
            coaching_memory.append(
                CoachingMemoryEntry(
                    memory_id=doc.id,
                    category=d.get("category", "style_preference"),
                    summary=d.get("summary", ""),
                    evidence_refs=d.get("evidence_refs", []),
                    strength=d.get("strength", 0.5),
                    last_seen_at=seen_dt,
                )
            )
    except Exception as exc:
        logger.warning(f"[voice] get_memory_context coaching read failed: {exc}")

    return MemoryContextResponse(
        profile_memory=profile_memory,
        coaching_memory=coaching_memory,
    )


@router.post("/memory/upsert")
async def upsert_memory(
    request: MemoryUpsertRequest,
    uid: str = Depends(get_verified_uid),
    db=Depends(_get_db),
):
    """Upsert a single profile memory entry (used during onboarding)."""
    try:
        from google.cloud.firestore import SERVER_TIMESTAMP
        db.collection("users").document(uid).collection("voice_profile_memory").document(
            request.key
        ).set(
            {
                "key": request.key,
                "value": request.value,
                "source": request.source,
                "confidence": request.confidence,
                "updated_at": SERVER_TIMESTAMP,
            },
            merge=True,
        )
        return {"updated": True}
    except Exception as exc:
        logger.error(f"[voice] memory upsert failed for {uid}: {exc}")
        raise HTTPException(status_code=500, detail="Memory upsert failed.")


@router.get("/usage/status", response_model=UsageStatusResponse)
async def get_usage_status(
    uid: str = Depends(get_verified_uid),
    usage_repo: UsageCounterRepo = Depends(get_usage_repo),
    db=Depends(_get_db),
):
    """Return current usage vs tier limits for the authenticated user."""
    from datetime import datetime, timezone
    period = datetime.now(timezone.utc).strftime("%Y-%m")
    data = await usage_repo.get(uid, period)

    # Read tier from Firestore
    tier = "prototype_owner"
    try:
        doc = db.collection("users").document(uid).get()
        if doc.exists:
            tier = doc.to_dict().get("subscription_tier", "prototype_owner")
    except Exception:
        pass

    from app.repositories.redis.usage_counter_repo import TIER_LIMITS
    limits = TIER_LIMITS.get(tier, TIER_LIMITS["free"])

    return UsageStatusResponse(
        billing_period=period,
        voice_minutes_used=round(data["voice_seconds"] / 60, 2),
        voice_sessions_used=data["sessions"],
        voice_minutes_limit=limits["voice_seconds"] / 60 if limits["voice_seconds"] else None,
        voice_sessions_limit=limits["sessions"],
        tier=tier,
    )


# ── Phase 11: ChromaDB Memory Endpoints ──────────────────────────────────────

@router.get("/memory/summary")
async def get_memory_summary(uid: str = Depends(get_verified_uid)):
    """Return a plain-English summary of what ChromaDB knows about the user."""
    try:
        from app.services.chroma_memory_service import ChromaMemoryService
        svc = ChromaMemoryService()
        return {"uid": uid, "summary": svc.summarise_user(uid)}
    except Exception as e:
        logger.error(f"[memory] summary error for {uid}: {e}")
        return {"uid": uid, "summary": "Memory unavailable."}


@router.post("/memory/store")
async def store_memory(
    payload: dict,
    uid: str = Depends(get_verified_uid),
):
    """
    Manually store a memory snippet for the user.
    Body: { "text": "...", "category": "preference|portfolio|learning|conversation|event" }
    """
    text     = payload.get("text", "").strip()
    category = payload.get("category", "event")
    symbol   = payload.get("symbol")

    if not text:
        from fastapi import HTTPException as _HTTPException
        raise _HTTPException(status_code=400, detail="text is required")

    try:
        from app.services.chroma_memory_service import ChromaMemoryService
        svc     = ChromaMemoryService()
        success = svc.store(uid, text, category=category, symbol=symbol)
        return {"stored": success}
    except Exception as e:
        logger.error(f"[memory] store error for {uid}: {e}")
        return {"stored": False, "error": str(e)}


@router.delete("/memory")
async def delete_memory(uid: str = Depends(get_verified_uid)):
    """GDPR: delete all ChromaDB memories for the authenticated user."""
    try:
        from app.services.chroma_memory_service import ChromaMemoryService
        svc     = ChromaMemoryService()
        success = svc.delete_user(uid)
        return {"deleted": success}
    except Exception as e:
        logger.error(f"[memory] delete error for {uid}: {e}")
        return {"deleted": False, "error": str(e)}
