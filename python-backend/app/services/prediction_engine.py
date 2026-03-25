"""
Prediction Engine — Phase 4 (§5.2, §5.3)

Implements two of the four ensemble models:
  Model 1 (35% → 58%): Signal Consensus — composite_score from signal engine
  Model 3 (25% → 42%): ATR-Based Statistical Range

Both models agree on direction (they both derive from composite_score),
so the consensus is the signal strength itself.  The ATR provides the
price range and stop-loss.  Models 2 & 4 are added in Phase 5.
"""

import pandas as pd
import numpy as np
from typing import List, Optional
import logging

from ta.volatility import AverageTrueRange

from app.models.stock import Candle
from app.models.signals import ComputedSignals
from app.models.prediction import PredictionResult
from app.services.backtest_service import get_backtest_service

logger = logging.getLogger(__name__)

# Horizon label and ATR day-multiplier per candle interval
_HORIZON_MAP: dict = {
    "1m":  ("30 minutes",      0.5),
    "5m":  ("2 hours",         1.0),
    "15m": ("4 hours",         1.5),
    "30m": ("8 hours",         2.0),
    "1h":  ("1 trading day",   3.0),
    "2h":  ("2 trading days",  4.0),
    "4h":  ("3 trading days",  5.0),
    "12h": ("7 trading days",  7.0),
    "1d":  ("5 trading days",  5.0),
    "1wk": ("4 weeks",        20.0),
    "1w":  ("4 weeks",        20.0),
    "1M":  ("3 months",       60.0),
}


class PredictionEngine:
    """Computes a probability-weighted price range from computed signals + candles."""

    def calculate(
        self,
        candles: List[Candle],
        signals: ComputedSignals,
        current_price: Optional[float],
        interval: str = "1d",
    ) -> Optional[PredictionResult]:
        """
        Run the prediction engine.

        Returns None if there is insufficient data (< 15 candles).
        """
        if not candles or len(candles) < 15:
            logger.warning("[prediction] Insufficient candles for ATR calculation")
            return None

        price = current_price
        if price is None or price <= 0:
            price = candles[-1].close
        if price <= 0:
            return None

        df = self._to_df(candles)

        # ── ATR (14-period) ───────────────────────────────────────────────────
        atr = self._compute_atr(df)
        if atr is None or atr <= 0:
            # Fallback: 1% of price
            atr = price * 0.01

        # ── Model 1: Signal Consensus ─────────────────────────────────────────
        score = signals.composite_score   # -1.0 to +1.0
        label = signals.signal_label.value

        if score >= 0.15:
            direction = "BULLISH"
            models_bullish = 2
        elif score <= -0.15:
            direction = "BEARISH"
            models_bullish = 0
        else:
            direction = "NEUTRAL"
            models_bullish = 1

        # ── Probability — backtest lookup (Phase B) ───────────────────────────
        # Primary: use real win rate from backtest table for detected pattern
        # Fallback: formula (50% base + signal strength × 35%)
        backtest_win_rate = None
        backtest_sample_count = None
        backtest_avg_gain_pct = None
        backtest_pattern_key = None

        detected_pattern = signals.candlestick.pattern if signals.candlestick else None
        if detected_pattern:
            svc = get_backtest_service()
            bt = svc.lookup(detected_pattern, interval)
            if bt:
                backtest_win_rate   = bt.get("win_rate")
                backtest_sample_count = bt.get("sample_count")
                raw_gain = bt.get("avg_gain_pct")
                if raw_gain is not None:
                    backtest_avg_gain_pct = abs(raw_gain)  # always positive magnitude
                backtest_pattern_key = detected_pattern
                logger.info(
                    f"[prediction] Backtest hit: {detected_pattern}/{interval} "
                    f"win_rate={backtest_win_rate} samples={backtest_sample_count}"
                )

        if backtest_win_rate is not None:
            # Blend: 70% backtest + 30% signal strength (signal may deviate from historical)
            formula_prob = 0.50 + abs(score) * 0.35
            probability = round(0.70 * backtest_win_rate + 0.30 * formula_prob, 2)
            probability = max(0.40, min(0.92, probability))
        else:
            # No pattern detected or not in table — formula-only
            probability = round(0.50 + abs(score) * 0.35, 2)

        # ── Model 3: ATR-Based Price Range (§5.3) ─────────────────────────────
        horizon_label, horizon_mult = _HORIZON_MAP.get(
            interval.lower(), ("5 trading days", 5.0)
        )

        direction_mult = score  # -1.0 → +1.0
        target_base = price + (direction_mult * atr * horizon_mult * 0.6)
        target_high = target_base + (atr * 1.5)
        target_low  = target_base - (atr * 1.5)

        # ── Stop Loss ─────────────────────────────────────────────────────────
        # 2× ATR below current price (long) or above (short)
        if direction == "BULLISH":
            stop_loss = max(price - atr * 2.0, price * 0.85)  # cap at -15%
            upside   = target_high - price
            downside = price - stop_loss
        elif direction == "BEARISH":
            stop_loss = min(price + atr * 2.0, price * 1.15)
            upside   = price - target_low
            downside = stop_loss - price
        else:
            stop_loss = price - atr * 1.5
            upside   = abs(target_base - price)
            downside = atr * 1.5

        # ── Risk / Reward ─────────────────────────────────────────────────────
        risk_reward = round(upside / downside, 2) if downside > 0 else 1.0
        risk_reward = min(risk_reward, 10.0)  # cap at 10:1

        # ── Expected return % ─────────────────────────────────────────────────
        expected_return_pct = round((target_base - price) / price * 100, 2)

        # ── Consensus string ──────────────────────────────────────────────────
        consensus_str = f"{models_bullish}/2 models {direction}"

        return PredictionResult(
            direction=direction,
            probability=probability,
            horizon=horizon_label,
            price_current=round(price, 4),
            price_target_base=round(target_base, 4),
            price_target_high=round(target_high, 4),
            price_target_low=round(target_low, 4),
            expected_return_pct=expected_return_pct,
            risk_reward_ratio=risk_reward,
            stop_loss_suggestion=round(stop_loss, 4),
            model_consensus=consensus_str,
            atr_14=round(atr, 4),
            backtest_win_rate=backtest_win_rate,
            backtest_sample_count=backtest_sample_count,
            backtest_avg_gain_pct=backtest_avg_gain_pct,
            backtest_pattern=backtest_pattern_key,
        )

    # ── Helpers ───────────────────────────────────────────────────────────────

    def _to_df(self, candles: List[Candle]) -> pd.DataFrame:
        return pd.DataFrame({
            "high":  [c.high  for c in candles],
            "low":   [c.low   for c in candles],
            "close": [c.close for c in candles],
        })

    def _compute_atr(self, df: pd.DataFrame) -> Optional[float]:
        try:
            atr_ind = AverageTrueRange(
                high=df["high"], low=df["low"], close=df["close"], window=14
            )
            val = atr_ind.average_true_range().iloc[-1]
            return float(val) if not np.isnan(val) else None
        except Exception as e:
            logger.warning(f"[prediction] ATR computation error: {e}")
            return None
