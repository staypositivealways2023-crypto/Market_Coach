"""
CrewAI Tool wrappers — thin async-to-sync bridges around existing services.

Each tool is a plain Python function decorated with @tool so CrewAI can
discover and call it.  Heavy I/O runs in asyncio event loops via
asyncio.run() — safe because CrewAI tasks run in threads, not the main loop.
"""

import asyncio
import json
import logging
from typing import Optional

from crewai.tools import tool

logger = logging.getLogger(__name__)


# ── helpers ───────────────────────────────────────────────────────────────────

def _run(coro):
    """Run an async coroutine synchronously (thread-safe)."""
    try:
        loop = asyncio.get_event_loop()
        if loop.is_running():
            import concurrent.futures
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
                fut = ex.submit(asyncio.run, coro)
                return fut.result(timeout=30)
        return loop.run_until_complete(coro)
    except Exception:
        return asyncio.run(coro)


# ── Market Data Tool ──────────────────────────────────────────────────────────

@tool("get_market_data")
def get_market_data(symbol: str) -> str:
    """
    Fetch real-time quote, 90-day daily candles, and technical indicators
    (RSI, MACD, EMA stack, Bollinger Bands, ATR) for a stock or crypto symbol.
    Returns a JSON string with: price, change_percent, rsi, macd_histogram,
    ema_stack, volume, atr, candle_count.
    """
    from app.services.data_fetcher import MarketDataFetcher
    from app.services.indicator_service import TechnicalIndicatorService

    sym = symbol.strip().upper()
    fetcher   = MarketDataFetcher()
    indicator = TechnicalIndicatorService()

    async def _fetch():
        quote, candles = await asyncio.gather(
            fetcher.get_quote(sym),
            fetcher.get_candles(sym, interval="1d", limit=90),
            return_exceptions=True,
        )
        return quote, candles

    quote, candles = _run(_fetch())

    indicators = {}
    if isinstance(candles, list) and candles:
        try:
            indicators = indicator.calculate_all(candles)
        except Exception as e:
            logger.warning(f"[tools] indicator calc failed for {sym}: {e}")

    result = {
        "symbol":          sym,
        "price":           quote.price          if hasattr(quote, "price") else None,
        "change_percent":  quote.change_percent  if hasattr(quote, "change_percent") else None,
        "volume":          quote.volume          if hasattr(quote, "volume") else None,
        "market_cap":      quote.market_cap      if hasattr(quote, "market_cap") else None,
        "candle_count":    len(candles) if isinstance(candles, list) else 0,
        **indicators,
    }
    return json.dumps(result, default=str)


# ── Technical Pattern Tool ────────────────────────────────────────────────────

@tool("detect_chart_patterns")
def detect_chart_patterns(symbol: str) -> str:
    """
    Run pattern recognition on the last 90 daily candles for a symbol.
    Returns: list of detected patterns (e.g. double_top, head_and_shoulders,
    support_bounce) with their signal direction and confidence score.
    """
    from app.services.data_fetcher import MarketDataFetcher
    from app.services.pattern_engine import PatternEngine

    sym     = symbol.strip().upper()
    fetcher = MarketDataFetcher()
    engine  = PatternEngine()

    candles = _run(fetcher.get_candles(sym, interval="1d", limit=90))

    if not candles:
        return json.dumps({"symbol": sym, "patterns": [], "error": "no candle data"})

    try:
        patterns = engine.scan(candles)
        return json.dumps({
            "symbol":   sym,
            "patterns": [p.dict() if hasattr(p, "dict") else str(p) for p in (patterns or [])],
        }, default=str)
    except Exception as e:
        return json.dumps({"symbol": sym, "patterns": [], "error": str(e)})


# ── News & Sentiment Tool ─────────────────────────────────────────────────────

@tool("get_news_sentiment")
def get_news_sentiment(symbol: str) -> str:
    """
    Fetch the latest 20 news articles for a symbol and score their sentiment
    using FinBERT (if available) or VADER.  Returns: article headlines,
    average sentiment score (-1 to +1), overall label (positive/negative/neutral),
    and Fear & Greed Index value.
    """
    from app.services.news_service import NewsService

    sym  = symbol.strip().upper()
    svc  = NewsService()

    articles = _run(svc.get_news(sym, limit=20))

    if not articles:
        return json.dumps({
            "symbol": sym,
            "article_count": 0,
            "average_sentiment": 0.0,
            "overall": "neutral",
            "headlines": [],
        })

    scores    = [a.sentiment_score for a in articles]
    avg       = round(sum(scores) / len(scores), 3)
    overall   = "positive" if avg > 0.05 else "negative" if avg < -0.05 else "neutral"
    headlines = [{"title": a.title, "source": a.source, "sentiment": a.sentiment_label}
                 for a in articles[:10]]

    return json.dumps({
        "symbol":            sym,
        "article_count":     len(articles),
        "average_sentiment": avg,
        "overall":           overall,
        "headlines":         headlines,
    }, default=str)


# ── Macro Context Tool ────────────────────────────────────────────────────────

@tool("get_macro_context")
def get_macro_context(dummy: str = "US") -> str:
    """
    Fetch macro-economic context: US Fed funds rate, CPI, 10Y yield,
    dollar index (DXY), and Fear & Greed Index.
    Pass any string (e.g. 'US') — the argument is not used.
    Returns a JSON summary of current macro conditions.
    """
    from app.services.fred_service import FredService

    svc  = FredService()
    data = _run(svc.get_overview()) if hasattr(svc, "get_overview") else {}

    return json.dumps({
        "source": "FRED + market data",
        "macro":  data if data else {
            "note": "FRED not configured — set FRED_API_KEY in .env for live macro data",
        },
    }, default=str)


# ── Fundamentals Tool ─────────────────────────────────────────────────────────

@tool("get_fundamentals")
def get_fundamentals(symbol: str) -> str:
    """
    Fetch fundamental data for a stock: P/E ratio, revenue growth, EPS,
    profit margin, debt/equity, and analyst price target.
    Not applicable to crypto — returns empty for crypto symbols.
    """
    from app.services.fundamental_service import FundamentalService
    from app.services.data_fetcher import _is_crypto_symbol

    sym = symbol.strip().upper()
    if _is_crypto_symbol(sym):
        return json.dumps({"symbol": sym, "note": "fundamentals not available for crypto"})

    svc  = FundamentalService()
    data = _run(svc.get_fundamentals(sym))

    if data is None:
        return json.dumps({"symbol": sym, "error": "fundamentals unavailable"})

    return json.dumps(
        data.dict() if hasattr(data, "dict") else data,
        default=str,
    )


# ── User Memory Tool ──────────────────────────────────────────────────────────

@tool("recall_user_context")
def recall_user_context(query: str) -> str:
    """
    Recall relevant memories for the current user from ChromaDB.
    Pass a natural-language query such as 'what symbols has this user been watching'
    or 'user risk tolerance'.
    Returns: up to 5 most semantically relevant memory snippets.
    Used by the Coach Agent to personalise its output.
    """
    # uid is injected at runtime by the crew runner (see crew.py run_crew)
    # We store the uid in a module-level context var set before crew.kickoff()
    from app.agents.crew import _CURRENT_UID

    uid = _CURRENT_UID or "anonymous"
    try:
        from app.services.chroma_memory_service import ChromaMemoryService
        svc      = ChromaMemoryService()
        memories = svc.recall(uid, query=query, n=5)
        return json.dumps({"uid": uid, "memories": memories})
    except Exception as e:
        return json.dumps({"uid": uid, "memories": [], "error": str(e)})
