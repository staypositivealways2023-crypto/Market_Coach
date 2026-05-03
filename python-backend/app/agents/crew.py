"""
MarketCoach CrewAI Agent Swarm — Phase 3 (Hedge Fund Analyst Brain)

Six specialist agents collaborate to produce institutional-grade analysis:

  MarketDataAgent    → Fetches price, indicators, chart patterns
  SentimentAgent     → FinBERT news scoring + macro risk
  FundamentalsAgent  → DCF valuation, quality scoring (DeepSeek-R1)
  TechnicalAgent     → Signal confluence, support/resistance
  RiskAgent          → ATR position sizing, stop-loss, risk/reward
  CoachAgent         → Personalised Bull/Base/Bear coaching (Claude)

Sequential process. Each agent's output is passed as context to the next.
The final CoachAgent output IS the API response.

LLMs:
  Mistral 7B (Ollama)     — MarketData, Sentiment, Technical, Risk  [cost-efficient]
  DeepSeek-R1 14B (Ollama) — Fundamentals  [chain-of-thought valuation reasoning]
  Claude Sonnet (Anthropic) — Coach  [highest-quality personalised synthesis]

Usage:
    result = await run_crew(symbol="NVDA", uid="user_123", user_level="intermediate")
    # result is a dict with scenario_card + coaching note
"""

import asyncio
import logging
import os
from typing import Optional

logger = logging.getLogger(__name__)

# ── Module-level UID context (set before crew.kickoff so tools can read it) ──
_CURRENT_UID: Optional[str] = None


