"""
Phase 5 — DeepSeek-R1 Reasoning node.

Replaces the Phase 3 stub with a real call to DeepSeek-R1 14B via Ollama.

Responsibilities:
  1. Build a domain-specific prompt from AnalystState (intent + tool_results).
  2. POST to Ollama /api/generate (stream=False) with DeepSeek-R1 14B.
  3. Parse the raw output — extract <think>...</think> as cot_thinking and
     the remainder as reasoning_answer.
  4. On retry (retry_count > 0), inject flagged_claims from the previous
     verification pass so the model can correct specific errors.

Temperature is held low (0.3) for factual financial reasoning.
Max tokens = 1500 — enough for a thorough CoT + verdict without blowing latency.
HTTP timeout = 120 s (14B Q4_K_M at ~30 tok/s ≈ 50 s for 1500 tokens).
"""

import re
import logging
import httpx

from app.graph.state import AnalystState
from app.graph.prompts import (
    TECHNICAL_PROMPT,
    FUNDAMENTAL_PROMPT,
    SENTIMENT_PROMPT,
    GENERAL_PROMPT,
)

logger = logging.getLogger(__name__)

OLLAMA_URL = "http://ollama:11434/api/generate"
MODEL = "deepseek-r1:14b"
TIMEOUT = 120.0  # seconds


# ── Helpers ───────────────────────────────────────────────────────────────────

def _safe(value, fallback: str = "N/A") -> str:
    """Return str(value) or fallback when value is None / falsy."""
    if value is None:
        return fallback
    return str(value)


def _bool_label(value, true_label: str = "Yes", false_label: str = "No") -> str:
    if value is None:
        return "N/A"
    return true_label if value else false_label


def _retry_note(flagged: list) -> str:
    """Build the retry context appended to every prompt on re-attempts."""
    if not flagged:
        return ""
    items = "; ".join(flagged)
    return (
        f"\n\n⚠️  CORRECTION REQUIRED — previous answer had these errors:\n{items}\n"
        "Please address each point specifically in your revised answer."
    )


# ── Prompt builders ───────────────────────────────────────────────────────────

def _build_technical_prompt(state: AnalystState) -> str:
    tool = state.get("tool_results") or {}
    ind = tool.get("indicators") or {}
    rsi = ind.get("rsi") or {}
    macd = ind.get("macd") or {}
    bb = ind.get("bollinger_bands") or {}
    quote = tool.get("quote") or {}

    return TECHNICAL_PROMPT.format(
        symbol=_safe(state.get("symbol")),
        price=_safe(quote.get("price")),
        # RSI
        rsi_value=_safe(rsi.get("value")),
        rsi_signal=_safe(rsi.get("signal")),
        # MACD
        macd_value=_safe(macd.get("macd")),
        macd_signal=_safe(macd.get("signal")),
        histogram=_safe(macd.get("histogram")),
        macd_trend=_safe(macd.get("trend")),
        # Bollinger Bands
        bb_upper=_safe(bb.get("upper")),
        bb_middle=_safe(bb.get("middle")),
        bb_lower=_safe(bb.get("lower")),
        percent_b=_safe(bb.get("percent_b")),
        bandwidth=_safe(bb.get("bandwidth")),
        # Trend / MAs
        sma_20=_safe(ind.get("sma_20")),
        sma_50=_safe(ind.get("sma_50")),
        sma_200=_safe(ind.get("sma_200")),
        above_sma_20=_bool_label(ind.get("above_sma_20"), "Above", "Below"),
        above_sma_50=_bool_label(ind.get("above_sma_50"), "Above", "Below"),
        above_sma_200=_bool_label(ind.get("above_sma_200"), "Above", "Below"),
        # Volatility / Volume
        atr=_safe(ind.get("atr")),
        obv=_safe(ind.get("obv")),
        # User question + retry context
        user_message=state["user_message"],
        retry_note=_retry_note(state.get("flagged_claims") or []),
    )


def _build_fundamental_prompt(state: AnalystState) -> str:
    tool = state.get("tool_results") or {}
    vm = tool.get("valuation_metrics") or {}
    dcf = tool.get("dcf") or {}
    quote = tool.get("quote") or {}

    return FUNDAMENTAL_PROMPT.format(
        symbol=_safe(state.get("symbol")),
        price=_safe(quote.get("price")),
        # Valuation ratios
        pe_ratio=_safe(vm.get("pe_ratio")),
        pb_ratio=_safe(vm.get("pb_ratio")),
        ev_ebitda=_safe(vm.get("ev_ebitda")),
        profit_margin=_safe(vm.get("profit_margin")),
        roe=_safe(vm.get("roe")),
        debt_equity=_safe(vm.get("debt_to_equity")),
        # DCF
        dcf_value=_safe(dcf.get("fair_value")),
        margin_of_safety=_safe(dcf.get("margin_of_safety")),
        wacc=_safe(dcf.get("wacc")),
        # RAG document context
        rag_context=tool.get("rag_context") or "No supporting documents retrieved.",
        # User question + retry context
        user_message=state["user_message"],
        retry_note=_retry_note(state.get("flagged_claims") or []),
    )


