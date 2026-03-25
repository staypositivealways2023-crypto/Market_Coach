"""Market data endpoints"""

from fastapi import APIRouter, HTTPException, Query
from typing import List, Optional
import asyncio
import logging

from app.services.data_fetcher import MarketDataFetcher
from app.models.stock import Quote, Candle, StockInfo
from app.utils.cache import cache_manager

logger = logging.getLogger(__name__)
router = APIRouter()

# Service instance
data_fetcher = MarketDataFetcher()


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

    # Fetch quote (day high/low) + 365 days of daily candles (year range) in parallel
    quote, candles = await asyncio.gather(
        data_fetcher.get_quote(sym),
        data_fetcher.get_candles(sym, interval="1d", limit=365),
    )

    year_high = max((c.high for c in candles), default=None) if candles else None
    year_low  = min((c.low  for c in candles), default=None) if candles else None

    # day high/low: prefer quote fields; fall back to most recent candle
    # (yfinance crypto quotes sometimes omit dayHigh/dayLow)
    day_high = quote.high if quote else None
    day_low  = quote.low  if quote else None
    if (day_high is None or day_low is None) and candles:
        last = candles[-1]
        day_high = day_high or last.high
        day_low  = day_low  or last.low

    logger.info(
        f"[range] {sym} → price={quote.price if quote else None} "
        f"day_high={day_high} day_low={day_low} "
        f"year_high={year_high} year_low={year_low} "
        f"candles={len(candles)} quote={'ok' if quote else 'MISSING'}"
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
