"""Jarvis Adapter Service

Thin async HTTP client that bridges MarketCoach backend to the local Jarvis
REST API (default: http://localhost:7700).

When Ollama/Jarvis is offline, falls back to Claude API (claude-haiku-4-5-20251001)
so the Flutter chat always works as long as ANTHROPIC_API_KEY is set in .env.

Market-data grounding: if the user's message contains a recognised ticker symbol,
live quote data is fetched and injected into the prompt as a [MARKET DATA] block
so neither Ollama nor Claude can hallucinate price numbers.
"""

from __future__ import annotations

import logging
import re
from typing import Any

import httpx

from app.config import settings
from app.services.data_fetcher import MarketDataFetcher

logger = logging.getLogger(__name__)

_TIMEOUT = getattr(settings, "JARVIS_TIMEOUT_SECONDS", 25)
_data_fetcher = MarketDataFetcher()

SYSTEM_PROMPT = (
    "You are Jarvis, a helpful AI financial coach for MarketCoach. "
    "You help users understand market data, stocks, crypto, and finance concepts. "
    "Be concise, accurate, and friendly. "
    "When a [MARKET DATA] block is present in the user message, use ONLY those "
    "numbers - never guess or hallucinate prices or indicators. "
    "Do not give specific investment advice or make buy/sell recommendations."
)

# Ticker detection helpers
_KNOWN_CRYPTO = {
    "BTC", "ETH", "BNB", "SOL", "ADA", "DOT", "AVAX", "XRP", "DOGE",
    "MATIC", "LINK", "LTC", "UNI", "ATOM", "FIL", "TRX", "XLM",
}
_CRYPTO_NAME_TO_TICKER = {
    "bitcoin": "BTC",
    "ethereum": "ETH",
    "ether": "ETH",
    "solana": "SOL",
    "binance coin": "BNB",
    "bnb": "BNB",
    "cardano": "ADA",
    "polkadot": "DOT",
    "avalanche": "AVAX",
    "ripple": "XRP",
    "dogecoin": "DOGE",
    "polygon": "MATIC",
    "chainlink": "LINK",
    "litecoin": "LTC",
    "uniswap": "UNI",
    "cosmos": "ATOM",
    "filecoin": "FIL",
    "tron": "TRX",
    "stellar": "XLM",
}
_TICKER_RE = re.compile(r'\b([A-Z]{1,5})\b')

# Common stock company names → ticker.  Keep the list conservative to avoid
# false positives; only well-known single-word or short-phrase names.
_STOCK_NAME_TO_TICKER: dict[str, str] = {
    "nvidia": "NVDA",
    "apple": "AAPL",
    "microsoft": "MSFT",
    "google": "GOOGL",
    "alphabet": "GOOGL",
    "amazon": "AMZN",
    "meta": "META",
    "tesla": "TSLA",
    "netflix": "NFLX",
    "disney": "DIS",
    "paypal": "PYPL",
    "salesforce": "CRM",
    "intel": "INTC",
    "amd": "AMD",
    "qualcomm": "QCOM",
    "broadcom": "AVGO",
    "oracle": "ORCL",
    "ibm": "IBM",
    "cisco": "CSCO",
    "shopify": "SHOP",
    "uber": "UBER",
    "lyft": "LYFT",
    "airbnb": "ABNB",
    "palantir": "PLTR",
    "coinbase": "COIN",
    "robinhood": "HOOD",
    "snowflake": "SNOW",
    "datadog": "DDOG",
    "crowdstrike": "CRWD",
    "zoom": "ZM",
    "pinterest": "PINS",
    "twitter": "X",    # delisted but commonly mentioned
    "jpmorgan": "JPM",
    "goldman": "GS",
    "goldman sachs": "GS",
    "bank of america": "BAC",
    "citigroup": "C",
    "wells fargo": "WFC",
    "morgan stanley": "MS",
    "berkshire": "BRK-B",
    "johnson": "JNJ",
    "johnson & johnson": "JNJ",
    "pfizer": "PFE",
    "moderna": "MRNA",
    "abbvie": "ABBV",
    "exxon": "XOM",
    "chevron": "CVX",
    "walmart": "WMT",
    "target": "TGT",
    "costco": "COST",
    "nike": "NKE",
    "starbucks": "SBUX",
    "mcdonald": "MCD",
    "mcdonalds": "MCD",
    "coca cola": "KO",
    "cocacola": "KO",
    "pepsi": "PEP",
    "pepsico": "PEP",
    "boeing": "BA",
}


