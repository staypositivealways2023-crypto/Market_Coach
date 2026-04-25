"""Market data endpoints"""

from fastapi import APIRouter, HTTPException, Query
from typing import List, Optional
import asyncio
import logging
import math
from datetime import datetime, timedelta

import yfinance as yf

from app.services.data_fetcher import (
    MarketDataFetcher,
    _is_crypto_symbol,
    _to_yfinance_symbol,
    _YF_SEMAPHORE,
)
from app.models.stock import Quote, Candle, StockInfo
from app.utils.cache import cache_manager

logger = logging.getLogger(__name__)
router = APIRouter()

# Service instance
data_fetcher = MarketDataFetcher()


async def _get_crypto_year_range(symbol: str) -> dict:
    """
    52-week high/low for a crypto symbol via yfinance fast_info.
    Uses fast_info (Yahoo v7/quote endpoint) — much faster than downloading 365 daily candles.
    """
    def _sync():
        try:
            yf_sym = _to_yfinance_symbol(symbol)
            fi = yf.Ticker(yf_sym).fast_info

            def _clean(v):
                if v is None:
                    return None
                try:
                    f = float(v)
                    return None if (math.isnan(f) or math.isinf(f) or f <= 0) else f
                except (TypeError, ValueError):
                    return None

            return {
                "year_high": _clean(getattr(fi, "year_high", None)),
                "year_low":  _clean(getattr(fi, "year_low",  None)),
            }
        except Exception as e:
            logger.warning(f"[crypto year range] {symbol}: {e}")
            return {"year_high": None, "year_low": None}

    async with _YF_SEMAPHORE:
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, _sync)


@router.get("/quote/{symbol}", response_model=Quote)
async def get_quote(symbol: str):
    """Get real-time quote for a symbol"""

    quote = await data_fetcher.get_quote(symbol.upper())

    if not quote:
        raise HTTPException(status_code=404, detail=f"Quote not found for {symbol}")

    return quote


@router.get("/quotes", response_model=List[Quote])
async def get_quotes(symbols: str = Query(..., description="Comma-separated symbols")):
    """
    Batch quote endpoint.
    Uses Binance (crypto) + Polygon (stocks) batch calls to minimise HTTP round-trips
    and avoid yfinance Yahoo 429 errors under load.
    Per-symbol cache (60s TTL) prevents redundant calls for the same symbol.
    Returns partial results — failed symbols are omitted, not 500.
    """
    symbol_list = [s.strip().upper() for s in symbols.split(",") if s.strip()]
    if not symbol_list:
        return []

    logger.info(f"[quotes] batch request ({len(symbol_list)} symbols): {symbol_list}")

    try:
        quotes = await data_fetcher.get_quotes_batch(symbol_list)
    except Exception as e:
        logger.error(f"[quotes] get_quotes_batch error: {e} — falling back to individual")
        # Per-symbol fallback so a single broken provider doesn't kill the whole batch
        raw = await asyncio.gather(
            *[data_fetcher.get_quote(sym) for sym in symbol_list],
            return_exceptions=True,
        )
        quotes = [r for r in raw if isinstance(r, Quote)]

    resolved = {q.symbol for q in quotes}
    missing  = [s for s in symbol_list if s not in resolved]
    if missing:
        logger.warning(f"[quotes] {len(missing)} symbols returned no quote: {missing}")

    logger.info(
        f"[quotes] returning {len(quotes)}/{len(symbol_list)} quotes "
        f"(missing={missing if missing else 'none'})"
    )
    return quotes


@router.get("/candles/{symbol}", response_model=List[Candle])
async def get_candles(
    symbol: str,
    interval: str = Query("1d", description="1m|5m|15m|1h|1d|1wk"),
    limit: int = Query(100, ge=1, le=500, description="Number of candles")
):
    """Get historical candles for a symbol"""

    candles = await data_fetcher.get_candles(
        symbol=symbol.upper(),
        interval=interval,
        limit=limit
    )

    if not candles:
        raise HTTPException(
            status_code=404,
            detail=f"Candles not found for {symbol}"
        )

    return candles


@router.get("/info/{symbol}", response_model=StockInfo)
async def get_stock_info(symbol: str):
    """Get detailed stock information"""

    info = await data_fetcher.get_stock_info(symbol.upper())

    if not info:
        raise HTTPException(
            status_code=404,
            detail=f"Stock info not found for {symbol}"
        )

    return info