def _build_crew(symbol: str, uid: str, user_level: str):
    """
    Construct and return a CrewAI Crew for a single analysis run.
    Importing crewai inside the function keeps startup fast when crewai
    is not yet installed (graceful fallback).
    """
    from crewai import Agent, Task, Crew, Process
    from app.agents.tools import (
        get_market_data,
        detect_chart_patterns,
        get_news_sentiment,
        get_finbert_sentiment,
        get_macro_context,
        get_fundamentals,
        get_deep_fundamentals,
        calculate_risk_metrics,
        recall_user_context,
    )

    # ── LLM config ──────────────────────────────────────────────────────────
    # Coach   → Claude Sonnet (quality synthesis, personalisation)
    # Fundamentals → DeepSeek-R1 (chain-of-thought valuation reasoning)
    # All other agents → Ollama Mistral 7B (cost-efficient)

    ollama_base    = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
    claude_key     = os.getenv("ANTHROPIC_API_KEY", "")
    deepseek_model = os.getenv("ANALYST_DEEPSEEK_MODEL", "deepseek-r1:14b")

    try:
        from crewai import LLM
        ollama_llm   = LLM(model="ollama/mistral",             base_url=ollama_base)
        deepseek_llm = LLM(model=f"ollama/{deepseek_model}",  base_url=ollama_base,
                           temperature=0.3, max_tokens=2000)
        claude_llm   = LLM(model="claude-sonnet-4-6",          api_key=claude_key)
    except Exception:
        # crewai LLM class not available — use string shorthand
        ollama_llm   = "ollama/mistral"
        deepseek_llm = f"ollama/{deepseek_model}"
        claude_llm   = "anthropic/claude-sonnet-4-6"

    # ── Agents ──────────────────────────────────────────────────────────────

    market_data_agent = Agent(
        role="Market Data Analyst",
        goal=(
            f"Gather and pre-process all real-time and historical data for {symbol}. "
            "Produce a clean data packet: price, volume, ATR, RSI, MACD, EMA stack, "
            "and any chart patterns. Be factual and precise — no opinions."
        ),
        backstory=(
            "You are a quant data specialist. Your job is to collect raw numbers "
            "accurately and present them in a structured format for the rest of the team."
        ),
        tools=[get_market_data, detect_chart_patterns, get_fundamentals],
        llm=ollama_llm,
        verbose=False,
        allow_delegation=False,
    )

    sentiment_agent = Agent(
        role="Sentiment & Macro Specialist",
        goal=(
            f"Analyse market sentiment for {symbol} from news, macro conditions, "
            "and the overall risk environment. Use FinBERT for precise article-level "
            "scoring. Score retail sentiment and macro risk. "
            "Identify any high-impact upcoming events."
        ),
        backstory=(
            "You are a market intelligence analyst who reads the news, FRED data, "
            "and macro indicators. You use NLP-based sentiment tools to distil "
            "noise into clear risk signals."
        ),
        tools=[get_finbert_sentiment, get_news_sentiment, get_macro_context],
        llm=ollama_llm,
        verbose=False,
        allow_delegation=False,
    )

    fundamentals_agent = Agent(
        role="Fundamental Value Analyst",
        goal=(
            f"Perform deep fundamental value analysis on {symbol}. "
            "Calculate DCF intrinsic value, WACC, and margin of safety. "
            "Score earnings quality (0-100) from profit margin, ROE, debt levels, "
            "and revenue/EPS growth. Deliver a clear valuation verdict: "
            "UNDERVALUED / FAIRLY_VALUED / OVERVALUED with supporting rationale. "
            "Think step-by-step through the numbers before concluding."
        ),
        backstory=(
            "You are a hedge-fund equity analyst trained in Warren Buffett-style "
            "value investing. You build DCF models, stress-test growth assumptions, "
            "and assess business quality before ever looking at a chart. "
            "Your reasoning is meticulous and you always show your work."
        ),
        tools=[get_deep_fundamentals],
        llm=deepseek_llm,
        verbose=False,
        allow_delegation=False,
    )

    technical_agent = Agent(
        role="Technical Analyst",
        goal=(
            f"Interpret the market data and sentiment for {symbol}. "
            "Identify key support/resistance levels, trend direction, and the strongest "
            "signal confluence. Assign a composite signal: STRONG_BUY / BUY / NEUTRAL / "
            "SELL / STRONG_SELL with a confidence score."
        ),
        backstory=(
            "You are a chart-reading expert with 20 years of technical analysis experience. "
            "You synthesise indicator data into clear directional calls."
        ),
        tools=[],
        llm=ollama_llm,
        verbose=False,
        allow_delegation=False,
    )

    risk_agent = Agent(
        role="Quantitative Risk Manager",
        goal=(
            f"Quantify the risk/reward profile for a trade on {symbol}. "
            "Use ATR-based stop-loss and take-profit levels, compute the "
            "risk/reward ratio, and recommend a position size as a percentage "
            "of portfolio using the 2%-per-trade risk rule. "
            "Classify overall risk as low / medium / high / very_high."
        ),
        backstory=(
            "You are a quant risk manager from a prop trading desk. "
            "You live by position sizing discipline and never let a single trade "
            "exceed 2% of account risk. You express everything in numbers."
        ),
        tools=[calculate_risk_metrics],
        llm=ollama_llm,
        verbose=False,
        allow_delegation=False,
    )

    coach_agent = Agent(
        role="Personal Trading Coach",
        goal=(
            f"Using all analysis above, create a personalised coaching output for a "
            f"{user_level}-level trader asking about {symbol}. "
            "Include: Bull/Base/Bear scenario probabilities, risk parameters from the "
            "RiskAgent, fundamental verdict from the FundamentalsAgent, "
            "and a coaching note that references their learning history. "
            "Be direct, educational, and empathetic. Keep it under 300 words."
        ),
        backstory=(
            "You are Dean — a world-class trading coach who combines technical expertise "
            "with behavioural finance psychology. You know what this user has been studying "
            "and you tailor your coaching to fill their knowledge gaps."
        ),
        tools=[recall_user_context],
        llm=claude_llm,
        verbose=False,
        allow_delegation=False,
    )

    # ── Tasks (sequential order matters) ────────────────────────────────────
    # 1. task_data         — collect all market data
    # 2. task_sentiment    — FinBERT + macro analysis
    # 3. task_fundamentals — DCF + quality scoring (DeepSeek-R1)
    # 4. task_technical    — signal confluence + support/resistance
    # 5. task_risk         — ATR stop-loss, sizing (references task_technical + task_fundamentals)
    # 6. task_coach        — full synthesis (context = all 5 prior tasks)

    task_data = Task(
        description=(
            f"1. Use get_market_data('{symbol}') to fetch price + indicators.\n"
            f"2. Use detect_chart_patterns('{symbol}') to identify patterns.\n"
            f"3. Use get_fundamentals('{symbol}') for valuation metrics.\n"
            "4. Summarise: current price, RSI value & zone, MACD direction, "
            "EMA stack stance, ATR (volatility), top detected pattern (if any), "
            "and P/E + revenue growth (stocks only).\n"
            "Output as a structured bullet list."
        ),
        agent=market_data_agent,
        expected_output=(
            "Structured data summary: price, change%, RSI, MACD, EMA stance, "
            "ATR, detected pattern, and fundamentals."
        ),
    )

    task_sentiment = Task(
        description=(
            f"1. Use get_finbert_sentiment('{symbol}') for FinBERT-scored article analysis.\n"
            f"2. Use get_news_sentiment('{symbol}') for the headline overview.\n"
            "3. Use get_macro_context('US') for the macro environment.\n"
            "4. Summarise: FinBERT sentiment distribution (positive/negative/neutral counts), "
            "average score, momentum direction (improving/stable/worsening), "
            "top 3 headline themes, macro risk level (low/medium/high), "
            "and any key upcoming events.\n"
            "Output as a structured bullet list."
        ),
        agent=sentiment_agent,
        expected_output=(
            "Sentiment summary: FinBERT distribution, average score, momentum, "
            "top headlines, macro risk, upcoming events."
        ),
        context=[task_data],
    )

    task_fundamentals = Task(
        description=(
            f"1. Use get_deep_fundamentals('{symbol}') to retrieve DCF, WACC, "
            "margin of safety, quality score, and all key ratios.\n"
            "2. Reason step-by-step:\n"
            "   a. Is the stock trading above or below its DCF fair value?\n"
            "   b. What does the quality score tell you about business health?\n"
            "   c. Are debt levels and margins sustainable?\n"
            "   d. What is the earnings growth trajectory?\n"
            "3. Deliver a valuation verdict: UNDERVALUED / FAIRLY_VALUED / OVERVALUED\n"
            "4. State the DCF fair value, margin of safety %, and quality label.\n"
            "Output as structured JSON."
        ),
        agent=fundamentals_agent,
        expected_output=(
            "JSON with: dcf_fair_value, margin_of_safety_pct, quality_score, "
            "quality_label, valuation_verdict, key_ratios, reasoning_summary."
        ),
        context=[task_data],
    )

    task_technical = Task(
        description=(
            "Based on the data and sentiment provided by the previous agents, "
            "produce a technical interpretation for the symbol:\n"
            "- Trend direction (uptrend/downtrend/sideways)\n"
            "- Key support level (nearest price)\n"
            "- Key resistance level (nearest price)\n"
            "- Composite signal: STRONG_BUY / BUY / NEUTRAL / SELL / STRONG_SELL\n"
            "- Signal confidence: 0-100\n"
            "- One-line technical rationale\n"
            "Output as a structured JSON block."
        ),
        agent=technical_agent,
        expected_output=(
            "JSON with: trend, support, resistance, composite_signal, confidence, rationale."
        ),
        context=[task_data, task_sentiment],
    )

    task_risk = Task(
        description=(
            f"1. Use calculate_risk_metrics('{symbol}') to fetch ATR, price levels, "
            "and signal score.\n"
            "2. From the results, report:\n"
            "   - Stop-loss price (1.5x ATR below entry)\n"
            "   - Take-profit price (2.5x ATR above entry)\n"
            "   - Risk/reward ratio\n"
            "   - Suggested position size % (2%-per-trade rule)\n"
            "   - Overall risk level (low / medium / high / very_high)\n"
            "3. Report tail-risk metrics from the tool output:\n"
            "   - VaR 95% (1-day % loss at 95th percentile)\n"
            "   - CVaR 95% (expected loss beyond VaR)\n"
            "   - Max drawdown over 1 year\n"
            "   - Whether the asset is black_swan_prone (excess kurtosis > 3)\n"
            "4. Cross-reference the fundamental valuation from the FundamentalsAgent: "
            "if the stock is OVERVALUED, reduce position size recommendation by 50% "
            "and note this adjustment in risk_rationale.\n"
            "Output as structured JSON."
        ),
        agent=risk_agent,
        expected_output=(
            "JSON with: stop_loss, take_profit, risk_reward_ratio, "
            "position_size_pct, risk_level, atr_pct, risk_rationale, "
            "var_95, cvar_95, max_drawdown_1yr, black_swan_prone."
        ),
        context=[task_data, task_technical, task_fundamentals],
    )

    task_coach = Task(
        description=(
            f"You have the full hedge-fund analysis above. Create a personalised coaching response:\n\n"
            f"1. Use recall_user_context('symbols watched risk tolerance learning progress') "
            f"to personalise for uid={uid}.\n"
            "2. Build a Scenario Card using the technical signal, fundamental verdict, "
            "and risk metrics:\n"
            "   Bull: probability (0-100), price_target, one-sentence thesis\n"
            "   Base: probability (0-100), price_target, one-sentence thesis\n"
            "   Bear: probability (0-100), price_target, one-sentence thesis\n"
            "   (probabilities must sum to 100)\n"
            "3. Use the RiskAgent's stop_loss, take_profit, and position_size_pct "
            "as the risk parameters in your response.\n"
            "4. Use the FundamentalsAgent's valuation_verdict to anchor the Base "
            "scenario price target.\n"
            "5. Assign risk_level from the RiskAgent output (do not re-calculate).\n"
            "5b. If risk output shows black_swan_prone=true, add a one-line tail-risk warning "
            "in the narrative (e.g. 'Note: this asset has fat-tailed return distribution — "
            "size positions conservatively').\n"
            f"6. Write a coaching_note for a {user_level} trader (max 2 sentences, "
            "reference their learning history if available).\n"
            "7. Provide a plain-English narrative (max 150 words) that integrates "
            "technicals, fundamentals, sentiment, and risk.\n\n"
            "Output as valid JSON with keys: scenarios, risk_level, composite_signal, "
            "fundamentals_verdict, stop_loss, take_profit, position_size_pct, "
            "coaching_note, narrative."
        ),
        agent=coach_agent,
        expected_output=(
            "JSON with: scenarios (bull/base/bear), risk_level, composite_signal, "
            "fundamentals_verdict, stop_loss, take_profit, position_size_pct, "
            "coaching_note, narrative."
        ),
        context=[task_data, task_sentiment, task_fundamentals, task_technical, task_risk],
    )

    crew = Crew(
        agents=[
            market_data_agent,
            sentiment_agent,
            fundamentals_agent,
            technical_agent,
            risk_agent,
            coach_agent,
        ],
        tasks=[
            task_data,
            task_sentiment,
            task_fundamentals,
            task_technical,
            task_risk,
            task_coach,
        ],
        process=Process.sequential,
        verbose=False,
    )

    return crew