def _build_sentiment_prompt(state: AnalystState) -> str:
    tool = state.get("tool_results") or {}
    sentiment = tool.get("sentiment") or {}
    quote = tool.get("quote") or {}

    return SENTIMENT_PROMPT.format(
        symbol=_safe(state.get("symbol")),
        price=_safe(quote.get("price")),
        news_sentiment=_safe(sentiment.get("news")),
        social_signal=_safe(sentiment.get("social")),
        analyst_consensus=_safe(sentiment.get("analyst_consensus")),
        short_interest=_safe(sentiment.get("short_interest")),
        user_message=state["user_message"],
        retry_note=_retry_note(state.get("flagged_claims") or []),
    )


def _build_general_prompt(state: AnalystState) -> str:
    return GENERAL_PROMPT.format(
        user_message=state["user_message"],
        retry_note=_retry_note(state.get("flagged_claims") or []),
    )


def _build_prompt(state: AnalystState) -> str:
    intent = state.get("intent", "general")
    builders = {
        "technical":   _build_technical_prompt,
        "fundamental": _build_fundamental_prompt,
        "sentiment":   _build_sentiment_prompt,
        "general":     _build_general_prompt,
    }
    builder = builders.get(intent, _build_general_prompt)
    return builder(state)


# ── CoT parser ────────────────────────────────────────────────────────────────

def _parse_deepseek_output(raw: str) -> tuple[str, str]:
    """
    Split DeepSeek-R1 output into (cot_thinking, reasoning_answer).

    DeepSeek-R1 wraps its chain-of-thought in <think>...</think>.
    We extract that block and strip it from the final answer.
    """
    think_match = re.search(r"<think>(.*?)</think>", raw, re.DOTALL)
    cot = think_match.group(1).strip() if think_match else ""
    answer = re.sub(r"<think>.*?</think>", "", raw, flags=re.DOTALL).strip()
    return cot, answer


# ── Main node ─────────────────────────────────────────────────────────────────

async def run(state: AnalystState) -> dict:
    """
    DeepSeek-R1 14B reasoning node.

    Builds a domain-specific prompt, calls Ollama, parses the CoT block,
    and returns cot_thinking + reasoning_answer into the graph state.
    """
    intent = state.get("intent", "general")
    symbol = state.get("symbol", "N/A")
    retry_count = state.get("retry_count", 0)

    logger.info(
        "[reasoning] intent=%s symbol=%s retry=%d — calling %s",
        intent, symbol, retry_count, MODEL,
    )

    prompt = _build_prompt(state)

    payload = {
        "model": MODEL,
        "prompt": prompt,
        "stream": False,
        "options": {
            "temperature": 0.3,   # Low temp for reproducible financial reasoning
            "top_p": 0.9,
            "num_predict": 1500,  # ~50 s at 30 tok/s on RTX 5060 Ti
        },
    }

    try:
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            resp = await client.post(OLLAMA_URL, json=payload)
            resp.raise_for_status()
            raw = resp.json().get("response", "")

    except httpx.TimeoutException:
        logger.error("[reasoning] Ollama timeout after %.0fs for %s", TIMEOUT, MODEL)
        return {
            "cot_thinking": "",
            "reasoning_answer": "",
            "error": f"DeepSeek-R1 timed out after {TIMEOUT:.0f}s. The model may be under load.",
        }
    except httpx.HTTPStatusError as exc:
        logger.error("[reasoning] Ollama HTTP error %d: %s", exc.response.status_code, exc)
        return {
            "cot_thinking": "",
            "reasoning_answer": "",
            "error": f"Ollama returned HTTP {exc.response.status_code}",
        }
    except Exception as exc:
        logger.exception("[reasoning] Unexpected error calling Ollama: %s", exc)
        return {
            "cot_thinking": "",
            "reasoning_answer": "",
            "error": str(exc),
        }

    cot, answer = _parse_deepseek_output(raw)

    logger.info(
        "[reasoning] Done — cot=%d chars, answer=%d chars",
        len(cot), len(answer),
    )

    return {
        "cot_thinking": cot,
        "reasoning_answer": answer,
        # retry_count is NOT incremented here — verification node owns that
    }