def _detect_tickers(text: str) -> list[str]:
    """Extract up to 3 likely ticker symbols from a free-form query."""
    raw_upper = text.upper()
    found: list[str] = []
    # Check crypto names first
    for name, ticker in _CRYPTO_NAME_TO_TICKER.items():
        if re.search(rf'\b{re.escape(name)}\b', text, re.IGNORECASE) and ticker not in found:
            found.append(ticker)
    # Check stock company names
    for name, ticker in _STOCK_NAME_TO_TICKER.items():
        if re.search(rf'\b{re.escape(name)}\b', text, re.IGNORECASE) and ticker not in found:
            found.append(ticker)
    for m in re.finditer(r'\$([A-Z]{1,5})\b', raw_upper):
        t = m.group(1)
        if t not in found:
            found.append(t)
    for m in _TICKER_RE.finditer(raw_upper):
        t = m.group(1)
        if t in found:
            continue
        if t in _KNOWN_CRYPTO:
            found.append(t)
        elif len(t) >= 2 and re.search(
            rf'(stock|ticker|symbol|chart|price|buy|sell|rsi|macd)\s+{t}\b|'
            rf'\b{t}\s+(stock|price|chart|rsi|macd|analysis)',
            raw_upper,
        ):
            found.append(t)
    return found[:3]


async def _fetch_market_context(tickers: list[str]) -> str:
    """Fetch live quote + indicators for each ticker and return a grounding block."""
    if not tickers:
        return ""
    lines = ["[MARKET DATA - sourced live, do not alter these numbers]"]
    any_data = False
    for sym in tickers:
        try:
            quote = await _data_fetcher.get_quote(sym)
            if quote is None:
                continue
            price = quote.price
            price_str = f"${price:.4f}" if price < 1 else f"${price:,.2f}"
            chg = quote.change_percent
            chg_str = f"{chg:+.2f}%" if chg is not None else "N/A"
            extra = ""
            if quote.volume:
                v = quote.volume
                vol = f"{v/1e9:.2f}B" if v >= 1e9 else f"{v/1e6:.1f}M" if v >= 1e6 else f"{v:,.0f}"
                extra += f"  Vol={vol}"
            if quote.market_cap:
                mc = quote.market_cap
                cap = f"${mc/1e12:.2f}T" if mc >= 1e12 else f"${mc/1e9:.1f}B"
                extra += f"  MCap={cap}"
            lines.append(f"{sym}: Price={price_str}  Change={chg_str}{extra}")
            any_data = True

            # ── Enrich with technical indicators (RSI, MACD) ──────────────
            try:
                candles = await _data_fetcher.get_candles(sym, interval="1d", limit=60)
                if candles and len(candles) >= 26:
                    from app.services.indicator_service import IndicatorService
                    _indicator_svc = IndicatorService()
                    indicators = _indicator_svc.calculate_indicators(
                        symbol=sym,
                        candles=candles,
                        current_price=price,
                    )
                    if indicators:
                        ind_parts = []
                        if indicators.rsi:
                            ind_parts.append(f"RSI(14)={indicators.rsi.value:.1f}")
                        if indicators.macd:
                            ind_parts.append(
                                f"MACD={indicators.macd.macd:.4f} "
                                f"Signal={indicators.macd.signal:.4f} "
                                f"Hist={indicators.macd.histogram:.4f}"
                            )
                        if ind_parts:
                            lines.append(f"  Indicators: {' | '.join(ind_parts)}")
            except Exception as ind_exc:
                logger.debug(f"[jarvis_adapter] indicator fetch skipped for {sym}: {ind_exc}")

        except Exception as exc:
            logger.warning(f"[jarvis_adapter] market context fetch failed for {sym}: {exc}")
    if not any_data:
        return ""
    lines.append("[END MARKET DATA]")
    block = "\n".join(lines)
    logger.info(f"[jarvis_adapter] injected market context tickers={tickers}")
    return block


def _inject_context(query: str, context: str) -> str:
    """Prepend the market-data block to the user query."""
    if not context:
        return query
    return f"{context}\n\n{query}"


def _market_unavailable_context(tickers: list[str]) -> str:
    symbols = ", ".join(tickers)
    return (
        "[MARKET DATA UNAVAILABLE]\n"
        f"Live market data is temporarily unavailable for {symbols}. "
        "Tell the user this clearly and do not guess prices, indicators, "
        "volume, market cap, or other live market numbers.\n"
        "[END MARKET DATA UNAVAILABLE]"
    )


def _client() -> httpx.AsyncClient:
    """Return a new async client pointed at JARVIS_URL."""
    return httpx.AsyncClient(
        base_url=settings.JARVIS_URL,
        timeout=_TIMEOUT,
        headers={"Content-Type": "application/json"},
    )


async def _claude_fallback(query: str, history: list[dict] | None = None) -> str:
    """Use Claude API when Ollama/Jarvis is unavailable."""
    api_key = getattr(settings, "ANTHROPIC_API_KEY", "")
    if not api_key:
        return (
            "Jarvis is currently offline and no AI fallback is configured. "
            "Please start Ollama or set ANTHROPIC_API_KEY in your .env file."
        )
    try:
        import anthropic
        client = anthropic.AsyncAnthropic(api_key=api_key)
        messages: list[dict] = []
        if history:
            for turn in history:
                role = turn.get("role", "user")
                content = turn.get("content", "")
                if role in ("user", "assistant") and content:
                    messages.append({"role": role, "content": content})
        messages.append({"role": "user", "content": query})
        logger.info(
            f"[claude_fallback] sending query='{query[:80]}' "
            f"messages={len(messages)} history_turns={len(history or [])}"
        )
        response = await client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=1024,
            system=SYSTEM_PROMPT,
            messages=messages,
        )
        reply = response.content[0].text
        logger.info(f"[claude_fallback] reply_chars={len(reply)}")
        return reply
    except Exception as exc:
        logger.error(f"[claude_fallback] failed: {exc}")
        return "I'm having trouble connecting right now. Please try again in a moment."


