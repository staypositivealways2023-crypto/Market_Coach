"""Signal Engine Models - Structured signal data for computed analysis"""

from pydantic import BaseModel
from enum import Enum
from typing import Optional

from app.models.prediction import PredictionResult
from app.models.correlation import CorrelationResult
from app.models.patterns import PatternScanResult


class SignalLabel(str, Enum):
    STRONG_BUY = "STRONG_BUY"
    BUY = "BUY"
    NEUTRAL = "NEUTRAL"
    SELL = "SELL"
    STRONG_SELL = "STRONG_SELL"


class CandlestickSignal(BaseModel):
    pattern: Optional[str] = None
    signal: str = "NEUTRAL"       # BULLISH | BEARISH | NEUTRAL
    confidence: float = 0.0        # 0.0 – 1.0


class IndicatorSignals(BaseModel):
    rsi_value: Optional[float] = None
    rsi_signal: str = "NEUTRAL"    # OVERSOLD | NEUTRAL | OVERBOUGHT
    macd_signal: str = "NEUTRAL"   # BULLISH_CROSS | BEARISH_CROSS | BULLISH | BEARISH | NEUTRAL
    macd_histogram: Optional[float] = None
    ema_stack: str = "MIXED"       # PRICE_ABOVE_ALL | PRICE_ABOVE_20_50 | PRICE_ABOVE_20 | MIXED | PRICE_BELOW_20 | PRICE_BELOW_20_50 | PRICE_BELOW_ALL
    volume: str = "AVERAGE"        # ABOVE_AVERAGE | AVERAGE | BELOW_AVERAGE
    bb_position: str = "MIDDLE"    # ABOVE_UPPER | UPPER | MIDDLE | LOWER | BELOW_LOWER


class ComputedSignals(BaseModel):
    candlestick: CandlestickSignal
    indicators: IndicatorSignals
    composite_score: float          # -1.0 to +1.0
    signal_label: SignalLabel


class ScenarioCase(BaseModel):
    probability: int    # percentage 0-100
    price_target: float # ATR-derived price target
    thesis: str         # one-sentence narrative


class Scenarios(BaseModel):
    bull: ScenarioCase
    base: ScenarioCase
    bear: ScenarioCase


class AnalyseResponse(BaseModel):
    symbol: str
    interval: str
    signals: ComputedSignals
    prediction: Optional[PredictionResult] = None   # Phase 4 price target
    correlation: Optional[CorrelationResult] = None # Phase 5 news × fundamentals
    patterns: Optional[PatternScanResult] = None    # Phase 6 chart patterns
    scenarios: Optional[Scenarios] = None           # Bull / Base / Bear cases
    analysis: str                                    # Claude's narrative
    coaching_nudge: Optional[str] = None            # Phase 2 Dean Agent nudge
    coaching_lesson_id: Optional[str] = None        # Phase 3 — GuidedLesson.id to open
    timestamp: str
    is_cached: bool = False
    tokens_used: int = 0
