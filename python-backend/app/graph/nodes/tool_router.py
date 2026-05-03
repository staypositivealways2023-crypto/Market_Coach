"""
Phase 3 — Tool Router node.
Dispatches data-fetching calls based on intent and serializes results into
tool_results so DeepSeek-R1 can reason over plain-dict data.

Intent routing:
  technical   → quote + candles (100d) + indicators (incl. ATR/OBV)
  fundamental → quote + valuation metrics + DCF
  sentiment   → stub (FinBERT/PRAW wired in Phase 6)
  general     → no symbol needed, empty tool_results
"""

import asyncio
import logging
from typing import Any

from app.graph.state import AnalystState
from app.services.indicator_service import TechnicalIndicatorService
from app.services.data_fetcher import MarketDataFetcher
from app.services.valuation_service import ValuationService

logger = logging.getLogger(__name__)

# Module-level singletons — instantiated once at import time
_indicator_svc = TechnicalIndicatorService()
_fetcher = MarketDataFetcher()
_valuation_svc = ValuationService()


# ── Serialization helper ──────────────────────────────────────────────────────

def _dump(obj: Any) -> Any:
    """
    Convert a Pydantic model (or list of models) to a plain JSON-safe dict.
    Falls back to obj itself for primitives and plain dicts.
    Uses mode='json' so datetime fields become ISO strings automatically.
    """
    if obj is None:
        return None
    if hasattr(obj, "model_dump"):
        return obj.model_dump(mode="json")
    if isinstance(obj, list):
        return [_dump(item) for item in obj]
    return obj


# ── Intent handlers ───────────────────────────────────────────────────────────

async def _handle_technical(symbol: str) -> dict:
    """Fetch quote + 100-day candles + full indicator suite."""
    results: dict = {}

    # Quote (async, multi-provider fallback chain)
    quote = await _fetcher.get_quote(symbol)
    results["quote"] = _dump(quote)

    if not quote:
        logger.warning("[tool_router] technical: no quote for %s — skipping indicators", symbol)
        return results

    # Candles (async, yfinance fallback)
    candles = await _fetcher.get_candles(symbol, interval="1d", limit=100)
    if not candles:
        logger.warning("[tool_router] technical: no candles for %s", symbol)
        return results

    # Indicator calculation is CPU-bound — run in thread pool to avoid blocking
    loop = asyncio.get_event_loop()
    indicators = await loop.run_in_executor(
        None,
        _indicator_svc.calculate_indicators,
        symbol,
        candles,
        quote.price,
    )

    results["indicators"] = _dump(indicators)
    # Include last 30 candles for context (full 100 would bloat the prompt)
    results["candles_30d"] = _dump(candles[-30:])

    logger.info(
        "[tool_router] technical %s: quote=%.2f rsi=%s atr=%s",
        symbol,
        quote.price,
        indicators.rsi.value if indicators and indicators.rsi else "N/A",
        indicators.atr if indicators else "N/A",
    )
    return results


async def _handle_fundamental(symbol: str) -> dict:
    """Fetch quote + valuation metrics + DCF. RAG context added in Phase 4."""
    results: dict = {}

    # Quote
    quote = await _fetcher.get_quote(symbol)
    results["quote"] = _dump(quote)

    # Valuation metrics and DCF run concurrently (both hit yfinance)
    metrics_task = asyncio.create_task(_valuation_svc.calculate_metrics(symbol))
    dcf_task = asyncio.create_task(_valuation_svc.calculate_dcf(symbol))

    metrics, dcf = await asyncio.gather(metrics_task, dcf_task, return_exceptions=True)

    results["valuation_metrics"] = _dump(metrics) if not isinstance(metrics, Exception) else {}
    results["dcf"] = _dump(dcf) if not isinstance(dcf, Exception) else {}

    if isinstance(metrics, Exception):
        logger.error("[tool_router] fundamental metrics error for %s: %s", symbol, metrics)
    if isinstance(dcf, Exception):
        logger.error("[tool_router] fundamental DCF error for %s: %s", symbol, dcf)

    # RAG context — Phase 4: LlamaIndex + pgvector retrieval
    try:
        from app.rag.retriever import rag_search
        rag_query = f"{symbol} earnings revenue fundamentals valuation"
        results["rag_context"] = await rag_search(rag_query, top_k=5)
        logger.info(
            "[tool_router] fundamental %s: rag_context=%d chars",
            symbol,
            len(results["rag_context"]) if results["rag_context"] else 0,
        )
    except Exception as exc:
        logger.warning("[tool_router] RAG search failed for %s: %s", symbol, exc)
        results["rag_context"] = None

    logger.info(
        "[tool_router] fundamental %s: pe=%s dcf_signal=%s",
        symbol,
        results["valuation_metrics"].get("pe_ratio") if results["valuation_metrics"] else "N/A",
        results["dcf"].get("signal") if results["dcf"] else "N/A",
    )
    return results


async def _handle_sentiment(symbol: str) -> dict:
    """Sentiment tools wired in Phase 6 (FinBERT + Reddit PRAW)."""
    logger.info("[tool_router] sentiment stub for %s — Phase 6 pending", symbol)
    return {
        "sentiment": {
            "status": "pending_phase_6",
            "symbol": symbol,
            "news": None,
            "social": None,
        }
    }


# ── Main node entry point ─────────────────────────────────────────────────────

async def run(state: AnalystState) -> dict:
    """
    Dispatch to the correct data handler based on intent.
    All exceptions are caught; errors are logged but do not crash the graph.
    """
    intent = state.get("intent", "general")
    symbol = state.get("symbol")

    logger.info("[tool_router] intent=%s symbol=%s", intent, symbol)

    tool_results: dict = {}

    try:
        if not symbol:
            # General queries have no symbol — return empty results
            logger.info("[tool_router] no symbol — skipping data fetch (general intent)")

        elif intent == "technical":
            tool_results = await _handle_technical(symbol)

        elif intent == "fundamental":
            tool_results = await _handle_fundamental(symbol)

        elif intent == "sentiment":
            tool_results = await _handle_sentiment(symbol)

        else:
            # general with a symbol — just grab a quote for context
            quote = await _fetcher.get_quote(symbol)
            tool_results["quote"] = _dump(quote)

    except Exception as exc:
        logger.exception("[tool_router] unhandled error for %s/%s: %s", intent, symbol, exc)
        tool_results["error"] = str(exc)

    return {"tool_results": tool_results}
