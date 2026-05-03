"""
/api/analyst — Analyst Cycle endpoints.

POST /api/analyst/query   — run the full 5-node LangGraph cycle
GET  /api/analyst/audio/{file_id} — serve Cartesia-generated MP3
"""

import uuid
import os
import logging
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

from app.graph.graph import analyst_graph
from app.graph.state import AnalystState

logger = logging.getLogger(__name__)
router = APIRouter()

AUDIO_DIR = Path("/app/audio_cache")


# ── Request / Response models ─────────────────────────────────────────────────

class AnalystQueryRequest(BaseModel):
    message: str
    user_id: str = "anonymous"
    thread_id: str | None = None   # Supply to resume a prior conversation


class AnalystQueryResponse(BaseModel):
    thread_id: str
    intent: str | None = None
    symbol: str | None = None
    intent_confidence: float | None = None
    cot_thinking: str | None = None
    reasoning_answer: str | None = None
    verification_passed: bool | None = None
    verification_score: float | None = None
    flagged_claims: list[str] | None = None
    coach_response: str | None = None
    scenario_cards: dict | None = None
    audio_url: str | None = None
    error: str | None = None


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/query", response_model=AnalystQueryResponse)
async def run_analyst_query(request: AnalystQueryRequest):
    """
    Run the full Analyst Cycle (intent → tools → reasoning → verify → synthesis).
    Supply thread_id to continue an existing session with memory.
    """
    thread_id = request.thread_id or str(uuid.uuid4())

    # Build initial state — only required fields; LangGraph fills the rest
    initial_state: AnalystState = {
        "user_message":        request.message,
        "user_id":             request.user_id,
        "thread_id":           thread_id,
        "intent":              None,
        "symbol":              None,
        "intent_confidence":   None,
        "tool_results":        None,
        "cot_thinking":        None,
        "reasoning_answer":    None,
        "verification_passed": None,
        "verification_score":  None,
        "flagged_claims":      None,
        "retry_count":         0,
        "coach_response":      None,
        "scenario_cards":      None,
        "audio_url":           None,
        "error":               None,
    }

    config = {"configurable": {"thread_id": thread_id}}

    try:
        logger.info(
            "[analyst] Starting query for user=%s thread=%s msg=%r",
            request.user_id, thread_id, request.message[:80],
        )
        final_state = await analyst_graph.ainvoke(initial_state, config=config)

    except Exception as e:
        logger.exception("[analyst] Graph execution failed: %s", e)
        raise HTTPException(status_code=500, detail=f"Analyst graph error: {e}")

    return AnalystQueryResponse(
        thread_id=           thread_id,
        intent=              final_state.get("intent"),
        symbol=              final_state.get("symbol"),
        intent_confidence=   final_state.get("intent_confidence"),
        cot_thinking=        final_state.get("cot_thinking"),
        reasoning_answer=    final_state.get("reasoning_answer"),
        verification_passed= final_state.get("verification_passed"),
        verification_score=  final_state.get("verification_score"),
        flagged_claims=      final_state.get("flagged_claims"),
        coach_response=      final_state.get("coach_response"),
        scenario_cards=      final_state.get("scenario_cards"),
        audio_url=           final_state.get("audio_url"),
        error=               final_state.get("error"),
    )


@router.get("/audio/{file_id}")
async def serve_audio(file_id: str):
    """Serve a Cartesia-generated WAV by file ID."""
    # Sanitise file_id — only allow UUID-shaped strings
    try:
        uuid.UUID(file_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid file_id")

    filepath = AUDIO_DIR / f"{file_id}.wav"
    if not filepath.exists():
        raise HTTPException(status_code=404, detail="Audio file not found")

    return FileResponse(filepath, media_type="audio/wav")
