"""Correlation Engine — News × Price Scenario + Fundamental Scoring (§4.2, §4.3)"""

import re
from typing import List, Optional, Dict, Any
from app.models.correlation import CorrelationResult

# ── High-impact keyword groups ────────────────────────────────────────────────
_HIGH_IMPACT_KEYWORDS: Dict[str, str] = {
    r"\bearnings?\b":          "Earnings Report",
    r"\bguidance\b":           "Guidance Update",
    r"\bfda\b":                "FDA Decision",
    r"\bmerger\b|\bacquisition\b|\btakeover\b": "M&A Activity",
    r"\bbankrupt\b|\bchapter\s*11\b":           "Bankruptcy Risk",
    r"\blawsuit\b|\blitigation\b|\bsettlement\b": "Legal Action",
    r"\binvestigation\b|\bsec\s+probe\b":       "Regulatory Probe",
    r"\blayoff\b|\brestructur\b":               "Restructuring",
    r"\bwar\b|\bconflict\b|\bsanction\b":       "Geopolitical Risk",
    r"\bdividend\b":           "Dividend Event",
    r"\bstock\s+split\b|\bsplit\b":             "Stock Split",
    r"\bbuyback\b|\brepurchas\b":               "Share Buyback",
    r"\bdowngrad\b":           "Analyst Downgrade",
    r"\bupgrad\b":             "Analyst Upgrade",
    r"\brecall\b":             "Product Recall",
    r"\brate\s+hike\b|\brate\s+cut\b|\bfed\b|\bfomc\b": "Fed / Rate Decision",
}

# ── Scenario table §4.3 ────────────────────────────────────────────────────────
# (sentiment_label, price_direction) → (scenario_key, label, description)
_SCENARIOS: Dict[tuple, tuple] = {
    ("positive", "RISING"):  ("BULLISH_CONFIRMATION",   "Confirmed Uptrend",
                               "Good news is driving real buying — a textbook bullish setup."),
    ("positive", "FALLING"): ("DIVERGENCE_BULLISH",     "Positive News, Falling Price",
                               "Buyers may be exhausted or sellers are front-running good news — watch for reversal."),
    ("positive", "FLAT"):    ("POSITIVE_FLAT",          "Accumulation Zone",
                               "Good news without price reaction often precedes a breakout."),
    ("negative", "FALLING"): ("BEARISH_CONFIRMATION",   "Confirmed Downtrend",
                               "Bad news is driving real selling — proceed with caution."),
    ("negative", "RISING"):  ("DIVERGENCE_BEARISH",     "Negative News, Rising Price",
                               "Bears may be exhausted or shorts are being squeezed — often unsustainable."),
    ("negative", "FLAT"):    ("NEGATIVE_FLAT",          "Distribution Zone",
                               "Bad news without price reaction may indicate smart money quietly exiting."),
    ("neutral",  "RISING"):  ("QUIET_RISING",           "Quiet Accumulation",
                               "Price rising on low-news environment — momentum-driven move."),
    ("neutral",  "FALLING"): ("QUIET_FALLING",          "Quiet Distribution",
                               "Price falling without catalysts — watch for support levels."),
    ("neutral",  "FLAT"):    ("QUIET_MARKET",           "Quiet Market",
                               "No strong news or price trend — sideways consolidation."),
}


