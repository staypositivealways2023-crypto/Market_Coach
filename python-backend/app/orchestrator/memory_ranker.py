"""Memory ranker — scores and selects coaching memories for prompt injection.

Two ranking functions:

  rank()               — ranks Firestore CoachingMemoryEntry objects.
                         Score = strength × recency_factor × mode_boost.

  rank_chroma_results() — ranks ChromaDB query results (Phase 4).
                          Score = (1 - distance) × recency_factor × category_boost.
                          Combines semantic relevance with time decay and
                          query-context category boosts.
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional

from app.models.memory import CoachingMemoryEntry
from app.models.voice_session import VoiceMode

# ── Shared constants ──────────────────────────────────────────────────────────

_TOP_N = 5
_RECENCY_DECAY_DAYS = 90.0   # memory fully decayed after 90 days without reinforcement
_MIN_RECENCY = 0.3            # floor — never decay below 30 % of original strength

# ── Firestore ranker (original) ───────────────────────────────────────────────

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


# ── ChromaDB ranker (Phase 4) ─────────────────────────────────────────────────

@dataclass
class ChromaMemoryResult:
    """One ranked ChromaDB result returned by rank_chroma_results()."""
    id: str
    text: str
    category: str
    timestamp: int          # Unix epoch seconds
    symbol: Optional[str]
    relevance_score: float  # Combined score: semantic × recency × category_boost


# Category boosts applied per query context keyword
# Keys are query context names; values map category → additive boost
_CHROMA_CONTEXT_BOOSTS: dict[str, dict[str, float]] = {
    "trade":     {"trade_history": 0.25, "watchlist_patterns": 0.15},
    "risk":      {"risk_profile": 0.30,  "trade_history": 0.10},
    "watchlist": {"watchlist_patterns": 0.30, "trade_history": 0.10},
    "learning":  {"learning": 0.25, "preference": 0.10},
    "preference":{"preference": 0.30},
    "portfolio": {"portfolio": 0.20, "watchlist_patterns": 0.15},
    "general":   {},   # no boost — pure semantic similarity
}


def rank_chroma_results(
    results: list[dict],
    context: str = "general",
    top_n: int = _TOP_N,
) -> list[ChromaMemoryResult]:
    """
    Rank ChromaDB query results (as returned by recall_with_metadata) by:
      final_score = (1 - distance) × recency_factor × (1 + category_boost)

    Args:
        results:  list of dicts with keys: id, text, category, timestamp,
                  symbol, distance  (from ChromaMemoryService.recall_with_metadata)
        context:  query context hint — one of: trade | risk | watchlist |
                  learning | preference | portfolio | general
        top_n:    number of top results to return

    Returns:
        Top-N ChromaMemoryResult objects sorted by relevance_score descending.
    """
    now_epoch = int(time.time())
    boosts = _CHROMA_CONTEXT_BOOSTS.get(context, {})

    ranked: list[ChromaMemoryResult] = []
    for r in results:
        distance  = float(r.get("distance", 0.5))
        timestamp = int(r.get("timestamp", 0))
        category  = r.get("category", "event")

        # Semantic similarity: cosine distance ∈ [0, 2]; typical range [0, 1]
        semantic = max(0.0, 1.0 - distance)

        # Recency decay: linear over _RECENCY_DECAY_DAYS
        if timestamp > 0:
            days_old = max(0.0, (now_epoch - timestamp) / 86400)
            recency = max(_MIN_RECENCY, 1.0 - days_old / _RECENCY_DECAY_DAYS)
        else:
            recency = _MIN_RECENCY  # unknown age → apply floor

        # Category boost: additive multiplier
        category_boost = boosts.get(category, 0.0)

        score = semantic * recency * (1.0 + category_boost)

        ranked.append(ChromaMemoryResult(
            id=r.get("id", ""),
            text=r.get("text", ""),
            category=category,
            timestamp=timestamp,
            symbol=r.get("symbol"),
            relevance_score=round(score, 4),
        ))

    return sorted(ranked, key=lambda x: x.relevance_score, reverse=True)[:top_n]