async def jarvis_health() -> dict:
    """Check if Jarvis API is reachable."""
    try:
        async with _client() as c:
            r = await c.get("/health")
            r.raise_for_status()
            return {"online": True, "detail": r.json(), "model": "ollama"}
    except Exception as exc:
        logger.warning(f"[jarvis_adapter] Ollama offline: {exc}")
    if getattr(settings, "ANTHROPIC_API_KEY", ""):
        logger.info("[jarvis_adapter] Claude API fallback available")
        return {"online": True, "detail": "claude-fallback", "model": "claude-haiku-4-5-20251001"}
    return {"online": False, "detail": "No AI backend available"}


async def jarvis_ask(query: str, history: list[dict] | None = None) -> str:
    """Send a free-form query through Jarvis or Claude fallback.

    Detects ticker symbols in the query, fetches live market data, and injects
    a grounding block so the LLM cannot hallucinate prices or indicators.
    """
    tickers = _detect_tickers(query)
    market_ctx = await _fetch_market_context(tickers) if tickers else ""
    if tickers and not market_ctx:
        market_ctx = _market_unavailable_context(tickers)
    grounded_query = _inject_context(query, market_ctx)
    logger.info(
        f"[jarvis_ask] query='{query[:80]}' tickers={tickers} "
        f"context_chars={len(market_ctx)} history_turns={len(history or [])}"
    )
    payload: dict[str, Any] = {"query": grounded_query}
    if history:
        payload["history"] = history
    try:
        async with _client() as c:
            r = await c.post("/ask", json=payload)
            r.raise_for_status()
            data = r.json()
            reply = data.get("response") or data.get("message") or str(data)
            logger.info(f"[jarvis_ask] ollama reply_chars={len(reply)}")
            return reply
    except httpx.ConnectError:
        logger.info("[jarvis_adapter] Ollama offline - using Claude API fallback")
        return await _claude_fallback(grounded_query, history)
    except httpx.TimeoutException:
        logger.warning("[jarvis_adapter] Jarvis timed out - using Claude API fallback")
        return await _claude_fallback(grounded_query, history)
    except Exception as exc:
        logger.error(f"[jarvis_adapter] jarvis_ask failed: {exc}")
        return await _claude_fallback(grounded_query, history)


async def jarvis_quote(ticker: str) -> dict:
    """Fetch a live price quote from Jarvis."""
    ticker = ticker.upper()
    try:
        async with _client() as c:
            r = await c.get(f"/quote/{ticker}")
            r.raise_for_status()
            return r.json()
    except httpx.ConnectError:
        return {"error": "Jarvis offline"}
    except httpx.HTTPStatusError as exc:
        return {"error": f"Jarvis /quote returned {exc.response.status_code}"}
    except Exception as exc:
        logger.error(f"[jarvis_adapter] jarvis_quote({ticker}) failed: {exc}")
        return {"error": str(exc)}


async def jarvis_indicators(ticker: str) -> dict:
    """Fetch RSI, MACD, and 52-week range from Jarvis."""
    ticker = ticker.upper()
    try:
        async with _client() as c:
            r = await c.get(f"/indicators/{ticker}")
            r.raise_for_status()
            return r.json()
    except httpx.ConnectError:
        return {"error": "Jarvis offline"}
    except httpx.HTTPStatusError as exc:
        return {"error": f"Jarvis /indicators returned {exc.response.status_code}"}
    except Exception as exc:
        logger.error(f"[jarvis_adapter] jarvis_indicators({ticker}) failed: {exc}")
        return {"error": str(exc)}


async def jarvis_analyse(ticker: str, question: str | None = None) -> dict:
    """Request a grounded analysis for a ticker."""
    ticker = ticker.upper()
    payload: dict[str, Any] = {}
    if question:
        payload["question"] = question
    try:
        async with _client() as c:
            r = await c.post(f"/analyse/{ticker}", json=payload)
            r.raise_for_status()
            return r.json()
    except httpx.ConnectError:
        return {"error": "Jarvis offline"}
    except httpx.HTTPStatusError as exc:
        return {"error": f"Jarvis /analyse returned {exc.response.status_code}"}
    except Exception as exc:
        logger.error(f"[jarvis_adapter] jarvis_analyse({ticker}) failed: {exc}")
        return {"error": str(exc)}


async def jarvis_snapshot(ticker: str) -> dict:
    """Combined quote + indicators in one round-trip."""
    quote = await jarvis_quote(ticker)
    if "error" in quote:
        return quote
    indicators = await jarvis_indicators(ticker)
    return {**quote, **indicators, "jarvis_source": True}