class CorrelationEngine:
    """
    Correlates news sentiment with price direction and scores fundamentals.
    All inputs are pre-computed Python dicts — no external API calls made here.
    """

    # ── Public interface ──────────────────────────────────────────────────────

    def run(
        self,
        news: List[Dict[str, Any]],
        quote: Dict[str, Any],
        fundamentals: Optional[Dict[str, Any]] = None,
        is_crypto: bool = False,
    ) -> CorrelationResult:
        sentiment_score, sentiment_label, headlines, flags = self._analyse_news(news)
        price_direction = self._price_direction(quote)
        scenario_key, scenario_label, scenario_desc = self._get_scenario(
            sentiment_label, price_direction
        )

        fund_score: Optional[int] = None
        fund_grade: Optional[str] = None
        fund_signals: List[str] = []

        if not is_crypto and fundamentals:
            fund_score, fund_grade, fund_signals = self._score_fundamentals(fundamentals)

        return CorrelationResult(
            news_sentiment_score=round(sentiment_score, 3),
            sentiment_label=sentiment_label,
            top_headlines=headlines,
            high_impact_flags=flags,
            price_direction=price_direction,
            scenario=scenario_key,
            scenario_label=scenario_label,
            scenario_description=scenario_desc,
            fundamental_score=fund_score,
            fundamental_grade=fund_grade,
            fundamental_signals=fund_signals,
        )

    # ── News sentiment ────────────────────────────────────────────────────────

    def _analyse_news(
        self, news: List[Dict[str, Any]]
    ) -> tuple:
        if not news:
            return 0.0, "neutral", [], []

        scores: List[float] = []
        headlines: List[str] = []
        flags_set: set = set()

        for article in news[:15]:
            # Collect headline (NewsArticle uses 'title'; some sources use 'headline')
            title = article.get("title") or article.get("headline") or ""
            if title and len(headlines) < 3:
                truncated = title[:100] + "…" if len(title) > 100 else title
                headlines.append(truncated)

            # Sentiment score (provided by news service or default 0)
            raw_score = article.get("sentiment_score", 0)
            try:
                scores.append(float(raw_score))
            except (TypeError, ValueError):
                scores.append(0.0)

            # High-impact keyword detection across title + summary
            text = f"{title} {article.get('summary', '')}".lower()
            for pattern, flag_label in _HIGH_IMPACT_KEYWORDS.items():
                if re.search(pattern, text, re.IGNORECASE) and flag_label not in flags_set:
                    flags_set.add(flag_label)

        avg_score = sum(scores) / len(scores) if scores else 0.0

        if avg_score > 0.05:
            label = "positive"
        elif avg_score < -0.05:
            label = "negative"
        else:
            label = "neutral"

        return avg_score, label, headlines, sorted(flags_set)

    # ── Price direction ───────────────────────────────────────────────────────

    def _price_direction(self, quote: Dict[str, Any]) -> str:
        change_pct = quote.get("change_percent", 0) or 0
        try:
            change_pct = float(change_pct)
        except (TypeError, ValueError):
            change_pct = 0.0

        if change_pct >= 0.5:
            return "RISING"
        elif change_pct <= -0.5:
            return "FALLING"
        return "FLAT"

    # ── Scenario lookup ───────────────────────────────────────────────────────

    def _get_scenario(self, sentiment_label: str, price_direction: str) -> tuple:
        key = (sentiment_label, price_direction)
        if key in _SCENARIOS:
            return _SCENARIOS[key]
        # Fallback
        return ("QUIET_MARKET", "Quiet Market", "No strong directional signal at this time.")

    # ── Fundamental scoring §4.2 ──────────────────────────────────────────────

    def _score_fundamentals(
        self, fund: Dict[str, Any]
    ) -> tuple:
        """
        Score fundamentals 0-100.  Each metric contributes to a raw tally
        that is then normalised to 0-100 and graded A-F.
        """
        raw = 0
        max_raw = 0
        signals: List[str] = []

        # P/E ratio (lower is generally better for value)
        pe = fund.get("pe_ratio")
        if pe is not None:
            max_raw += 2
            try:
                pe = float(pe)
                if pe <= 0:
                    raw -= 1
                    signals.append("Negative P/E — company is unprofitable (bearish)")
                elif pe < 15:
                    raw += 2
                    signals.append(f"P/E {pe:.1f} — value territory (bullish)")
                elif pe < 25:
                    raw += 1
                    signals.append(f"P/E {pe:.1f} — fairly valued (neutral)")
                elif pe < 40:
                    raw += 0
                    signals.append(f"P/E {pe:.1f} — elevated valuation (caution)")
                else:
                    raw -= 1
                    signals.append(f"P/E {pe:.1f} — very expensive (bearish)")
            except (TypeError, ValueError):
                pass

        # Revenue growth YoY
        rev_growth = fund.get("revenue_growth_yoy")
        if rev_growth is not None:
            max_raw += 2
            try:
                rg = float(rev_growth)
                if rg > 0.20:
                    raw += 2
                    signals.append(f"Revenue growth {rg*100:.0f}% — strong growth (bullish)")
                elif rg > 0.10:
                    raw += 1
                    signals.append(f"Revenue growth {rg*100:.0f}% — solid growth (bullish)")
                elif rg >= 0:
                    raw += 0
                    signals.append(f"Revenue growth {rg*100:.0f}% — slow growth (neutral)")
                else:
                    raw -= 2
                    signals.append(f"Revenue declining {rg*100:.0f}% (bearish)")
            except (TypeError, ValueError):
                pass

        # Return on Equity
        roe = fund.get("roe")
        if roe is not None:
            max_raw += 2
            try:
                r = float(roe)
                if r > 0.20:
                    raw += 2
                    signals.append(f"ROE {r*100:.0f}% — excellent returns (bullish)")
                elif r > 0.15:
                    raw += 1
                    signals.append(f"ROE {r*100:.0f}% — good returns (bullish)")
                elif r > 0.10:
                    raw += 0
                    signals.append(f"ROE {r*100:.0f}% — average returns (neutral)")
                else:
                    raw -= 1
                    signals.append(f"ROE {r*100:.0f}% — weak returns (bearish)")
            except (TypeError, ValueError):
                pass

        # Debt/Equity
        de = fund.get("debt_to_equity")
        if de is not None:
            max_raw += 2
            try:
                d = float(de)
                if d < 0.5:
                    raw += 2
                    signals.append(f"D/E {d:.2f} — low debt (bullish)")
                elif d < 1.0:
                    raw += 1
                    signals.append(f"D/E {d:.2f} — manageable debt (neutral)")
                elif d < 2.0:
                    raw -= 1
                    signals.append(f"D/E {d:.2f} — elevated debt (caution)")
                else:
                    raw -= 2
                    signals.append(f"D/E {d:.2f} — high leverage (bearish)")
            except (TypeError, ValueError):
                pass

        # Profit margin
        margin = fund.get("profit_margin")
        if margin is not None:
            max_raw += 2
            try:
                m = float(margin)
                if m > 0.20:
                    raw += 2
                    signals.append(f"Net margin {m*100:.0f}% — highly profitable (bullish)")
                elif m > 0.10:
                    raw += 1
                    signals.append(f"Net margin {m*100:.0f}% — healthy margins (bullish)")
                elif m > 0.05:
                    raw += 0
                    signals.append(f"Net margin {m*100:.0f}% — thin margins (neutral)")
                else:
                    raw -= 1
                    signals.append(f"Net margin {m*100:.0f}% — poor margins (bearish)")
            except (TypeError, ValueError):
                pass

        if max_raw == 0:
            return None, None, []

        # Normalise to 0-100
        score = int(((raw + max_raw) / (2 * max_raw)) * 100)
        score = max(0, min(100, score))

        if score >= 80:
            grade = "A"
        elif score >= 65:
            grade = "B"
        elif score >= 50:
            grade = "C"
        elif score >= 35:
            grade = "D"
        else:
            grade = "F"

        return score, grade, signals[:5]  # cap at 5 signals
