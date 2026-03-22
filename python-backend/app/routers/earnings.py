"""Earnings endpoints — historical EPS + upcoming earnings date"""

from fastapi import APIRouter, HTTPException, Query
import logging

from app.services.earnings_service import EarningsService
from app.utils.cache import cache_manager

logger = logging.getLogger(__name__)
router = APIRouter()

earnings_svc = EarningsService()


@router.get("/{symbol}")
async def get_earnings(
    symbol: str,
    limit: int = Query(8, ge=1, le=20, description="Quarters of history"),
):
    """
    Upcoming earnings date + historical quarterly EPS for a ticker.
    Returns: upcoming (date, eps_estimate, revenue_estimate) + history (8 quarters).
    """
    sym = symbol.upper()
    cache_key = f"earnings:{sym}:{limit}"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    data = await earnings_svc.get_earnings_summary(sym, history_limit=limit)

    if not data["history"] and not data["upcoming"]["earnings_date"]:
        raise HTTPException(status_code=404, detail=f"No earnings data for {symbol}")

    cache_manager.set(cache_key, data, ttl=3600 * 6)  # 6hr cache — earnings dates rarely change
    return data
