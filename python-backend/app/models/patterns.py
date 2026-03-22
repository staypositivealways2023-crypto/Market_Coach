"""Chart Pattern Models — Phase 6 Pattern Detection"""

from pydantic import BaseModel
from typing import List, Optional


class ChartPattern(BaseModel):
    type: str            # DOUBLE_TOP | DOUBLE_BOTTOM | HEAD_SHOULDERS | INV_HEAD_SHOULDERS
                         # | ASCENDING_TRIANGLE | DESCENDING_TRIANGLE | SYMMETRICAL_TRIANGLE
                         # | BULL_FLAG | BEAR_FLAG | WEDGE_RISING | WEDGE_FALLING
    signal: str          # BULLISH | BEARISH | NEUTRAL
    confidence: float    # 0.0 – 1.0
    description: str     # one-sentence plain-English explanation
    key_price: Optional[float] = None   # breakout level or neckline
    formed_at_index: int = -1           # candle index where pattern completed


class SupportResistanceLevel(BaseModel):
    price: float
    type: str        # SUPPORT | RESISTANCE
    strength: int    # number of touches (2-5+)
    description: str


class PatternScanResult(BaseModel):
    patterns: List[ChartPattern] = []
    support_resistance: List[SupportResistanceLevel] = []
    trend: str = "SIDEWAYS"          # UPTREND | DOWNTREND | SIDEWAYS
    trend_strength: str = "WEAK"     # STRONG | MODERATE | WEAK
