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
    """Get quotes for multiple symbols"""

    symbol_list = [s.strip().upper() for s in symbols.split(',')]

    quotes = []
    for symbol in symbol_list:
        quote = await data_fetcher.get_quote(symbol)
        if quote:
            quotes.append(quote)

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

    result = {
        "symbol": sym,
        "current_price": quote.price if quote else None,
        "day_high":      quote.high  if quote else None,
        "day_low":       quote.low   if quote else None,
        "open":          quote.open  if quote else None,
        "previous_close":quote.previous_close if quote else None,
        "volume":        quote.volume if quote else None,
        "year_high":     year_high,
        "year_low":      year_low,
    }

    cache_manager.set(cache_key, result, ttl=300)  # 5 min
    return result
