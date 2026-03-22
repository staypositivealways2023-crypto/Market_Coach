"""Signal Engine - Aggregates all technical signals into a single composite score.

Architecture (§3.4):
  candlestick  20% weight
  RSI          20% weight
  MACD         20% weight
  EMA stack    25% weight
  BB position  10% weight
  Volume        5% weight
  ─────────────────────────
  composite_score: -1.0 (strong bearish) → +1.0 (strong bullish)
"""

import pandas as pd
import numpy as np
from typing import List, Optional
import logging

from app.models.stock import Candle
from app.models.indicator import TechnicalIndicators
from app.models.signals import (
    CandlestickSignal,
    ComputedSignals,
    IndicatorSignals,
    SignalLabel,
)
from app.services.candlestick_patterns import detect_candlestick_pattern

logger = logging.getLogger(__name__)


class SignalEngine:
    """Computes a composite signal score from all available technical signals."""

    # ── Weight table ──────────────────────────────────────────────────────────
    W_CANDLE = 0.20
    W_RSI    = 0.20
    W_MACD   = 0.20
    W_EMA    = 0.25
    W_BB     = 0.10
    W_VOL    = 0.05

    def run(
        self,
        candles: List[Candle],
        indicators: Optional[TechnicalIndicators],
        avg_volume: Optional[float] = None,
    ) -> ComputedSignals:
        """
        Run the full signal engine and return ComputedSignals.

        Args:
            candles:    List of Candle objects (ascending order).
            indicators: Pre-calculated TechnicalIndicators (may be None).
            avg_volume: Optional 20-period average volume for volume signal.
        """

        df = self._candles_to_df(candles)

        # ── 1. Candlestick pattern ────────────────────────────────────────────
        pattern_name, pattern_signal, pattern_conf = detect_candlestick_pattern(df)
        candlestick = CandlestickSignal(
            pattern=pattern_name,
            signal=pattern_signal,
            confidence=round(pattern_conf, 2),
        )

        # ── 2. Indicator signals ──────────────────────────────────────────────
        ind_signals = self._extract_indicator_signals(df, indicators, avg_volume)

        # ── 3. Component scores (-1 to +1) ───────────────────────────────────
        candle_score = self._candlestick_score(pattern_signal, pattern_conf)
        rsi_score    = self._rsi_score(indicators)
        macd_score   = self._macd_score(indicators)
        ema_score    = self._ema_score(ind_signals.ema_stack)
        bb_score     = self._bb_score(ind_signals.bb_position)
        vol_score    = self._volume_score(ind_signals.volume)

        composite = (
            candle_score * self.W_CANDLE
            + rsi_score  * self.W_RSI
            + macd_score * self.W_MACD
            + ema_score  * self.W_EMA
            + bb_score   * self.W_BB
            + vol_score  * self.W_VOL
        )
        composite = round(float(np.clip(composite, -1.0, 1.0)), 3)

        signal_label = self._score_to_label(composite)

        return ComputedSignals(
            candlestick=candlestick,
            indicators=ind_signals,
            composite_score=composite,
            signal_label=signal_label,
        )

    # ── Private helpers ───────────────────────────────────────────────────────

    def _candles_to_df(self, candles: List[Candle]) -> pd.DataFrame:
        if not candles:
            return pd.DataFrame(columns=["open", "high", "low", "close", "volume"])
        data = {
            "open":   [c.open   for c in candles],
            "high":   [c.high   for c in candles],
            "low":    [c.low    for c in candles],
            "close":  [c.close  for c in candles],
            "volume": [c.volume for c in candles],
        }
        return pd.DataFrame(data)

    def _extract_indicator_signals(
        self,
        df: pd.DataFrame,
        indicators: Optional[TechnicalIndicators],
        avg_volume: Optional[float],
    ) -> IndicatorSignals:
        """Convert TechnicalIndicators model → plain IndicatorSignals dict."""

        # RSI
        rsi_value = None
        rsi_signal = "NEUTRAL"
        if indicators and indicators.rsi:
            rsi_value = indicators.rsi.value
            raw_sig = (indicators.rsi.signal or "neutral").lower()
            if raw_sig == "overbought":
                rsi_signal = "OVERBOUGHT"
            elif raw_sig == "oversold":
                rsi_signal = "OVERSOLD"

        # MACD
        macd_signal = "NEUTRAL"
        macd_histogram = None
        if indicators and indicators.macd:
            macd_histogram = indicators.macd.histogram
            raw_trend = (indicators.macd.trend or "neutral").lower()
            if raw_trend == "bullish":
                macd_signal = "BULLISH"
            elif raw_trend == "bearish":
                macd_signal = "BEARISH"

        # EMA / SMA stack
        ema_stack = self._compute_ema_stack(indicators)

        # Bollinger Bands position
        bb_position = "MIDDLE"
        if indicators and indicators.bollinger_bands:
            pct_b = indicators.bollinger_bands.percent_b or 0.5
            if pct_b >= 1.0:
                bb_position = "ABOVE_UPPER"
            elif pct_b >= 0.75:
                bb_position = "UPPER"
            elif pct_b <= 0.0:
                bb_position = "BELOW_LOWER"
            elif pct_b <= 0.25:
                bb_position = "LOWER"

        # Volume (compare last candle volume vs avg_volume or rolling 20-period avg)
        volume = "AVERAGE"
        if not df.empty:
            last_vol = df["volume"].iloc[-1]
            if avg_volume is None and len(df) >= 20:
                avg_volume = df["volume"].rolling(20).mean().iloc[-1]
            if avg_volume and avg_volume > 0:
                ratio = last_vol / avg_volume
                if ratio > 1.5:
                    volume = "ABOVE_AVERAGE"
                elif ratio < 0.5:
                    volume = "BELOW_AVERAGE"

        return IndicatorSignals(
            rsi_value=round(rsi_value, 2) if rsi_value is not None else None,
            rsi_signal=rsi_signal,
            macd_signal=macd_signal,
            macd_histogram=round(float(macd_histogram), 4) if macd_histogram is not None else None,
            ema_stack=ema_stack,
            volume=volume,
            bb_position=bb_position,
        )

    def _compute_ema_stack(self, indicators: Optional[TechnicalIndicators]) -> str:
        if not indicators:
            return "MIXED"
        above_20  = indicators.above_sma_20
        above_50  = indicators.above_sma_50
        above_200 = indicators.above_sma_200
        # Count how many are True/False/None
        trues  = sum(1 for x in [above_20, above_50, above_200] if x is True)
        falses = sum(1 for x in [above_20, above_50, above_200] if x is False)
        if trues == 3:
            return "PRICE_ABOVE_ALL"
        elif trues == 2 and above_20 and above_50:
            return "PRICE_ABOVE_20_50"
        elif trues == 1 and above_20:
            return "PRICE_ABOVE_20"
        elif falses == 3:
            return "PRICE_BELOW_ALL"
        elif falses == 2 and not above_20 and not above_50:
            return "PRICE_BELOW_20_50"
        elif falses == 1 and above_20 is False:
            return "PRICE_BELOW_20"
        return "MIXED"

    # ── Scoring functions (-1 to +1) ─────────────────────────────────────────

    def _candlestick_score(self, signal: str, confidence: float) -> float:
        if signal == "BULLISH":
            return confidence
        if signal == "BEARISH":
            return -confidence
        return 0.0

    def _rsi_score(self, indicators: Optional[TechnicalIndicators]) -> float:
        if not indicators or not indicators.rsi:
            return 0.0
        v = indicators.rsi.value
        if v <= 30:
            return 1.0
        if v <= 45:
            return 0.35
        if v >= 70:
            return -1.0
        if v >= 55:
            return -0.35
        return 0.0   # 45–55 neutral zone

    def _macd_score(self, indicators: Optional[TechnicalIndicators]) -> float:
        if not indicators or not indicators.macd:
            return 0.0
        trend = (indicators.macd.trend or "neutral").lower()
        hist  = indicators.macd.histogram or 0.0
        if trend == "bullish":
            return 0.8 if hist > 0 else 0.4
        if trend == "bearish":
            return -0.8 if hist < 0 else -0.4
        return 0.0

    def _ema_score(self, ema_stack: str) -> float:
        mapping = {
            "PRICE_ABOVE_ALL":    1.0,
            "PRICE_ABOVE_20_50":  0.6,
            "PRICE_ABOVE_20":     0.3,
            "MIXED":              0.0,
            "PRICE_BELOW_20":    -0.3,
            "PRICE_BELOW_20_50": -0.6,
            "PRICE_BELOW_ALL":   -1.0,
        }
        return mapping.get(ema_stack, 0.0)

    def _bb_score(self, bb_position: str) -> float:
        mapping = {
            "BELOW_LOWER":  1.0,    # oversold, potential bounce
            "LOWER":        0.5,
            "MIDDLE":       0.0,
            "UPPER":       -0.5,
            "ABOVE_UPPER": -1.0,    # overbought
        }
        return mapping.get(bb_position, 0.0)

    def _volume_score(self, volume: str) -> float:
        # Volume is directionally neutral on its own — used as confirmation multiplier
        if volume == "ABOVE_AVERAGE":
            return 0.3
        if volume == "BELOW_AVERAGE":
            return -0.1
        return 0.0

    def _score_to_label(self, score: float) -> SignalLabel:
        if score >= 0.5:
            return SignalLabel.STRONG_BUY
        if score >= 0.15:
            return SignalLabel.BUY
        if score > -0.15:
            return SignalLabel.NEUTRAL
        if score > -0.5:
            return SignalLabel.SELL
        return SignalLabel.STRONG_SELL
