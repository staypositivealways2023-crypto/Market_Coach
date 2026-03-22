"""Pattern Engine — Phase 6 chart pattern detection from OHLCV data.

Approach: pivot-point analysis (no TA-Lib required).
  1. Detect local highs/lows (pivot points) with configurable lookback
  2. Match pivot sequences against known pattern templates
  3. Cluster horizontal price levels into Support/Resistance zones
  4. Determine overall trend direction from linear regression on closes
"""

from typing import List, Tuple, Optional
import statistics

from app.models.patterns import ChartPattern, SupportResistanceLevel, PatternScanResult


# ── Constants ─────────────────────────────────────────────────────────────────
_PIVOT_LB = 5          # pivot lookback window each side
_SR_TOL   = 0.015      # 1.5% price tolerance for S/R clustering
_MIN_CONF = 0.45       # minimum confidence to report a pattern


class PatternEngine:
    """
    Stateless pattern scanner.  Call `scan(candles)` where candles is a list
    of dicts with keys: open, high, low, close, volume.
    Returns a PatternScanResult.
    """

    def scan(self, candles) -> PatternScanResult:
        """candles: list of Candle objects (Pydantic) or plain dicts."""
        if len(candles) < 30:
            return PatternScanResult()

        def _g(c, k):  # get field from Pydantic model or dict
            return getattr(c, k) if hasattr(c, k) else c[k]

        highs  = [_g(c, "high")  for c in candles]
        lows   = [_g(c, "low")   for c in candles]
        closes = [_g(c, "close") for c in candles]

        pivot_highs = self._pivot_highs(highs, lows, closes)
        pivot_lows  = self._pivot_lows(highs, lows, closes)

        trend, trend_strength = self._trend(closes)
        sr_levels = self._support_resistance(pivot_highs, pivot_lows, closes[-1])
        patterns: List[ChartPattern] = []

        patterns += self._double_top(pivot_highs, closes[-1])
        patterns += self._double_bottom(pivot_lows, closes[-1])
        patterns += self._head_and_shoulders(pivot_highs, closes[-1])
        patterns += self._inv_head_and_shoulders(pivot_lows, closes[-1])
        patterns += self._triangles(pivot_highs, pivot_lows, closes)
        patterns += self._flags(candles, trend)

        # Keep top-3 chart patterns
        chart_patterns = sorted(
            [p for p in patterns if p.confidence >= _MIN_CONF],
            key=lambda p: p.confidence, reverse=True
        )[:3]

        # Candlestick patterns — scan recent candles, keep top-5
        candle_patterns = sorted(
            [p for p in self._candlestick_patterns(candles) if p.confidence >= _MIN_CONF],
            key=lambda p: p.confidence, reverse=True
        )[:5]

        all_patterns = chart_patterns + candle_patterns

        return PatternScanResult(
            patterns=all_patterns,
            support_resistance=sr_levels[:5],
            trend=trend,
            trend_strength=trend_strength,
        )

    # ── Pivot Detection ───────────────────────────────────────────────────────

    def _pivot_highs(self, highs, lows, closes) -> List[Tuple[int, float]]:
        """Returns (index, price) for each local high."""
        pivots = []
        lb = _PIVOT_LB
        for i in range(lb, len(highs) - lb):
            if all(highs[i] >= highs[i - j] for j in range(1, lb + 1)) and \
               all(highs[i] >= highs[i + j] for j in range(1, lb + 1)):
                pivots.append((i, highs[i]))
        return pivots

    def _pivot_lows(self, highs, lows, closes) -> List[Tuple[int, float]]:
        """Returns (index, price) for each local low."""
        pivots = []
        lb = _PIVOT_LB
        for i in range(lb, len(lows) - lb):
            if all(lows[i] <= lows[i - j] for j in range(1, lb + 1)) and \
               all(lows[i] <= lows[i + j] for j in range(1, lb + 1)):
                pivots.append((i, lows[i]))
        return pivots

    # ── Trend ─────────────────────────────────────────────────────────────────

    def _trend(self, closes: List[float]) -> Tuple[str, str]:
        """Linear regression slope over last 50 candles to determine trend."""
        n = min(50, len(closes))
        subset = closes[-n:]
        x_mean = (n - 1) / 2
        y_mean = sum(subset) / n
        num = sum((i - x_mean) * (v - y_mean) for i, v in enumerate(subset))
        den = sum((i - x_mean) ** 2 for i in range(n))
        if den == 0:
            return "SIDEWAYS", "WEAK"

        slope_pct = (num / den) / (y_mean or 1) * 100  # slope as % of avg price per candle

        if slope_pct > 0.15:
            trend = "UPTREND"
        elif slope_pct < -0.15:
            trend = "DOWNTREND"
        else:
            trend = "SIDEWAYS"

        strength = "STRONG" if abs(slope_pct) > 0.4 else "MODERATE" if abs(slope_pct) > 0.2 else "WEAK"
        return trend, strength

    # ── Support / Resistance ──────────────────────────────────────────────────

    def _support_resistance(
        self, pivot_highs, pivot_lows, current_price: float
    ) -> List[SupportResistanceLevel]:
        all_pivots = [(p, "RESISTANCE") for _, p in pivot_highs] + \
                     [(p, "SUPPORT") for _, p in pivot_lows]

        clusters: List[Tuple[float, str, int]] = []  # (price, type, strength)
        used = set()
        for i, (price, ptype) in enumerate(all_pivots):
            if i in used:
                continue
            group = [price]
            for j, (p2, _) in enumerate(all_pivots):
                if j != i and j not in used and abs(p2 - price) / (price or 1) < _SR_TOL:
                    group.append(p2)
                    used.add(j)
            if len(group) >= 2:
                avg = sum(group) / len(group)
                clusters.append((avg, ptype, len(group)))
            used.add(i)

        levels = []
        for price, ptype, strength in sorted(clusters, key=lambda x: -x[2]):
            # Reclassify relative to current price
            level_type = "RESISTANCE" if price > current_price else "SUPPORT"
            desc = (
                f"Price bounced from ~${price:.2f} at least {strength}x — "
                f"{'overhead resistance' if level_type == 'RESISTANCE' else 'floor support'}."
            )
            levels.append(SupportResistanceLevel(
                price=round(price, 4),
                type=level_type,
                strength=strength,
                description=desc,
            ))
        return levels

    # ── Double Top ────────────────────────────────────────────────────────────

    def _double_top(self, pivot_highs, current_price: float) -> List[ChartPattern]:
        if len(pivot_highs) < 2:
            return []
        results = []
        ph = pivot_highs[-6:]  # look at last 6 pivot highs
        for i in range(len(ph) - 1):
            idx1, p1 = ph[i]
            idx2, p2 = ph[i + 1]
            if idx2 - idx1 < 5:  # peaks too close
                continue
            similarity = abs(p1 - p2) / ((p1 + p2) / 2)
            if similarity > 0.04:  # peaks must be within 4%
                continue
            neckline = min(p1, p2) * 0.97  # approximate neckline
            conf = round(max(0.5, 0.9 - similarity * 10), 2)
            results.append(ChartPattern(
                type="DOUBLE_TOP",
                signal="BEARISH",
                confidence=conf,
                description=(
                    f"Double top at ~${(p1 + p2) / 2:.2f} — "
                    "two failed attempts to break higher suggest bearish reversal. "
                    f"Watch for break below ${neckline:.2f}."
                ),
                key_price=round(neckline, 4),
                formed_at_index=idx2,
            ))
        return results

    # ── Double Bottom ─────────────────────────────────────────────────────────

    def _double_bottom(self, pivot_lows, current_price: float) -> List[ChartPattern]:
        if len(pivot_lows) < 2:
            return []
        results = []
        pl = pivot_lows[-6:]
        for i in range(len(pl) - 1):
            idx1, p1 = pl[i]
            idx2, p2 = pl[i + 1]
            if idx2 - idx1 < 5:
                continue
            similarity = abs(p1 - p2) / ((p1 + p2) / 2)
            if similarity > 0.04:
                continue
            neckline = max(p1, p2) * 1.03
            conf = round(max(0.5, 0.9 - similarity * 10), 2)
            results.append(ChartPattern(
                type="DOUBLE_BOTTOM",
                signal="BULLISH",
                confidence=conf,
                description=(
                    f"Double bottom at ~${(p1 + p2) / 2:.2f} — "
                    "two bounces from the same level suggest buyers stepping in. "
                    f"Breakout target above ${neckline:.2f}."
                ),
                key_price=round(neckline, 4),
                formed_at_index=idx2,
            ))
        return results

    # ── Head & Shoulders ──────────────────────────────────────────────────────

    def _head_and_shoulders(self, pivot_highs, current_price: float) -> List[ChartPattern]:
        if len(pivot_highs) < 3:
            return []
        results = []
        ph = pivot_highs[-8:]
        for i in range(len(ph) - 2):
            _, ls = ph[i]       # left shoulder
            _, h  = ph[i + 1]   # head
            _, rs = ph[i + 2]   # right shoulder
            if h <= max(ls, rs):
                continue
            shoulder_diff = abs(ls - rs) / ((ls + rs) / 2)
            if shoulder_diff > 0.05:
                continue
            neckline = (ls + rs) / 2 * 0.97
            conf = round(min(0.88, 0.65 + (1 - shoulder_diff * 10) * 0.3), 2)
            results.append(ChartPattern(
                type="HEAD_SHOULDERS",
                signal="BEARISH",
                confidence=conf,
                description=(
                    f"Head & Shoulders pattern with head at ${h:.2f} — "
                    "classic bearish reversal signal. "
                    f"Neckline at ~${neckline:.2f}; break below triggers target."
                ),
                key_price=round(neckline, 4),
                formed_at_index=ph[i + 2][0],
            ))
        return results

    # ── Inverse Head & Shoulders ──────────────────────────────────────────────

    def _inv_head_and_shoulders(self, pivot_lows, current_price: float) -> List[ChartPattern]:
        if len(pivot_lows) < 3:
            return []
        results = []
        pl = pivot_lows[-8:]
        for i in range(len(pl) - 2):
            _, ls = pl[i]
            _, h  = pl[i + 1]
            _, rs = pl[i + 2]
            if h >= min(ls, rs):
                continue
            shoulder_diff = abs(ls - rs) / ((ls + rs) / 2)
            if shoulder_diff > 0.05:
                continue
            neckline = (ls + rs) / 2 * 1.03
            conf = round(min(0.88, 0.65 + (1 - shoulder_diff * 10) * 0.3), 2)
            results.append(ChartPattern(
                type="INV_HEAD_SHOULDERS",
                signal="BULLISH",
                confidence=conf,
                description=(
                    f"Inverse Head & Shoulders with head at ${h:.2f} — "
                    "classic bullish reversal pattern. "
                    f"Breakout above neckline ${neckline:.2f} confirms signal."
                ),
                key_price=round(neckline, 4),
                formed_at_index=pl[i + 2][0],
            ))
        return results

    # ── Triangle Patterns ─────────────────────────────────────────────────────

    def _triangles(self, pivot_highs, pivot_lows, closes) -> List[ChartPattern]:
        results = []
        if len(pivot_highs) < 2 or len(pivot_lows) < 2:
            return results

        ph = pivot_highs[-4:]
        pl = pivot_lows[-4:]

        h_slope = self._slope([p for _, p in ph])
        l_slope = self._slope([p for _, p in pl])

        current = closes[-1]

        if h_slope < -0.001 and l_slope > 0.001:
            # Highs falling, lows rising → Symmetrical
            results.append(ChartPattern(
                type="SYMMETRICAL_TRIANGLE",
                signal="NEUTRAL",
                confidence=0.62,
                description=(
                    "Symmetrical triangle — price coiling as highs drop and lows rise. "
                    "A breakout in either direction is expected. Watch for volume surge."
                ),
                key_price=round(current, 4),
            ))
        elif abs(h_slope) < 0.0005 and l_slope > 0.001:
            # Flat top, rising bottom → Ascending
            resistance = [p for _, p in ph][-1]
            results.append(ChartPattern(
                type="ASCENDING_TRIANGLE",
                signal="BULLISH",
                confidence=0.68,
                description=(
                    f"Ascending triangle — flat resistance at ~${resistance:.2f} with higher lows. "
                    "Buyers are gaining strength; breakout above resistance is the setup."
                ),
                key_price=round(resistance, 4),
            ))
        elif h_slope < -0.001 and abs(l_slope) < 0.0005:
            # Falling top, flat bottom → Descending
            support = [p for _, p in pl][-1]
            results.append(ChartPattern(
                type="DESCENDING_TRIANGLE",
                signal="BEARISH",
                confidence=0.68,
                description=(
                    f"Descending triangle — flat support at ~${support:.2f} with lower highs. "
                    "Sellers are gaining control; watch for break below support."
                ),
                key_price=round(support, 4),
            ))
        return results

    # ── Flag / Pennant ────────────────────────────────────────────────────────

    def _flags(self, candles, trend: str) -> List[ChartPattern]:
        """Detect bull/bear flags: strong move followed by tight consolidation."""
        def _g(c, k):
            return getattr(c, k) if hasattr(c, k) else c[k]

        results = []
        if len(candles) < 20:
            return results

        pole = candles[-20:-5]
        flag = candles[-5:]

        pole_move = (_g(pole[-1], "close") - _g(pole[0], "close")) / (_g(pole[0], "close") or 1)
        flag_range_highs = max(_g(c, "high") for c in flag)
        flag_range_lows  = min(_g(c, "low")  for c in flag)
        flag_range_pct   = (flag_range_highs - flag_range_lows) / (flag_range_lows or 1)

        # Flag condition: pole > 5% move, flag consolidation < 3% range
        if abs(pole_move) > 0.05 and flag_range_pct < 0.03:
            if pole_move > 0:
                results.append(ChartPattern(
                    type="BULL_FLAG",
                    signal="BULLISH",
                    confidence=0.70,
                    description=(
                        f"Bull flag — strong {pole_move*100:.1f}% upward pole followed by tight "
                        "consolidation. Continuation pattern; breakout above flag top expected."
                    ),
                    key_price=round(flag_range_highs, 4),
                    formed_at_index=len(candles) - 1,
                ))
            else:
                results.append(ChartPattern(
                    type="BEAR_FLAG",
                    signal="BEARISH",
                    confidence=0.70,
                    description=(
                        f"Bear flag — sharp {abs(pole_move)*100:.1f}% decline followed by tight "
                        "consolidation. Continuation pattern; breakdown below flag low expected."
                    ),
                    key_price=round(flag_range_lows, 4),
                    formed_at_index=len(candles) - 1,
                ))
        return results

    # ── Helpers ───────────────────────────────────────────────────────────────

    def _slope(self, values: List[float]) -> float:
        """Simple linear slope of a value series."""
        n = len(values)
        if n < 2:
            return 0.0
        x_mean = (n - 1) / 2
        y_mean = sum(values) / n
        num = sum((i - x_mean) * (v - y_mean) for i, v in enumerate(values))
        den = sum((i - x_mean) ** 2 for i in range(n))
        return (num / den) / (y_mean or 1) if den else 0.0

    # ── Candlestick Pattern Detection ─────────────────────────────────────────

    def _candlestick_patterns(self, candles) -> List[ChartPattern]:
        """Detect single and multi-candle formations on the last 30 candles."""
        results: List[ChartPattern] = []
        n = len(candles)

        def _g(c, k):
            return getattr(c, k) if hasattr(c, k) else c[k]

        # Only scan the most recent 30 candles — keeps chart readable
        start = max(2, n - 30)

        for i in range(start, n):
            c  = candles[i]
            c1 = candles[i - 1]
            c2 = candles[i - 2]

            o,  h,  l,  cl  = _g(c,  'open'), _g(c,  'high'), _g(c,  'low'), _g(c,  'close')
            o1, h1, l1, cl1 = _g(c1, 'open'), _g(c1, 'high'), _g(c1, 'low'), _g(c1, 'close')
            o2, h2, l2, cl2 = _g(c2, 'open'), _g(c2, 'high'), _g(c2, 'low'), _g(c2, 'close')

            body  = abs(cl  - o)
            body1 = abs(cl1 - o1)
            rng   = h  - l
            rng1  = h1 - l1

            if rng < 1e-8 or rng1 < 1e-8:
                continue

            body_pct  = body  / rng
            upper_wick = h  - max(o,  cl)
            lower_wick = min(o,  cl)  - l
            upper_wick1 = h1 - max(o1, cl1)
            lower_wick1 = min(o1, cl1) - l1

            # ── Single-candle ──────────────────────────────────────────────

            # Doji — body < 10% of range
            if body_pct < 0.10:
                results.append(ChartPattern(
                    type='DOJI', signal='NEUTRAL',
                    confidence=min(0.55 + (0.10 - body_pct) * 3, 0.85),
                    description='Indecision candle — neither buyers nor sellers won',
                    key_price=cl, formed_at_index=i,
                ))

            # Hammer — small body at top, long lower wick (≥2× body), tiny upper wick
            elif (lower_wick >= 2 * max(body, rng * 0.01) and
                  upper_wick <= body * 0.5 and body_pct < 0.40 and cl >= o):
                conf = min(0.60 + (lower_wick / (body + 1e-8) - 2) * 0.05, 0.85)
                results.append(ChartPattern(
                    type='HAMMER', signal='BULLISH',
                    confidence=conf,
                    description='Bullish reversal — buyers pushed back from the lows',
                    key_price=l, formed_at_index=i,
                ))

            # Hanging Man — same shape as hammer but bearish (candle bearish)
            elif (lower_wick >= 2 * max(body, rng * 0.01) and
                  upper_wick <= body * 0.5 and body_pct < 0.40 and cl < o):
                results.append(ChartPattern(
                    type='HANGING_MAN', signal='BEARISH',
                    confidence=0.55,
                    description='Bearish warning after uptrend — sellers starting to appear',
                    key_price=h, formed_at_index=i,
                ))

            # Shooting Star — long upper wick, small body at bottom
            elif (upper_wick >= 2 * max(body, rng * 0.01) and
                  lower_wick <= body * 0.5 and body_pct < 0.40 and cl < o):
                conf = min(0.60 + (upper_wick / (body + 1e-8) - 2) * 0.05, 0.85)
                results.append(ChartPattern(
                    type='SHOOTING_STAR', signal='BEARISH',
                    confidence=conf,
                    description='Bearish reversal — buyers failed to hold the rally',
                    key_price=h, formed_at_index=i,
                ))

            # Inverted Hammer — long upper wick, bullish body (potential reversal at bottom)
            elif (upper_wick >= 2 * max(body, rng * 0.01) and
                  lower_wick <= body * 0.5 and body_pct < 0.40 and cl >= o):
                results.append(ChartPattern(
                    type='INVERTED_HAMMER', signal='BULLISH',
                    confidence=0.55,
                    description='Potential bullish reversal — buyers testing the highs',
                    key_price=l, formed_at_index=i,
                ))

            # Marubozu — body dominates, nearly no wicks
            elif body_pct > 0.85:
                signal = 'BULLISH' if cl > o else 'BEARISH'
                results.append(ChartPattern(
                    type='MARUBOZU', signal=signal,
                    confidence=0.65,
                    description='Strong conviction candle — one side completely dominated',
                    key_price=cl, formed_at_index=i,
                ))

            # ── Two-candle ─────────────────────────────────────────────────

            # Bullish Engulfing — bearish c1, bullish c that fully engulfs c1
            if (cl1 < o1 and cl > o and o <= cl1 and cl >= o1):
                conf = min(0.65 + (body / (body1 + 1e-8) - 1) * 0.08, 0.88)
                results.append(ChartPattern(
                    type='BULLISH_ENGULFING', signal='BULLISH',
                    confidence=conf,
                    description='Strong bullish reversal — buyers overwhelmed sellers',
                    key_price=cl, formed_at_index=i,
                ))

            # Bearish Engulfing — bullish c1, bearish c that fully engulfs c1
            elif (cl1 > o1 and cl < o and o >= cl1 and cl <= o1):
                conf = min(0.65 + (body / (body1 + 1e-8) - 1) * 0.08, 0.88)
                results.append(ChartPattern(
                    type='BEARISH_ENGULFING', signal='BEARISH',
                    confidence=conf,
                    description='Strong bearish reversal — sellers overwhelmed buyers',
                    key_price=cl, formed_at_index=i,
                ))

            # Bullish Harami — bearish c1 contains small bullish c
            elif (cl1 < o1 and cl > o and o > cl1 and cl < o1 and body < body1 * 0.5):
                results.append(ChartPattern(
                    type='BULLISH_HARAMI', signal='BULLISH',
                    confidence=0.55,
                    description='Inside reversal — selling momentum is slowing',
                    key_price=cl, formed_at_index=i,
                ))

            # Bearish Harami — bullish c1 contains small bearish c
            elif (cl1 > o1 and cl < o and o < cl1 and cl > o1 and body < body1 * 0.5):
                results.append(ChartPattern(
                    type='BEARISH_HARAMI', signal='BEARISH',
                    confidence=0.55,
                    description='Inside reversal — buying momentum is slowing',
                    key_price=cl, formed_at_index=i,
                ))

            # ── Three-candle ───────────────────────────────────────────────

            # Morning Star — bearish c2, small-body c1 (star), bullish c
            if (cl2 < o2 and
                    abs(cl1 - o1) < rng1 * 0.30 and
                    cl > o and cl > (o2 + cl2) / 2):
                results.append(ChartPattern(
                    type='MORNING_STAR', signal='BULLISH',
                    confidence=0.72,
                    description='Three-candle bullish reversal at the bottom of a downtrend',
                    key_price=cl, formed_at_index=i,
                ))

            # Evening Star — bullish c2, small-body c1 (star), bearish c
            elif (cl2 > o2 and
                    abs(cl1 - o1) < rng1 * 0.30 and
                    cl < o and cl < (o2 + cl2) / 2):
                results.append(ChartPattern(
                    type='EVENING_STAR', signal='BEARISH',
                    confidence=0.72,
                    description='Three-candle bearish reversal at the top of an uptrend',
                    key_price=cl, formed_at_index=i,
                ))

        return results
