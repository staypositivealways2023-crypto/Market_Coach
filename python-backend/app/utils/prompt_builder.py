"""Prompt Builder - Construct Claude API prompts for market analysis"""

from typing import Dict, Any
from datetime import date


class PromptBuilder:
    """Builds prompts for Claude AI market analysis"""

    @staticmethod
    def build_system_prompt() -> str:
        """
        Build system prompt defining Claude's persona as a financial coach

        Returns:
            System prompt string
        """

        today = date.today().strftime("%B %d, %Y")
        return f"""Today's date is {today}.

You are a financial coach for MarketCoach, an educational investment app. Your role is to analyze market data and explain it in a coaching, educational tone.

**Key Guidelines:**
- Use a friendly, coaching tone - like a mentor teaching a student
- Explain WHY indicators matter, not just what they show
- Use analogies and simple language to explain complex concepts
- Reference educational lessons when relevant (e.g., "Learn more in our 'RSI Basics' lesson")
- NEVER give direct buy/sell advice - use phrases like "suggests" or "indicates"
- Highlight when signals conflict - this teaches critical thinking
- Focus on what the data teaches, not what to do
- Keep responses concise but insightful

**Output Format:**
Structure your analysis in markdown with these sections:

## Market Context
Brief overview of current price action and what's happening

## Technical Analysis
Explain technical indicators and what they suggest (RSI, MACD, Bollinger Bands, moving averages)

## Fundamental Perspective
Discuss valuation metrics if available (P/E, DCF, growth, profitability)
For crypto, acknowledge that fundamentals don't apply

## Key Considerations
Highlight conflicting signals, risks, or important context

## Learning Opportunities
Suggest concepts the user should study based on this analysis

**Tone Examples:**
- Good: "The RSI at 72 suggests the stock is overbought - like a rubber band stretched too far"
- Bad: "RSI is overbought. Sell now."
- Good: "Notice how price is above all moving averages - this indicates strong momentum"
- Bad: "Buy because price > SMA"
"""

    @staticmethod
    def build_user_prompt(context: Dict[str, Any]) -> str:
        """
        Build user prompt from aggregated market data

        Args:
            context: Dict containing quote, technical, valuation, and info data

        Returns:
            Formatted user prompt string
        """

        symbol = context.get("symbol", "Unknown")
        quote = context.get("quote", {})
        technical = context.get("technical", {})
        valuation_dcf = context.get("valuation_dcf")
        valuation_metrics = context.get("valuation_metrics")
        info = context.get("info")

        # Build prompt sections
        sections = []

        # Header
        sections.append(f"Analyze {symbol} based on the following market data:\n")

        # 1. Current Price & Quote
        if quote:
            price = quote.get("price", 0)
            change = quote.get("change", 0)
            change_pct = quote.get("change_percent", 0)

            sections.append(f"**Current Price:** ${price:.2f}")

            change_sign = "+" if change >= 0 else ""
            sections.append(f"**Today's Change:** {change_sign}${change:.2f} ({change_sign}{change_pct:.2f}%)")

            if quote.get("high") and quote.get("low"):
                sections.append(f"**Day Range:** ${quote['low']:.2f} - ${quote['high']:.2f}")

            if quote.get("volume"):
                sections.append(f"**Volume:** {quote['volume']:,.0f}")

        sections.append("")  # Blank line

        # 2. Technical Indicators
        if technical:
            sections.append("**Technical Indicators:**")

            # RSI
            rsi = technical.get("rsi")
            if rsi and rsi.get("value"):
                sections.append(f"- RSI: {rsi['value']:.1f} ({rsi.get('signal', 'neutral')})")

            # MACD
            macd = technical.get("macd")
            if macd and macd.get("macd") is not None:
                sections.append(
                    f"- MACD: {macd['macd']:.4f}, "
                    f"Signal: {macd['signal']:.4f}, "
                    f"Histogram: {macd['histogram']:.4f} ({macd.get('trend', 'neutral')})"
                )

            # Bollinger Bands
            bb = technical.get("bollinger_bands")
            if bb and bb.get("upper"):
                percent_b = bb.get("percent_b", 0.5)
                position = "near upper band" if percent_b > 0.8 else "near lower band" if percent_b < 0.2 else "middle of bands"
                sections.append(
                    f"- Bollinger Bands: ${bb['lower']:.2f} - ${bb['middle']:.2f} - ${bb['upper']:.2f} "
                    f"(price {position}, %B: {percent_b:.2f})"
                )

            # Moving Averages
            ma = technical.get("moving_averages", {})
            if ma.get("sma_20") or ma.get("sma_50") or ma.get("sma_200"):
                ma_values = []
                if ma.get("sma_20"):
                    ma_values.append(f"SMA-20: ${ma['sma_20']:.2f}")
                if ma.get("sma_50"):
                    ma_values.append(f"SMA-50: ${ma['sma_50']:.2f}")
                if ma.get("sma_200"):
                    ma_values.append(f"SMA-200: ${ma['sma_200']:.2f}")

                sections.append(f"- Moving Averages: {', '.join(ma_values)}")

                # Trend context
                above_count = sum([
                    1 for k in ['above_sma_20', 'above_sma_50', 'above_sma_200']
                    if ma.get(k) is True
                ])
                if above_count == 3:
                    sections.append("  (Price above all MAs - strong uptrend)")
                elif above_count == 0:
                    sections.append("  (Price below all MAs - strong downtrend)")

        sections.append("")  # Blank line

        # 3. Fundamental Metrics (if available)
        if valuation_metrics or valuation_dcf:
            sections.append("**Fundamental Metrics:**")

            if valuation_dcf:
                intrinsic = valuation_dcf.get("intrinsic_value")
                current = valuation_dcf.get("current_price")
                upside = valuation_dcf.get("upside_percent")
                signal = valuation_dcf.get("signal")

                sections.append(
                    f"- DCF Intrinsic Value: ${intrinsic:.2f} "
                    f"(current: ${current:.2f}, upside: {upside:+.1f}%, {signal})"
                )

            if valuation_metrics:
                vm = valuation_metrics

                if vm.get("pe_ratio"):
                    sections.append(f"- P/E Ratio: {vm['pe_ratio']:.2f}")

                if vm.get("peg_ratio"):
                    sections.append(f"- PEG Ratio: {vm['peg_ratio']:.2f}")

                if vm.get("roe"):
                    sections.append(f"- ROE: {vm['roe']*100:.1f}%")

                if vm.get("profit_margin"):
                    sections.append(f"- Profit Margin: {vm['profit_margin']*100:.1f}%")

                if vm.get("debt_to_equity"):
                    sections.append(f"- Debt/Equity: {vm['debt_to_equity']:.2f}")

                if vm.get("revenue_growth"):
                    sections.append(f"- Revenue Growth: {vm['revenue_growth']*100:+.1f}%")

                if vm.get("grade"):
                    sections.append(f"- Value Grade: {vm['grade']} (score: {vm.get('value_score', 0):.0f}/100)")

        sections.append("")  # Blank line

        # 4. Company Info
        if info:
            sections.append("**Company Info:**")
            if info.get("name"):
                sections.append(f"- Name: {info['name']}")
            if info.get("sector"):
                sections.append(f"- Sector: {info['sector']}")
            if info.get("industry"):
                sections.append(f"- Industry: {info['industry']}")

        sections.append("")  # Blank line

        # Instructions
        sections.append(
            "Provide a coaching-style analysis explaining what this data suggests. "
            "Focus on education, highlight conflicting signals if any, and suggest learning opportunities. "
            "Remember: no buy/sell advice, just insightful explanation."
        )

        return "\n".join(sections)

    # ── Phase 3: Signal Engine prompts (§6.1 + §6.2 from architecture doc) ───

    @staticmethod
    def build_analyse_system_prompt() -> str:
        """
        System prompt for the /api/analyse endpoint.
        Defines the Market Coach AI persona per §6.1.
        Keep under 800 tokens — Anthropic caches repeated system prompts.
        """
        today = date.today().strftime("%B %d, %Y")
        return f"""Today's date is {today}.

You are Market Coach AI — a professional financial analyst and educator. You speak clearly, confidently, and in plain English.

Your role:
- Explain technical signals in terms a beginner can understand
- Validate or challenge the algorithmic signals with nuance
- Connect news events to price action when relevant
- Always state confidence levels and acknowledge uncertainty
- Never make guarantees. Frame everything as probabilities.

Output format (always use this exact structure):
1. ONE sentence summary of the current situation
2. What the chart/pattern is showing (technical signals)
3. What news or fundamentals add (only if material)
4. The signal verdict with brief reasoning
5. One actionable learning point for the user

Rules:
- Keep responses under 200 words unless detail is explicitly requested
- Never repeat the raw numbers — interpret them
- No direct buy/sell advice — use "suggests", "indicates", "may signal"
- If signals conflict, say so — conflicting signals are valuable learning moments
- Adjust depth for the user level passed in the request

After your main analysis, you MUST end with exactly these three lines (no extra text after them):
BULL_THESIS: <one sentence — bull case driver>
BASE_THESIS: <one sentence — base case driver>
BEAR_THESIS: <one sentence — bear case driver>"""

    @staticmethod
    def build_analyse_user_prompt(
        symbol: str,
        interval: str,
        quote: dict,
        signals,              # ComputedSignals instance
        news: list,
        fundamentals,         # dict or None
        user_level: str = "beginner",
        prediction=None,      # Optional[PredictionResult]
        correlation=None,     # Optional[CorrelationResult]
        patterns=None,        # Optional[PatternScanResult]
        macro_overview=None,  # Optional[dict] — FRED macro snapshot
    ) -> str:
        """
        User message for the /api/analyse endpoint.
        Pre-computed signals dict keeps this ~200-350 tokens per §6.2.
        """
        from app.models.signals import ComputedSignals

        lines = [f"Analyse {symbol} on the {interval} chart.\n"]

        # ── SIGNALS block ────────────────────────────────────────────────────
        lines.append("SIGNALS:")
        cs = signals.candlestick
        if cs.pattern:
            lines.append(
                f"- Candlestick: {cs.pattern} ({cs.signal}, {int(cs.confidence * 100)}% confidence)"
            )
        else:
            lines.append("- Candlestick: No clear pattern")

        ind = signals.indicators
        if ind.rsi_value is not None:
            lines.append(f"- RSI: {ind.rsi_value:.1f} ({ind.rsi_signal})")
        lines.append(f"- MACD: {ind.macd_signal}")
        lines.append(f"- EMA Stack: {ind.ema_stack}")
        lines.append(f"- Volume: {ind.volume}")
        lines.append(
            f"- Composite Score: {signals.composite_score:+.2f} → {signals.signal_label.value}"
        )

        # ── PRICE block ──────────────────────────────────────────────────────
        if quote:
            price = quote.get("price", 0)
            change_pct = quote.get("change_percent", 0)
            lines.append(f"\nPRICE: ${price:.2f} ({change_pct:+.2f}% today)")

        # ── FUNDAMENTALS block (stocks only) ─────────────────────────────────
        if fundamentals and not fundamentals.get("is_crypto"):
            ratios = fundamentals.get("ratios", {})
            ttm    = fundamentals.get("ttm", {})
            pe     = ratios.get("pe")
            gm     = ratios.get("gross_margin")
            nm     = ratios.get("net_margin")
            roe    = ratios.get("roe")
            de     = ratios.get("debt_equity")
            eps    = ttm.get("eps")
            if any(v is not None for v in [pe, gm, nm, roe, de, eps]):
                lines.append("\nFUNDAMENTALS:")
                if pe and pe > 0:
                    lines.append(f"- P/E: {pe:.1f}")
                if gm is not None:
                    lines.append(f"- Gross Margin: {gm:.1f}%")
                if nm is not None:
                    lines.append(f"- Net Margin: {nm:.1f}%")
                if roe is not None:
                    lines.append(f"- ROE: {roe:.1f}%")
                if de is not None:
                    lines.append(f"- Debt/Equity: {de:.2f}")
                if eps is not None:
                    lines.append(f"- EPS (TTM): ${eps:.2f}")

        # ── PREDICTION MODEL OUTPUT block (§6.2) ────────────────────────────
        if prediction:
            p = prediction
            lines.append("\nPREDICTION MODEL OUTPUT:")
            lines.append(f"- Direction: {p.direction} ({int(p.probability * 100)}% confidence)")
            lines.append(f"- Price Now: ${p.price_current:.2f}")
            lines.append(
                f"- Target Range: ${p.price_target_low:.2f} — ${p.price_target_base:.2f} — ${p.price_target_high:.2f}"
            )
            lines.append(f"- Expected Return: {p.expected_return_pct:+.1f}%")
            lines.append(f"- Risk/Reward: {p.risk_reward_ratio:.1f}")
            lines.append(f"- Stop Loss: ${p.stop_loss_suggestion:.2f}")
            lines.append(f"- Horizon: {p.horizon}")
            lines.append(f"- Consensus: {p.model_consensus}")

        # ── NEWS SENTIMENT block ─────────────────────────────────────────────
        if news:
            scores = [a.get("sentiment_score", 0) for a in news if "sentiment_score" in a]
            avg_sentiment = sum(scores) / len(scores) if scores else 0
            label = "positive" if avg_sentiment > 0.05 else "negative" if avg_sentiment < -0.05 else "neutral"
            lines.append(f"\nNEWS SENTIMENT: {avg_sentiment:+.2f} ({label})")
            top = [a.get("title") or a.get("headline", "") for a in news[:3] if a]
            for h in top:
                if h:
                    lines.append(f'- "{h[:90]}"')

        # ── CHART PATTERNS block (Phase 6) ───────────────────────────────────
        if patterns:
            lines.append(f"\nCHART PATTERNS ({patterns.trend}, {patterns.trend_strength}):")
            if patterns.patterns:
                for p in patterns.patterns:
                    lines.append(
                        f"- {p.type.replace('_', ' ')} [{p.signal}] "
                        f"{int(p.confidence * 100)}% confidence — {p.description}"
                    )
            else:
                lines.append("- No significant chart patterns detected")
            if patterns.support_resistance:
                sr_top = patterns.support_resistance[:3]
                sr_str = ", ".join(
                    f"${s.price:.2f} ({s.type}, {s.strength}x)" for s in sr_top
                )
                lines.append(f"- Key S/R levels: {sr_str}")

        # ── CORRELATION block (Phase 5) ───────────────────────────────────────
        if correlation:
            c = correlation
            lines.append(f"\nCORRELATION SCENARIO: {c.scenario_label}")
            lines.append(f"- Sentiment: {c.sentiment_label} ({c.news_sentiment_score:+.2f})")
            lines.append(f"- Price direction: {c.price_direction}")
            lines.append(f"- Interpretation: {c.scenario_description}")
            if c.high_impact_flags:
                lines.append(f"- High-impact events: {', '.join(c.high_impact_flags)}")
            if c.fundamental_score is not None:
                lines.append(
                    f"- Fundamental score: {c.fundamental_score}/100 "
                    f"(Grade {c.fundamental_grade})"
                )
                for sig in c.fundamental_signals[:3]:
                    lines.append(f"  • {sig}")

        # ── MACRO CONTEXT block (Phase A) ────────────────────────────────────
        if macro_overview and correlation and correlation.macro_flags:
            lines.append("\nMACRO CONTEXT:")
            for flag in correlation.macro_flags[:4]:
                lines.append(f"- {flag}")

        # ── USER LEVEL ────────────────────────────────────────────────────────
        lines.append(f"\nUser level: {user_level}")

        return "\n".join(lines)
