"""Correlation Engine Models — News × Price + Fundamental scoring (§4.2, §4.3)"""

from pydantic import BaseModel
from typing import List, Optional


class CorrelationResult(BaseModel):
    # ── News sentiment ────────────────────────────────────────────────────────
    news_sentiment_score: float          # weighted avg  -1.0 → +1.0
    sentiment_label: str                 # positive | negative | neutral
    top_headlines: List[str]             # top 3 headlines (truncated)
    high_impact_flags: List[str]         # e.g. ["Earnings Report", "FDA Decision"]

    # ── News × Price scenario (§4.3) ─────────────────────────────────────────
    price_direction: str                 # RISING | FALLING | FLAT
    scenario: str                        # scenario key (see CorrelationEngine)
    scenario_label: str                  # human-readable label
    scenario_description: str           # one-sentence explanation

    # ── Fundamentals (stocks only) ────────────────────────────────────────────
    fundamental_score: Optional[int] = None    # 0-100
    fundamental_grade: Optional[str] = None    # A / B / C / D / F
    fundamental_signals: List[str] = []        # ["P/E below sector avg (bullish)", ...]

    # ── Macro overlay (Phase A) ───────────────────────────────────────────────
    macro_flags: List[str] = []                # e.g. ["Inverted yield curve: recession risk"]
