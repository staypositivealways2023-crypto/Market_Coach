"""Prediction Engine Models — probability-weighted price range output (§5.1)"""

from typing import Optional
from pydantic import BaseModel


class PredictionResult(BaseModel):
    direction: str             # BULLISH | BEARISH | NEUTRAL
    probability: float         # 0.50 – 0.85 (confidence in direction)
    horizon: str               # human-readable horizon e.g. "5 trading days"
    price_current: float       # price at time of analysis
    price_target_base: float   # central projection (direction_mult × ATR)
    price_target_high: float   # bull case  (+1.5 ATR from base)
    price_target_low: float    # bear case  (−1.5 ATR from base)
    expected_return_pct: float # (target_base − current) / current × 100
    risk_reward_ratio: float   # upside / downside  (always positive)
    stop_loss_suggestion: float
    model_consensus: str       # "2/2 models BULLISH"
    atr_14: float              # raw ATR value for reference

    # ── Backtest fields (Phase B) ─────────────────────────────────────────────
    backtest_win_rate: Optional[float] = None      # e.g. 0.67
    backtest_sample_count: Optional[int] = None    # e.g. 312
    backtest_avg_gain_pct: Optional[float] = None  # e.g. 5.2
    backtest_pattern: Optional[str] = None         # pattern that sourced the data
