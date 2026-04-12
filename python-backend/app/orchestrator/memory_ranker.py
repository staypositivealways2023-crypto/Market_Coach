"""Memory ranker — scores and selects coaching memories for prompt injection.

Rule-based scoring (no ML). Score = strength × recency_factor × mode_boost.
Returns top N memories sorted by score descending.
"""

from __future__ import annotations

from datetime import datetime, timezone

from app.models.memory import CoachingMemoryEntry
from app.models.voice_session import VoiceMode

_TOP_N = 5
_RECENCY_DECAY_DAYS = 90.0   # memory fully decayed after 90 days without reinforcement
_MIN_RECENCY = 0.3            # floor — never decay below 30 % of original strength

_MODE_BOOSTS: dict[VoiceMode, dict[str, float]] = {
    VoiceMode.TRADE_DEBRIEF: {"trading_habit": 0.3, "risk_pattern": 0.3},
    VoiceMode.LESSON: {"learning_gap": 0.3, "style_preference": 0.2},
    VoiceMode.GENERAL: {},
}


def rank(
    memories: list[CoachingMemoryEntry],
    mode: VoiceMode,
    top_n: int = _TOP_N,
) -> list[CoachingMemoryEntry]:
    """Return the top_n most relevant coaching memories for the given mode."""
    now = datetime.now(timezone.utc)
    boosts = _MODE_BOOSTS.get(mode, {})

    def score(m: CoachingMemoryEntry) -> float:
        base = m.strength
        # Recency decay
        days_old = max(0.0, (now - m.last_seen_at).total_seconds() / 86400)
        recency = max(_MIN_RECENCY, 1.0 - days_old / _RECENCY_DECAY_DAYS)
        # Mode relevance boost
        boost = boosts.get(m.category, 0.0)
        return (base * recency) + boost

    return sorted(memories, key=score, reverse=True)[:top_n]