# ── Public API ────────────────────────────────────────────────────────────────

def _store_crew_memory(uid: str, symbol: str, result: dict) -> None:
    """
    Persist a crew analysis run to ChromaDB as trade_history and
    watchlist_patterns entries.  Called synchronously inside run_crew()
    after a successful parse — failures are swallowed so they never
    block the caller.
    """
    if uid == "anonymous" or not symbol:
        return
    try:
        from app.services.chroma_memory_service import ChromaMemoryService
        chroma = ChromaMemoryService()

        # ── trade_history: narrative summary of what the crew found ─────────
        narrative = result.get("narrative") or ""
        composite = result.get("composite_signal") or ""
        verdict   = result.get("fundamentals_verdict") or ""

        # Build a concise one-sentence summary for this analysis run
        parts = [f"Analysed {symbol}"]
        if composite:
            parts.append(f"signal={composite}")
        if verdict:
            parts.append(f"fundamentals={verdict}")
        if narrative:
            # Trim to first 200 chars to keep the memory snippet readable
            parts.append(narrative[:200].replace("\n", " ").strip())

        trade_text = "; ".join(parts)
        chroma.store(uid, trade_text, category="trade_history", symbol=symbol)

        # ── watchlist_patterns: lightweight "user looked at this symbol" ────
        chroma.store(
            uid,
            f"Ran full crew analysis on {symbol}",
            category="watchlist_patterns",
            symbol=symbol,
        )

        logger.debug(f"[crew] memory stored for {uid} / {symbol}")
    except Exception as exc:
        logger.warning(f"[crew] _store_crew_memory failed for {uid}/{symbol}: {exc}")