@router.get("/range/{symbol}")
async def get_price_range(symbol: str):
    """
    Day range (high/low) + 52-week range for a symbol.
    Used for the price range bar in the stock detail screen.
    """
    sym = symbol.upper()
    cache_key = f"range:{sym}"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    if _is_crypto_symbol(sym):
        # Crypto path: Binance quote already has 24h high/low; use yfinance fast_info for
        # 52-week range (much faster than downloading 365 daily candles via yfinance).
        quote, year_range = await asyncio.gather(
            data_fetcher.get_quote(sym),
            _get_crypto_year_range(sym),
        )
        day_high  = quote.high if quote else None
        day_low   = quote.low  if quote else None
        year_high = year_range.get("year_high")
        year_low  = year_range.get("year_low")
        candles   = []  # not fetched for crypto
    else:
        # Stock path: existing candle-based logic unchanged
        quote, candles = await asyncio.gather(
            data_fetcher.get_quote(sym),
            data_fetcher.get_candles(sym, interval="1d", limit=365),
        )
        year_high = max((c.high for c in candles), default=None) if candles else None
        year_low  = min((c.low  for c in candles), default=None) if candles else None
        day_high  = quote.high if quote else None
        day_low   = quote.low  if quote else None
        if (day_high is None or day_low is None) and candles:
            last = candles[-1]
            day_high = day_high or last.high
            day_low  = day_low  or last.low

    logger.info(
        f"[range] {sym} → price={quote.price if quote else None} "
        f"day_high={day_high} day_low={day_low} "
        f"year_high={year_high} year_low={year_low} "
        f"candles={len(candles)} quote={'ok' if quote else 'MISSING'} "
        f"crypto={_is_crypto_symbol(sym)}"
    )
    if not quote:
        logger.warning(f"[range] {sym} → quote missing — all providers failed for this symbol")
    if day_high is None or day_low is None:
        logger.warning(f"[range] {sym} → day range missing (day_high={day_high} day_low={day_low})")

    result = {
        "symbol": sym,
        "current_price": quote.price if quote else None,
        "day_high":      day_high,
        "day_low":       day_low,
        "open":          quote.open  if quote else None,
        "previous_close":quote.previous_close if quote else None,
        "volume":        quote.volume if quote else None,
        "market_cap":    quote.market_cap if quote else None,
        "year_high":     year_high,
        "year_low":      year_low,
    }

    cache_manager.set(cache_key, result, ttl=300)  # 5 min
    return result


# ── Major Indices ─────────────────────────────────────────────────────────────

_INDEX_MAP = {
    "SPY":  {"name": "S&P 500",       "type": "stock"},
    "QQQ":  {"name": "Nasdaq 100",    "type": "stock"},
    "DIA":  {"name": "Dow Jones",     "type": "stock"},
    "IWM":  {"name": "Russell 2000",  "type": "stock"},
    "VIX":  {"name": "VIX",           "type": "stock"},
    "BTC":  {"name": "Bitcoin",       "type": "crypto"},
    "ETH":  {"name": "Ethereum",      "type": "crypto"},
    "BNB":  {"name": "BNB",           "type": "crypto"},
    "SOL":  {"name": "Solana",        "type": "crypto"},
}


@router.get("/indices")
async def get_indices(category: str = Query("all", description="all|stock|crypto")):
    """
    Real-time quotes for major market indices and top cryptos.
    category: all | stock | crypto
    """
    cache_key = f"indices:{category}"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    symbols = [
        s for s, meta in _INDEX_MAP.items()
        if category == "all" or meta["type"] == category
    ]

    quotes = await data_fetcher.get_quotes_batch(symbols)
    quote_map = {q.symbol: q for q in quotes}

    result = []
    for sym in symbols:
        q = quote_map.get(sym)
        meta = _INDEX_MAP[sym]
        result.append({
            "symbol":        sym,
            "name":          meta["name"],
            "type":          meta["type"],
            "price":         q.price         if q else None,
            "change":        q.change        if q else None,
            "change_percent":q.change_percent if q else None,
            "volume":        q.volume        if q else None,
            "market_cap":    q.market_cap    if q else None,
        })

    cache_manager.set(cache_key, result, ttl=60)  # 1-min TTL
    return result


# ── Sector Heat Map ───────────────────────────────────────────────────────────

_SECTOR_ETFS = {
    "Technology":         "XLK",
    "Healthcare":         "XLV",
    "Financials":         "XLF",
    "Consumer Disc.":     "XLY",
    "Communication":      "XLC",
    "Industrials":        "XLI",
    "Consumer Staples":   "XLP",
    "Energy":             "XLE",
    "Utilities":          "XLU",
    "Real Estate":        "XLRE",
    "Materials":          "XLB",
}


