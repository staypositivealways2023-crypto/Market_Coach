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
    interval: str = Query("1d", description="1m|5m|15m|30m|1h|2h|4h|12h|1d|1wk|1mo"),
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
            status_code=503,
            detail={
                "error": "candles_unavailable",
                "symbol": symbol.upper(),
                "interval": interval,
                "requested": limit,
                "message": "All candle providers failed and no stale cache is available.",
            },
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

        # Fallback: if quote didn't supply intraday high/low (e.g. yfinance
        # fallback path), derive them from the most recent daily candle.
        if day_high is None or day_low is None:
            candles = await data_fetcher.get_candles(sym, interval="1d", limit=2)
        else:
            candles = []

        if candles and (day_high is None or day_low is None):
            last = candles[-1]
            day_high = day_high or last.high
            day_low  = day_low  or last.low
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

from app.services.screener_service import run_screener


@router.get("/screener")
async def get_screener(
    min_change:     Optional[float] = Query(None, description="Min daily change % (e.g. 2.0)"),
    max_change:     Optional[float] = Query(None, description="Max daily change % (e.g. -2.0)"),
    asset_type:     str             = Query("all",            description="all|stock|crypto"),
    sector:         Optional[str]   = Query(None,             description="Tech|Finance|Healthcare|Energy|Consumer|ETF|Crypto"),
    signal:         Optional[str]   = Query(None,             description="OVERSOLD|OVERBOUGHT|NEUTRAL"),
    min_volume:     Optional[float] = Query(None,             description="Min daily volume"),
    min_market_cap: Optional[float] = Query(None,             description="Min market cap (USD)"),
    max_market_cap: Optional[float] = Query(None,             description="Max market cap (USD)"),
    sort_by:        str             = Query("change_percent", description="change_percent|volume|market_cap|rsi"),
    limit:          int             = Query(20, ge=1, le=50),
):
    """
    Multi-factor screener — filters by daily change, volume, market cap, sector,
    and RSI-based signal (OVERSOLD / OVERBOUGHT / NEUTRAL).

    RSI is computed per surviving symbol after the fast price/volume filters run,
    so the candle-fetch step only touches the filtered subset.
    Response is cached 5 minutes (RSI cache) + 2 minutes (result cache).
    """
    cache_key = (
        f"screener2:{asset_type}:{sector}:{signal}:{min_change}:{max_change}:"
        f"{min_volume}:{min_market_cap}:{max_market_cap}:{sort_by}:{limit}"
    )
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    results = await run_screener(
        asset_type=asset_type,
        sector=sector,
        min_change=min_change,
        max_change=max_change,
        min_volume=min_volume,
        min_market_cap=min_market_cap,
        max_market_cap=max_market_cap,
        signal=signal,
        sort_by=sort_by,
        limit=limit,
    )

    payload = {"count": len(results), "results": results}
    cache_manager.set(cache_key, payload, ttl=120)  # 2-min result cache
    return payload


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


# ── Fear & Greed Index ────────────────────────────────────────────────────────

import math as _math
import pandas as _pd
from ta.momentum import RSIIndicator as _RSIIndicator

@router.get("/fear-greed")
async def get_fear_greed():
    """
    Composite Fear & Greed index (0-100).

    Three components, equal weight:
      * VIX component  -- inverted VIX level (VIX 10->100pts, VIX 40->0pts)
      * Momentum       -- SPY RSI-14
      * Market position -- SPY price vs 52-week range (0-100%)

    Labels: 0-20 Extreme Fear, 20-40 Fear, 40-60 Neutral, 60-80 Greed, 80-100 Extreme Greed
    Cached 5 minutes.
    """
    cache_key = "fear_greed:v1"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    vix_quote, spy_candles = await asyncio.gather(
        data_fetcher.get_quote("VIX"),
        data_fetcher.get_candles("SPY", interval="1d", limit=252),
        return_exceptions=True,
    )

    components: dict = {}

    # VIX component
    vix_score: Optional[float] = None
    if isinstance(vix_quote, Quote) and vix_quote.price is not None:
        vix = float(vix_quote.price)
        vix_score = max(0.0, min(100.0, 100.0 - (vix - 10.0) * (100.0 / 30.0)))
        components["vix"] = {"value": round(vix, 2), "score": round(vix_score, 1)}

    # RSI component (SPY RSI-14)
    rsi_score: Optional[float] = None
    if isinstance(spy_candles, list) and len(spy_candles) >= 15:
        closes = _pd.Series([float(c.close) for c in spy_candles], dtype=float)
        rsi_val = _RSIIndicator(close=closes, window=14).rsi().iloc[-1]
        if not _math.isnan(rsi_val):
            rsi_score = float(rsi_val)
            components["momentum_rsi"] = {"value": round(rsi_score, 1), "score": round(rsi_score, 1)}

    # Market position -- SPY vs 52-week range
    position_score: Optional[float] = None
    if isinstance(spy_candles, list) and len(spy_candles) >= 20:
        hi52 = max(c.high for c in spy_candles)
        lo52 = min(c.low  for c in spy_candles)
        current = float(spy_candles[-1].close)
        if hi52 > lo52:
            position_score = (current - lo52) / (hi52 - lo52) * 100.0
            components["market_position"] = {
                "value": round(current, 2),
                "year_high": round(hi52, 2),
                "year_low": round(lo52, 2),
                "score": round(position_score, 1),
            }

    scores = [s for s in [vix_score, rsi_score, position_score] if s is not None]
    composite = round(sum(scores) / len(scores), 1) if scores else 50.0

    def _label(s: float) -> str:
        if s < 20: return "Extreme Fear"
        if s < 40: return "Fear"
        if s < 60: return "Neutral"
        if s < 80: return "Greed"
        return "Extreme Greed"

    payload = {
        "score":      composite,
        "label":      _label(composite),
        "components": components,
        "fetched_at": datetime.utcnow().isoformat(),
    }
    cache_manager.set(cache_key, payload, ttl=300)
    return payload


