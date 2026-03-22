"""Fundamental analysis endpoints"""

from fastapi import APIRouter, HTTPException
import logging

from app.services.fundamental_service import FundamentalService
from app.utils.cache import cache_manager

logger = logging.getLogger(__name__)
router = APIRouter()

fund_svc = FundamentalService()


@router.get("/{symbol}")
async def get_fundamentals(symbol: str):
    """
    Key financial ratios + TTM financials + quarterly EPS history.
    Stocks: P/E, P/S, margins, ROE, debt/equity, current ratio.
    Crypto: returns is_crypto=true with minimal data (no P/E).
    """
    sym = symbol.upper()
    cache_key = f"fundamentals:{sym}"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    data = await fund_svc.get_fundamentals(sym)

    if not data:
        raise HTTPException(status_code=404, detail=f"No fundamental data for {symbol}")

    # Cache 6hrs — fundamentals are quarterly, no need to refresh often
    cache_manager.set(cache_key, data, ttl=3600 * 6)
    return data
