"""Pydantic models for the three-layer Jarvis memory system."""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel


# ── Layer 1: Profile memory (Firestore, stable facts) ─────────────────────────

class ProfileMemoryEntry(BaseModel):
    """One fact about the user stored at users/{uid}/voice_profile_memory/{key}.

    Examples:
      key="preferred_examples"  value="bitcoin"
      key="primary_market"      value="crypto"
      key="goal"                value="improve trading discipline"
    """
    key: str
    value: str
    source: str    # "onboarding" | "session_extraction" | "explicit"
    confidence: float = 1.0
    updated_at: datetime


# ── Layer 3: Coaching memory (Firestore, derived facts) ───────────────────────

class CoachingMemoryEntry(BaseModel):
    """Derived coaching observation stored at users/{uid}/coaching_memory/{id}.

    Built by BehaviorAnalysisWorker post-session.  Strength decays over time
    if not reinforced; increases when the pattern is observed again.
    """
    memory_id: str
    category: str   # "learning_gap" | "trading_habit" | "style_preference" |
                    # "risk_pattern" | "goal" | "motivation_pattern"
    summary: str    # e.g. "Frequently enters trades without a stop-loss"
    evidence_refs: list[str] = []   # session_ids that support this observation
    strength: float = 0.5           # 0.0–1.0; decays ~1/90 days if not seen
    last_seen_at: datetime


# ── Behavior events (Firestore, event log) ────────────────────────────────────

class BehaviorEvent(BaseModel):
    """One event entry stored at users/{uid}/behavior_events/{event_id}.

    See voicecoachbuild.md event taxonomy for all valid event_type values.
    """
    event_type: str
    session_id: Optional[str] = None
    screen: Optional[str] = None
    payload: dict = {}


# ── API models ────────────────────────────────────────────────────────────────

class BatchEventsRequest(BaseModel):
    events: list[BehaviorEvent]


class MemoryUpsertRequest(BaseModel):
    key: str
    value: str
    source: str = "explicit"
    confidence: float = 1.0


class MemoryContextResponse(BaseModel):
    profile_memory: list[ProfileMemoryEntry]
    coaching_memory: list[CoachingMemoryEntry]
