"""Candlestick Pattern Detection - Pure Python, no TA-Lib required.

Detects the 12 highest-reliability patterns and returns the most significant
one found in the last 3 candles.  Returns (pattern_name, signal, confidence).
"""

import pandas as pd
from typing import Optional, Tuple


def detect_candlestick_pattern(df: pd.DataFrame) -> Tuple[Optional[str], str, float]:
    """
    Detect the most significant candlestick pattern in the most recent candles.

    Args:
        df: DataFrame with columns [open, high, low, close, volume], sorted ascending.

    Returns:
        (pattern_name | None, signal, confidence)
        signal:     "BULLISH" | "BEARISH" | "NEUTRAL"
        confidence: 0.0 – 1.0
    """
    if len(df) < 3:
        return None, "NEUTRAL", 0.0

    c0 = df.iloc[-3]   # 3 candles ago
    c1 = df.iloc[-2]   # previous candle
    c2 = df.iloc[-1]   # current candle

    # ── Helpers ────────────────────────────────────────────────────────────────
    def body(c):         return abs(c["close"] - c["open"])
    def rng(c):          return c["high"] - c["low"]
    def upper_shadow(c): return c["high"] - max(c["open"], c["close"])
    def lower_shadow(c): return min(c["open"], c["close"]) - c["low"]
    def is_bull(c):      return c["close"] > c["open"]
    def is_bear(c):      return c["close"] < c["open"]
    def is_doji(c):      return rng(c) > 0 and body(c) <= rng(c) * 0.1
    def midpoint(c):     return (c["open"] + c["close"]) / 2

    # ── 3-Candle Patterns (highest priority) ───────────────────────────────────

    # 1. Three White Soldiers — very strong bullish continuation
    if (is_bull(c0) and is_bull(c1) and is_bull(c2)
            and c1["open"] > c0["open"] and c1["open"] < c0["close"]
            and c2["open"] > c1["open"] and c2["open"] < c1["close"]
            and c2["close"] > c1["close"] > c0["close"]):
        return "Three White Soldiers", "BULLISH", 0.90

    # 2. Three Black Crows — very strong bearish continuation
    if (is_bear(c0) and is_bear(c1) and is_bear(c2)
            and c1["open"] < c0["open"] and c1["open"] > c0["close"]
            and c2["open"] < c1["open"] and c2["open"] > c1["close"]
            and c2["close"] < c1["close"] < c0["close"]):
        return "Three Black Crows", "BEARISH", 0.90

    # 3. Morning Star — bullish reversal (bearish → indecision → bullish)
    if (is_bear(c0) and body(c0) > rng(c0) * 0.5
            and (is_doji(c1) or body(c1) < body(c0) * 0.3)
            and is_bull(c2) and c2["close"] > midpoint(c0)):
        return "Morning Star", "BULLISH", 0.85

    # 4. Evening Star — bearish reversal (bullish → indecision → bearish)
    if (is_bull(c0) and body(c0) > rng(c0) * 0.5
            and (is_doji(c1) or body(c1) < body(c0) * 0.3)
            and is_bear(c2) and c2["close"] < midpoint(c0)):
        return "Evening Star", "BEARISH", 0.85

    # ── 2-Candle Patterns ──────────────────────────────────────────────────────

    # 5. Bullish Engulfing — current bull body wraps previous bear body
    if (is_bear(c1) and is_bull(c2)
            and c2["open"] <= c1["close"]
            and c2["close"] >= c1["open"]
            and body(c2) > body(c1)):
        return "Bullish Engulfing", "BULLISH", 0.82

    # 6. Bearish Engulfing — current bear body wraps previous bull body
    if (is_bull(c1) and is_bear(c2)
            and c2["open"] >= c1["close"]
            and c2["close"] <= c1["open"]
            and body(c2) > body(c1)):
        return "Bearish Engulfing", "BEARISH", 0.82

    # 7. Piercing Line — bullish; opens below prior low, closes above midpoint
    if (is_bear(c1) and is_bull(c2)
            and c2["open"] < c1["low"]
            and c2["close"] > midpoint(c1)
            and c2["close"] < c1["open"]):
        return "Piercing Line", "BULLISH", 0.75

    # 8. Dark Cloud Cover — bearish; opens above prior high, closes below midpoint
    if (is_bull(c1) and is_bear(c2)
            and c2["open"] > c1["high"]
            and c2["close"] < midpoint(c1)
            and c2["close"] > c1["open"]):
        return "Dark Cloud Cover", "BEARISH", 0.75

    # ── Single-Candle Patterns ─────────────────────────────────────────────────

    # Determine trend context using last available candles
    prior_close = df.iloc[-6]["close"] if len(df) >= 6 else df.iloc[0]["close"]
    in_downtrend = c2["close"] < prior_close
    in_uptrend = c2["close"] > prior_close

    # 9. Hammer — small body at top, long lower shadow; bullish at bottom of downtrend
    if (body(c2) <= rng(c2) * 0.3
            and lower_shadow(c2) >= body(c2) * 2.0
            and upper_shadow(c2) <= body(c2) * 0.5
            and in_downtrend):
        return "Hammer", "BULLISH", 0.78

    # 10. Shooting Star — small body at bottom, long upper shadow; bearish at top of uptrend
    if (body(c2) <= rng(c2) * 0.3
            and upper_shadow(c2) >= body(c2) * 2.0
            and lower_shadow(c2) <= body(c2) * 0.5
            and in_uptrend):
        return "Shooting Star", "BEARISH", 0.78

    # 11. Inverted Hammer — long upper shadow at bottom of downtrend; bullish reversal signal
    if (body(c2) <= rng(c2) * 0.3
            and upper_shadow(c2) >= body(c2) * 2.0
            and lower_shadow(c2) <= body(c2) * 0.5
            and in_downtrend):
        return "Inverted Hammer", "BULLISH", 0.65

    # 12. Doji — open ≈ close; signals indecision / potential reversal
    if is_doji(c2):
        return "Doji", "NEUTRAL", 0.55

    return None, "NEUTRAL", 0.0
