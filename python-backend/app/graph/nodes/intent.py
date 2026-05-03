"""
Phase 2 — Intent Classification node.
Uses Mistral 7B (via Ollama) with JSON mode to classify the user's financial
query into one of four intents and extract a ticker symbol.
"""

import json
import logging
import re

from app.graph.state import AnalystState
from app.config import settings

logger = logging.getLogger(__name__)

VALID_INTENTS = {"technical", "fundamental", "sentiment", "general"}

_SYSTEM_PROMPT = """You are a financial query classifier. Analyse the user query and return ONLY valid JSON — no extra text, no markdown fences.

Output format:
{"intent": "<intent>", "symbol": "<TICKER or null>", "confidence": <0.0-1.0>}

Intent definitions:
- technical    : chart patterns, RSI, MACD, Bollinger, price action, support/resistance, candlesticks, overbought/oversold
- fundamental  : earnings, P/E ratio, revenue, SEC filings, DCF valuation, balance sheet, dividends, EPS
- sentiment    : news sentiment, social media, Reddit, analyst ratings, market mood, fear/greed
- general      : portfolio advice, market overview, educational questions, how-to, definitions

Symbol rules:
- Return the uppercase ticker symbol if a specific asset is mentioned (e.g. AAPL, TSLA, BTC, ETH)
- Return null (JSON null, not the string "null") if no specific asset is mentioned
- For crypto, use the base ticker: BTC not BTCUSDT

Confidence rules:
- 0.9–1.0 : query is unambiguously one intent
- 0.6–0.9 : mostly clear but could overlap
- 0.3–0.6 : ambiguous, best guess applied
"""


def _clean_symbol(raw) -> str | None:
    """Normalise the model's symbol output into a clean ticker or None."""
    if raw is None:
        return None
    s = str(raw).strip().upper()
    if s in ("NULL", "NONE", "N/A", ""):
        return None
    # Strip non-alphanumeric except hyphen (preserves BTC-USD style)
    s = re.sub(r"[^A-Z0-9\-]", "", s)
    return s or None


def _parse_json(raw: str) -> dict:
    """
    Extract a JSON object from the model's output.
    Handles: plain JSON, markdown code fences, prefixed prose.
    """
    # Direct parse
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        pass

    # Strip markdown fences
    cleaned = re.sub(r"```(?:json)?", "", raw, flags=re.IGNORECASE).strip()
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        pass

    # Grab first {...} block
    m = re.search(r"\{.*\}", cleaned, re.DOTALL)
    if m:
        try:
            return json.loads(m.group())
        except json.JSONDecodeError:
            pass

    return {}


async def run(state: AnalystState) -> dict:
    """Classify user intent and extract ticker using Mistral 7B JSON mode."""
    from langchain_ollama import OllamaLLM

    llm = OllamaLLM(
        model=settings.ANALYST_INTENT_MODEL,   # "mistral"
        format="json",
        base_url=settings.OLLAMA_BASE_URL,
        temperature=0.1,                        # Low temp for deterministic classification
    )

    prompt = f"{_SYSTEM_PROMPT}\n\nUser query: {state['user_message']}"

    try:
        raw = await llm.ainvoke(prompt)
        logger.debug("[intent] raw output: %r", raw[:300])

        parsed = _parse_json(raw)

        # Validate and sanitise intent
        intent = parsed.get("intent", "general")
        if intent not in VALID_INTENTS:
            logger.warning("[intent] invalid intent %r — falling back to 'general'", intent)
            intent = "general"

        # Validate and sanitise symbol
        symbol = _clean_symbol(parsed.get("symbol"))

        # Clamp confidence to [0.0, 1.0]
        try:
            confidence = float(parsed.get("confidence", 0.5))
            confidence = max(0.0, min(1.0, confidence))
        except (TypeError, ValueError):
            confidence = 0.5

        logger.info(
            "[intent] intent=%s symbol=%s confidence=%.2f msg=%r",
            intent, symbol, confidence, state["user_message"][:60],
        )
        return {
            "intent": intent,
            "symbol": symbol,
            "intent_confidence": confidence,
        }

    except Exception as exc:
        logger.exception("[intent] Mistral call failed: %s", exc)
        return {
            "intent": "general",
            "symbol": None,
            "intent_confidence": 0.0,
        }