# ── Technical Alerts ──────────────────────────────────────────────────────────

@router.get("/technical-alerts")
async def get_technical_alerts(
    symbols: str = Query(
        "AAPL,MSFT,NVDA,GOOGL,AMZN,META,TSLA,NFLX,AMD,INTC,QCOM,AVGO,BTC,ETH,SOL,XRP",
        description="Comma-separated symbols to scan",
    ),
):
    """
    Scan symbols for triggered RSI and volume-spike alerts.

    Conditions:
      * RSI < 30  -> OVERSOLD
      * RSI > 70  -> OVERBOUGHT
      * Volume today > 2x 20-day avg -> VOLUME_SPIKE

    Cached 5 minutes.
    """
    sym_list = [s.strip().upper() for s in symbols.split(",") if s.strip()][:20]
    cache_key = f"tech_alerts:{','.join(sorted(sym_list))}"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    RSI_PERIOD   = 14
    CANDLE_LIMIT = 30

    async def _scan(sym: str) -> list:
        alerts = []
        try:
            candle_symbol = _to_yfinance_symbol(sym) if _is_crypto_symbol(sym) else sym
            quote, candles = await asyncio.gather(
                data_fetcher.get_quote(sym),
                data_fetcher.get_candles(candle_symbol, interval="1d", limit=CANDLE_LIMIT),
                return_exceptions=True,
            )
            if not isinstance(candles, list) or len(candles) < RSI_PERIOD + 2:
                return alerts

            closes  = _pd.Series([float(c.close) for c in candles], dtype=float)
            volumes = [float(c.volume) for c in candles if c.volume]

            rsi_series = _RSIIndicator(close=closes, window=RSI_PERIOD).rsi()
            rsi_val = float(rsi_series.iloc[-1]) if not _math.isnan(rsi_series.iloc[-1]) else None

            if rsi_val is not None:
                if rsi_val < 30:
                    alerts.append({
                        "symbol":    sym,
                        "type":      "OVERSOLD",
                        "condition": f"RSI {rsi_val:.1f} < 30",
                        "severity":  "high" if rsi_val < 25 else "medium",
                        "rsi":       round(rsi_val, 1),
                        "price":     float(candles[-1].close),
                    })
                elif rsi_val > 70:
                    alerts.append({
                        "symbol":    sym,
                        "type":      "OVERBOUGHT",
                        "condition": f"RSI {rsi_val:.1f} > 70",
                        "severity":  "high" if rsi_val > 80 else "medium",
                        "rsi":       round(rsi_val, 1),
                        "price":     float(candles[-1].close),
                    })

            if len(volumes) >= 21:
                today_vol  = volumes[-1]
                avg_vol_20 = sum(volumes[-21:-1]) / 20
                if avg_vol_20 > 0 and today_vol > 2 * avg_vol_20:
                    mult = today_vol / avg_vol_20
                    alerts.append({
                        "symbol":     sym,
                        "type":       "VOLUME_SPIKE",
                        "condition":  f"Volume {mult:.1f}x 20-day avg",
                        "severity":   "high" if mult > 3 else "medium",
                        "volume":     int(today_vol),
                        "avg_volume": int(avg_vol_20),
                        "multiplier": round(mult, 2),
                        "price":      float(candles[-1].close),
                    })
        except Exception as e:
            logger.warning(f"[tech-alerts] scan failed for {sym}: {e}")
        return alerts

    results_nested = await asyncio.gather(*[_scan(s) for s in sym_list], return_exceptions=True)

    all_alerts = []
    for item in results_nested:
        if isinstance(item, list):
            all_alerts.extend(item)

    severity_order = {"high": 0, "medium": 1}
    all_alerts.sort(key=lambda a: (severity_order.get(a["severity"], 2), a["symbol"]))

    payload = {
        "count":      len(all_alerts),
        "scanned":    len(sym_list),
        "alerts":     all_alerts,
        "fetched_at": datetime.utcnow().isoformat(),
    }
    cache_manager.set(cache_key, payload, ttl=300)
    return payload