async def run_crew(
    symbol: str,
    uid: str = "anonymous",
    user_level: str = "beginner",
) -> dict:
    """
    Run the full 6-agent crew for a symbol and return a structured result dict.

    Falls back gracefully to an empty result if CrewAI is not installed or
    any agent throws an exception — the caller can then fall back to the
    existing single-Claude analyse endpoint.
    """
    global _CURRENT_UID
    _CURRENT_UID = uid

    try:
        crew   = _build_crew(symbol=symbol, uid=uid, user_level=user_level)
        # CrewAI kickoff is blocking — run in executor to avoid blocking the event loop
        loop   = asyncio.get_event_loop()
        result = await loop.run_in_executor(None, crew.kickoff)

        raw = str(result)

        # Try to extract JSON from the output
        import re
        import json
        match = re.search(r'\{.*\}', raw, re.DOTALL)
        if match:
            try:
                parsed = json.loads(match.group(0))
                _store_crew_memory(uid, symbol, parsed)
                return parsed
            except json.JSONDecodeError:
                pass

        fallback = {"narrative": raw, "crew_raw": True}
        _store_crew_memory(uid, symbol, fallback)
        return fallback

    except ImportError:
        logger.warning("[crew] crewai not installed — returning empty result")
        return {}
    except Exception as e:
        logger.error(f"[crew] run failed for {symbol}: {e}", exc_info=True)
        return {"error": str(e)}
