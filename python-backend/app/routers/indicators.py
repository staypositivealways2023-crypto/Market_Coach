"""Technical indicators endpoints"""

from fastapi import APIRouter, HTTPException, Query
import logging

from app.services.data_fetcher import MarketDataFetcher
from app.services.indicator_service import TechnicalIndicatorService
from app.services.valuation_service import ValuationService
from app.models.indicator import TechnicalIndicators
from app.models.valuation import DCFValuation, ValuationMetrics

logger = logging.getLogger(__name__)
router = APIRouter()

# Service instances
data_fetcher = MarketDataFetcher()
indicator_service = TechnicalIndicatorService()
valuation_service = ValuationService()


@router.get("/{symbol}", response_model=TechnicalIndicators)
async def get_indicators(
    symbol: str,
    period: int = Query(100, ge=50, le=500, description="Historical period for calculation")
):
    """Calculate technical indicators for a symbol"""

    symbol = symbol.upper()

    # Fetch candles
    candles = await data_fetcher.get_candles(symbol, interval="1d", limit=period)

    if not candles:
        raise HTTPException(
            status_code=404,
            detail=f"Unable to fetch candles for {symbol}"
        )

    # Get current quote for price
    quote = await data_fetcher.get_quote(symbol)
    current_price = quote.price if quote else None

    # Calculate indicators
    indicators = indicator_service.calculate_indicators(
        symbol=symbol,
        candles=candles,
        current_price=current_price
    )

    if not indicators:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to calculate indicators for {symbol}"
        )

    return indicators


@router.get("/valuation/dcf/{symbol}", response_model=DCFValuation)
async def get_dcf_valuation(symbol: str):
    """Calculate DCF valuation for a symbol"""

    dcf = await valuation_service.calculate_dcf(symbol.upper())

    if not dcf:
        raise HTTPException(
            status_code=404,
            detail=f"Unable to calculate DCF for {symbol}"
        )

    return dcf


@router.get("/valuation/metrics/{symbol}", response_model=ValuationMetrics)
async def get_valuation_metrics(symbol: str):
    """Get valuation metrics for a symbol"""

    metrics = await valuation_service.calculate_metrics(symbol.upper())

    if not metrics:
        raise HTTPException(
            status_code=404,
            detail=f"Unable to fetch metrics for {symbol}"
        )

    return metrics
