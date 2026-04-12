"""Pydantic models for the Jarvis voice session system."""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any, Optional

from pydantic import BaseModel, Field


class VoiceMode(str, Enum):
    GENERAL = "general"
    LESSON = "lesson"
    TRADE_DEBRIEF = "trade_debrief"


# ── Auditable tool call record ────────────────────────────────────────────────

class ToolPayload(BaseModel):
    """Typed, auditable record of the most-recent tool call in a session.

    Stored in Redis SessionState so every turn can reference what was last
    fetched — prevents the model from hallucinating stale or invented data.
    """
    tool_name: str
    arguments: dict[str, Any] = {}
    result: dict[str, Any] = {}
    called_at: datetime
    symbol: Optional[str] = None
    timeframe: Optional[str] = None   # "1d" | "1h" | "5m" etc.
    metric: Optional[str] = None      # primary metric returned: "rsi", "composite_score", …


# ── Redis working state ───────────────────────────────────────────────────────

class SessionState(BaseModel):
    """Live session state stored in Redis (key: voice_session:{session_id}).

    TTL = REDIS_TTL_SESSION (3 h).  Extended on every tool call.
    """
    session_id: str
    user_id: str
    mode: VoiceMode
    started_at: datetime
    turn_count: int = 0
    voice_seconds: float = 0.0
    # Structured last-tool tracking — updated after every /tools/invoke call
    last_metric: Optional[str] = None
    last_timeframe: Optional[str] = None
    last_tool_payload: Optional[ToolPayload] = None
    # Active context (updated by tool calls)
    active_symbol: Optional[str] = None
    active_lesson_id: Optional[str] = None


# ── Session bootstrap (returned to Flutter) ───────────────────────────────────

class VoiceSessionBootstrap(BaseModel):
    """Returned to Flutter from POST /api/voice/session/create.

    Flutter uses the ephemeral token to open the OpenAI Realtime WebSocket
    directly — the backend never handles raw audio.
    """
    session_id: str
    openai_ephemeral_token: str
    openai_model: str
    openai_voice: str          # "alloy" | "echo" | "shimmer" | "verse" | "coral"
    instructions: str          # assembled prompt sent to OpenAI session
    tools: list[dict]          # OpenAI tool schemas to enable
    mode: VoiceMode
    user_level: str            # "beginner" | "intermediate" | "advanced"
    expires_at: datetime       # ephemeral token expiry (60 s from issuance)


# ── Request / response models ─────────────────────────────────────────────────

class VoiceSessionCreateRequest(BaseModel):
    mode: VoiceMode = VoiceMode.GENERAL
    screen_context: str = ""
    active_symbol: Optional[str] = None
    active_lesson_id: Optional[str] = None


class TranscriptTurn(BaseModel):
    role: str          # "user" | "assistant"
    text: str
    tool_calls: list[dict] = []


class VoiceSessionEndRequest(BaseModel):
    session_id: str
    transcript_turns: list[TranscriptTurn] = []
    voice_seconds: float = 0.0


class ToolInvokeRequest(BaseModel):
    session_id: str
    tool_name: str
    arguments: dict[str, Any] = {}


class ToolInvokeResponse(BaseModel):
    result: dict[str, Any]
    tool_payload: ToolPayload


class UsageStatusResponse(BaseModel):
    billing_period: str
    voice_minutes_used: float
    voice_sessions_used: int
    voice_minutes_limit: Optional[float]
    voice_sessions_limit: Optional[int]
    tier: str