@router.get("/heatmap")
async def get_sector_heatmap():
    """
    Daily performance heatmap for major US market sectors via SPDR ETFs.
    Returns list of {sector, etf_symbol, change_percent, price}.
    """
    cache_key = "heatmap:sectors"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    symbols = list(_SECTOR_ETFS.values())
    quotes = await data_fetcher.get_quotes_batch(symbols)
    quote_map = {q.symbol: q for q in quotes}

    heatmap = []
    for sector, etf in _SECTOR_ETFS.items():
        q = quote_map.get(etf)
        heatmap.append({
            "sector":         sector,
            "etf_symbol":     etf,
            "price":          q.price          if q else None,
            "change_percent": q.change_percent  if q else None,
            "change":         q.change          if q else None,
        })

    # Sort by change_percent descending (best sectors first)
    heatmap.sort(key=lambda x: (x["change_percent"] or 0), reverse=True)

    cache_manager.set(cache_key, heatmap, ttl=300)  # 5 min
    return heatmap


# ── Economic Calendar ─────────────────────────────────────────────────────────

# Static near-term high-impact events (supplement with FRED/Finnhub when available)
# In production wire this to a real economic calendar API.
@router.get("/economic-calendar")
async def get_economic_calendar(days_ahead: int = Query(14, ge=1, le=30)):
    """
    Upcoming high-impact economic events for the next N days.
    Currently returns curated static events + FOMC meeting dates.
    Wire to a live calendar API (Finnhub, Trading Economics) for production.
    """
    cache_key = f"econ-calendar:{days_ahead}"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    # Minimal static set — replace with live API call
    today = datetime.utcnow().date()
    events = [
        {"date": "2026-04-29", "event": "US GDP Q1 (Advance)",        "impact": "high",   "country": "US",  "actual": None, "forecast": "2.1%",   "previous": "2.4%"},
        {"date": "2026-04-30", "event": "FOMC Rate Decision",          "impact": "high",   "country": "US",  "actual": None, "forecast": "4.25%",  "previous": "4.25%"},
        {"date": "2026-05-02", "event": "US Non-Farm Payrolls",        "impact": "high",   "country": "US",  "actual": None, "forecast": "175K",   "previous": "228K"},
        {"date": "2026-05-07", "event": "RBA Rate Decision",           "impact": "medium", "country": "AU",  "actual": None, "forecast": "4.10%",  "previous": "4.10%"},
        {"date": "2026-05-13", "event": "US CPI (Apr)",                "impact": "high",   "country": "US",  "actual": None, "forecast": "0.3%",   "previous": "0.2%"},
        {"date": "2026-05-15", "event": "US Retail Sales (Apr)",       "impact": "medium", "country": "US",  "actual": None, "forecast": "0.4%",   "previous": "-0.9%"},
        {"date": "2026-05-20", "event": "Fed Minutes",                 "impact": "medium", "country": "US",  "actual": None, "forecast": None,     "previous": None},
        {"date": "2026-05-22", "event": "US PMI Flash (May)",          "impact": "medium", "country": "US",  "actual": None, "forecast": "52.0",   "previous": "52.2"},
    ]

    cutoff = (today + timedelta(days=days_ahead)).isoformat()
    filtered = [e for e in events if e["date"] >= today.isoformat() and e["date"] <= cutoff]

    result = {"events": filtered, "count": len(filtered)}
    cache_manager.set(cache_key, result, ttl=3600)  # 1-hour cache (static data)
    return result


# ── Stock Screener ────────────────────────────────────────────────────────────

_SCREENER_UNIVERSE = [
    "AAPL","MSFT","NVDA","GOOGL","AMZN","META","TSLA","BRK-B",
    "JPM","V","JNJ","UNH","XOM","PG","MA","HD","CVX","MRK",
    "ABBV","LLY","AVGO","COST","PEP","KO","TMO","WMT","BAC",
    "DIS","CSCO","ADBE","ACN","CRM","NFLX","INTC","AMD","QCOM",
    "BTC","ETH","BNB","SOL","ADA","DOT","AVAX",
]


