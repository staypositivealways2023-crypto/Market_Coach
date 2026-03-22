"""Macro economic data endpoints — FRED API"""

from fastapi import APIRouter, HTTPException, Query
from typing import List
import logging

from app.services.fred_service import FredService, SERIES
from app.utils.cache import cache_manager

logger = logging.getLogger(__name__)
router = APIRouter()

fred = FredService()


@router.get("/overview")
async def get_macro_overview():
    """
    All key macro indicators in one call:
    fed_funds_rate, cpi, inflation_yoy, yield_curve, unemployment, gdp_growth, dxy
    """
    cache_key = "macro:overview"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    data = await fred.get_macro_overview()
    cache_manager.set(cache_key, data, ttl=3600)  # 1 hour — macro data is slow moving
    return data


@router.get("/series/{series_key}")
async def get_series_history(
    series_key: str,
    limit: int = Query(24, ge=1, le=120, description="Number of data points")
):
    """
    Historical data for a specific macro indicator.
    series_key: fed_funds_rate | cpi | inflation_yoy | yield_curve | unemployment | gdp_growth | dxy
    """
    if series_key not in SERIES:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown series key '{series_key}'. Valid keys: {list(SERIES.keys())}"
        )

    cache_key = f"macro:series:{series_key}:{limit}"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    series_id = SERIES[series_key]
    data = await fred.get_series_history(series_id, limit=limit)

    if not data:
        raise HTTPException(status_code=503, detail="FRED data unavailable")

    result = {"series_key": series_key, "series_id": series_id, "data": data}
    cache_manager.set(cache_key, result, ttl=3600)
    return result
