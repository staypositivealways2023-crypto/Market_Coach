"""
MarketCoach CrewAI Agent Swarm — Phase 9

Four specialist agents that collaborate to produce a rich Scenario Card:

  MarketDataAgent   → Fetches price, indicators, patterns
  SentimentAgent    → Scores news + macro risk
  TechnicalAgent    → Interprets signals, identifies key levels
  CoachAgent        → Synthesises into personalised coaching output

The crew runs sequentially. Each agent's output is passed as context to
the next.  The final CoachAgent output IS the API response.

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
        get_macro_context,
        get_fundamentals,
        recall_user_context,
    )

    # ── LLM config ──────────────────────────────────────────────────────────
    # Use Anthropic Claude for the Coach (quality matters).
    # Use Ollama mistral:7b for the data-heavy agents to save cost.
    # Falls back to Claude if Ollama is not running.

    ollama_base  = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
    claude_key   = os.getenv("ANTHROPIC_API_KEY", "")

    try:
        from crewai import LLM
        ollama_llm = LLM(model="ollama/mistral", base_url=ollama_base)
        claude_llm = LLM(
            model="claude-sonnet-4-5",
            api_key=claude_key,
        )
    except Exception:
        # crewai LLM class not available — use string shorthand
        ollama_llm = "ollama/mistral"
        claude_llm = f"anthropic/claude-sonnet-4-5"

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
            "and the overall risk environment. Score retail sentiment and macro risk. "
            "Identify any high-impact upcoming events."
        ),
        backstory=(
            "You are a market intelligence analyst who reads the news, FRED data, "
            "and macro indicators. You distil noise into clear risk signals."
        ),
        tools=[get_news_sentiment, get_macro_context],
        llm=ollama_llm,
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

    coach_agent = Agent(
        role="Personal Trading Coach",
        goal=(
            f"Using all analysis above, create a personalised coaching output for a "
            f"{user_level}-level trader asking about {symbol}. "
            "Include: Bull/Base/Bear scenario probabilities, a 1-sentence thesis for each, "
            "risk level, and a coaching note that references their learning history. "
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

    # ── Tasks ────────────────────────────────────────────────────────────────

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
            f"1. Use get_news_sentiment('{symbol}') to score recent news.\n"
            "2. Use get_macro_context('US') for the macro environment.\n"
            "3. Summarise: news sentiment label + score, top 3 headline themes, "
            "macro risk level (low/medium/high), and any key upcoming events.\n"
            "Output as a structured bullet list."
        ),
        agent=sentiment_agent,
        expected_output=(
            "Sentiment summary: overall label, score, top headlines, macro risk, "
            "upcoming events."
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
            "- Signal confidence: 0–100\n"
            "- One-line technical rationale\n"
            "Output as a structured JSON block."
        ),
        agent=technical_agent,
        expected_output=(
            "JSON with: trend, support, resistance, composite_signal, confidence, rationale."
        ),
        context=[task_data, task_sentiment],
    )

    task_coach = Task(
        description=(
            f"Using all previous analysis, create a complete coaching response:\n\n"
            f"1. Use recall_user_context('symbols watched risk tolerance learning progress') "
            f"to personalise your response for uid={uid}.\n"
            "2. Build a Scenario Card:\n"
            "   Bull: probability (0-100), price_target, one-sentence thesis\n"
            "   Base: probability (0-100), price_target, one-sentence thesis\n"
            "   Bear: probability (0-100), price_target, one-sentence thesis\n"
            "   (probabilities must sum to 100)\n"
            "3. Assign risk_level: low / medium / high / very_high\n"
            f"4. Write a coaching_note for a {user_level} trader (max 2 sentences, "
            "reference their learning history if available).\n"
            "5. Provide a plain-English narrative (max 150 words).\n\n"
            "Output as valid JSON with keys: scenarios, risk_level, "
            "composite_signal, coaching_note, narrative."
        ),
        agent=coach_agent,
        expected_output=(
            "JSON with: scenarios (bull/base/bear), risk_level, composite_signal, "
            "coaching_note, narrative."
        ),
        context=[task_data, task_sentiment, task_technical],
    )

    crew = Crew(
        agents=[market_data_agent, sentiment_agent, technical_agent, coach_agent],
        tasks=[task_data, task_sentiment, task_technical, task_coach],
        process=Process.sequential,
        verbose=False,
    )

    return crew


# ── Public API ────────────────────────────────────────────────────────────────

async def run_crew(
    symbol: str,
    uid: str = "anonymous",
    user_level: str = "beginner",
) -> dict:
    """
    Run the full 4-agent crew for a symbol and return a structured result dict.

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
                return json.loads(match.group(0))
            except json.JSONDecodeError:
                pass

        return {"narrative": raw, "crew_raw": True}

    except ImportError:
        logger.warning("[crew] crewai not installed — returning empty result")
        return {}
    except Exception as e:
        logger.error(f"[crew] run failed for {symbol}: {e}", exc_info=True)
        return {"error": str(e)}