@router.get("/screener")
async def get_screener(
    min_change: float  = Query(None, description="Min daily change % (e.g. 2.0)"),
    max_change: float  = Query(None, description="Max daily change % (e.g. -2.0)"),
    asset_type: str    = Query("all", description="all|stock|crypto"),
    limit:      int    = Query(20, ge=1, le=50),
):
    """
    Simple screener — filter universe by daily % change.
    Returns top movers matching the criteria.
    """
    cache_key = f"screener:{min_change}:{max_change}:{asset_type}:{limit}"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    symbols = _SCREENER_UNIVERSE
    if asset_type == "stock":
        symbols = [s for s in symbols if not _is_crypto_symbol(s)]
    elif asset_type == "crypto":
        symbols = [s for s in symbols if _is_crypto_symbol(s)]

    quotes = await data_fetcher.get_quotes_batch(symbols[:40])  # cap to avoid overload

    results = []
    for q in quotes:
        if q.change_percent is None:
            continue
        if min_change is not None and q.change_percent < min_change:
            continue
        if max_change is not None and q.change_percent > max_change:
            continue
        results.append({
            "symbol":         q.symbol,
            "price":          q.price,
            "change_percent": q.change_percent,
            "change":         q.change,
            "volume":         q.volume,
            "market_cap":     q.market_cap,
            "asset_type":     "crypto" if _is_crypto_symbol(q.symbol) else "stock",
        })

    # Sort by absolute change desc
    results.sort(key=lambda x: abs(x["change_percent"] or 0), reverse=True)
    results = results[:limit]

    cache_manager.set(cache_key, results, ttl=120)  # 2 min
    return {"count": len(results), "results": results}


# ── Order Book ────────────────────────────────────────────────────────────────

import httpx as _httpx

@router.get("/orderbook/{symbol}")
async def get_orderbook(
    symbol: str,
    levels: int = Query(10, ge=1, le=20, description="Number of bid/ask levels"),
):
    """
    Live order-book snapshot.
    • Crypto  → Binance REST depth (top N bids + asks with size).
    • Stocks  → BBO only (best bid/ask from quote; no full book without premium feed).
    Returns:
      {
        symbol, is_crypto, spread, spread_pct,
        bids: [{price, size}],   # best first (highest bid)
        asks: [{price, size}],   # best first (lowest ask)
        bid_total, ask_total,    # total quantity in returned levels
        buy_pressure_pct,        # bid_total / (bid_total + ask_total) * 100
        timestamp_ms
      }
    """
    sym = symbol.upper()
    cache_key = f"orderbook:{sym}:{levels}"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    import time as _time
    ts = int(_time.time() * 1000)

    if _is_crypto_symbol(sym):
        # ── Binance depth endpoint ──────────────────────────────────────────
        binance_sym = sym + "USDT" if not sym.endswith("USDT") else sym
        url = f"https://api.binance.com/api/v3/depth?symbol={binance_sym}&limit={levels}"
        try:
            async with _httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(url)
                resp.raise_for_status()
                data = resp.json()
            bids = [{"price": float(b[0]), "size": float(b[1])} for b in data.get("bids", [])]
            asks = [{"price": float(a[0]), "size": float(a[1])} for a in data.get("asks", [])]
        except Exception as e:
            logger.warning(f"[orderbook] Binance depth failed for {sym}: {e}")
            # Fallback: return empty book
            bids, asks = [], []
    else:
        # ── Stock: BBO from quote ───────────────────────────────────────────
        quote = await data_fetcher.get_quote(sym)
        if quote and quote.price:
            spread_est = round(quote.price * 0.0002, 4)  # ~0.02% synthetic spread
            bid_px = round(quote.price - spread_est / 2, 4)
            ask_px = round(quote.price + spread_est / 2, 4)
            bids = [{"price": bid_px, "size": None}]
            asks = [{"price": ask_px, "size": None}]
        else:
            bids, asks = [], []

    # ── Compute summary stats ───────────────────────────────────────────────
    best_bid = bids[0]["price"] if bids else None
    best_ask = asks[0]["price"] if asks else None
    spread     = round(best_ask - best_bid, 6) if (best_bid and best_ask) else None
    spread_pct = round(spread / best_ask * 100, 4) if (spread and best_ask) else None

    bid_total = sum(b["size"] for b in bids if b["size"] is not None)
    ask_total = sum(a["size"] for a in asks if a["size"] is not None)
    total = bid_total + ask_total
    buy_pressure = round(bid_total / total * 100, 1) if total > 0 else 50.0

    result = {
        "symbol":           sym,
        "is_crypto":        _is_crypto_symbol(sym),
        "spread":           spread,
        "spread_pct":       spread_pct,
        "bids":             bids,
        "asks":             asks,
        "bid_total":        bid_total,
        "ask_total":        ask_total,
        "buy_pressure_pct": buy_pressure,
        "timestamp_ms":     ts,
    }

    ttl = 3 if _is_crypto_symbol(sym) else 15  # crypto: 3s, stocks: 15s
    cache_manager.set(cache_key, result, ttl=ttl)
    return result
