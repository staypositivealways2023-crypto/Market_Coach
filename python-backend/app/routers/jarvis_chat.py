"""Jarvis Chat Router — /api/jarvis/*

Exposes the local Jarvis (Ollama-backed) assistant over HTTP so the Flutter
app can use it for:
  • General conversation  POST /api/jarvis/chat
  • Live quote            GET  /api/jarvis/quote/{ticker}
  • Technical indicators  GET  /api/jarvis/indicators/{ticker}
  • Grounded analysis     POST /api/jarvis/analyse/{ticker}
  • Health / availability GET  /api/jarvis/status

All routes require Firebase authentication (Bearer token).
If Jarvis is offline the routes return a 503 with a clear message rather than
crashing, so the Flutter app can degrade gracefully.
"""

from __future__ import annotations

import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.services.jarvis_adapter_service import (
    jarvis_analyse,
    jarvis_ask,
    jarvis_health,
    jarvis_indicators,
    jarvis_quote,
    jarvis_snapshot,
)
from app.services.voice_auth_service import get_verified_uid

router = APIRouter()
logger = logging.getLogger(__name__)


# ── Request / Response models ─────────────────────────────────────────────────

class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=4000)
    history: list[dict] = Field(
        default_factory=list,
        description="Optional conversation history: [{role, content}, ...]",
    )


class ChatResponse(BaseModel):
    reply: str
    source: str = "jarvis-local"


class AnalyseRequest(BaseModel):
    question: Optional[str] = Field(
        None,
        description="Optional focus question, e.g. 'Should I buy here?'",
    )


# ── Routes ────────────────────────────────────────────────────────────────────

@router.get("/status")
async def jarvis_status(uid: str = Depends(get_verified_uid)):
    """Check if the local Jarvis service is reachable.

    Returns {"online": bool, "detail": ...}.
    Does NOT raise an error if Jarvis is offline — Flutter uses this to show
    an offline badge in the chat UI.
    """
    result = await jarvis_health()
    return result


@router.post("/chat", response_model=ChatResponse)
async def chat_with_jarvis(
    body: ChatRequest,
    uid: str = Depends(get_verified_uid),
):
    """Send a free-form message to Jarvis and get a reply.

    Jarvis routes internally:
      • System command  → instant (no LLM)
      • Finance query   → yfinance data ± Ollama grounded response
      • General chat    → Ollama (gemma3:4b by default)

    The optional `history` list injects previous turns so multi-turn
    conversations feel natural.
    """
    logger.info(f"[jarvis_chat] uid={uid} msg='{body.message[:60]}'")

    reply = await jarvis_ask(body.message, history=body.history or None)

    # If Jarvis is offline jarvis_ask returns an error string starting with
    # "[Jarvis unavailable]". We turn that into a 503 so Flutter can show
    # a proper offline state rather than displaying the error as a chat bubble.
    if reply.startswith("[Jarvis unavailable]"):
        raise HTTPException(
            status_code=503,
            detail=reply,
        )

    return ChatResponse(reply=reply)


@router.get("/quote/{ticker}")
async def get_quote(
    ticker: str,
    uid: str = Depends(get_verified_uid),
):
    """Get a live price quote from Jarvis (backed by yfinance).

    Returns price, day_change_pct, and volume.
    Falls back cleanly with {"error": ...} if Jarvis is offline.
    """
    result = await jarvis_quote(ticker.upper())
    if "error" in result:
        raise HTTPException(status_code=503, detail=result["error"])
    return result


@router.get("/indicators/{ticker}")
async def get_indicators(
    ticker: str,
    uid: str = Depends(get_verified_uid),
):
    """Get RSI, MACD, and 52-week range from Jarvis.

    Returns rsi, macd_line, macd_signal, macd_histogram, 52wk_high, 52wk_low.
    """
    result = await jarvis_indicators(ticker.upper())
    if "error" in result:
        raise HTTPException(status_code=503, detail=result["error"])
    return result


@router.get("/snapshot/{ticker}")
async def get_snapshot(
    ticker: str,
    uid: str = Depends(get_verified_uid),
):
    """Combined quote + indicators in one call.

    Convenience endpoint used by the Flutter finance quick-view card.
    """
    result = await jarvis_snapshot(ticker.upper())
    if "error" in result:
        raise HTTPException(status_code=503, detail=result["error"])
    return result


@router.post("/analyse/{ticker}")
async def analyse_ticker(
    ticker: str,
    body: AnalyseRequest,
    uid: str = Depends(get_verified_uid),
):
    """Request a grounded Ollama analysis for a ticker.

    Jarvis fetches live data, locks it into a [LOCKED DATA] block, and passes
    it to Ollama so the LLM cannot hallucinate price or indicator numbers.

    Optional `question` focuses the analysis (e.g. "Is the RSI oversold?").
    """
    result = await jarvis_analyse(ticker.upper(), question=body.question)
    if "error" in result:
        raise HTTPException(status_code=503, detail=result["error"])
    return result
