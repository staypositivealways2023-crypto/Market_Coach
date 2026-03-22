"""Internal endpoints for scheduled jobs and admin tasks"""

from fastapi import APIRouter, HTTPException, BackgroundTasks
from pydantic import BaseModel
from typing import List, Optional
import logging

from app.services.data_fetcher import MarketDataFetcher
from app.services.indicator_service import TechnicalIndicatorService
from app.services.valuation_service import ValuationService
from app.services.firestore_writer import FirestoreWriter

logger = logging.getLogger(__name__)
router = APIRouter()

# Service instances
data_fetcher = MarketDataFetcher()
indicator_service = TechnicalIndicatorService()
valuation_service = ValuationService()
firestore_writer = FirestoreWriter()


class RefreshRequest(BaseModel):
    """Request to refresh watchlist data"""
    symbols: Optional[List[str]] = None
    include_indicators: bool = True
    include_candles: bool = True
    include_valuation: bool = False


class RefreshResponse(BaseModel):
    """Response from refresh operation"""
    success: bool
    processed: int
    failed: List[str]
    message: str


async def refresh_symbol_data(
    symbol: str,
    include_indicators: bool,
    include_candles: bool,
    include_valuation: bool
) -> bool:
    """Refresh all data for a single symbol"""

    try:
        logger.info(f"Refreshing data for {symbol}")

        # 1. Fetch quote
        quote = await data_fetcher.get_quote(symbol)
        if quote:
            await firestore_writer.write_quote(quote)
        else:
            logger.warning(f"Failed to fetch quote for {symbol}")
            return False

        # 2. Fetch stock info
        info = await data_fetcher.get_stock_info(symbol)
        if info:
            await firestore_writer.write_stock_info(info)

        # 3. Fetch candles if requested
        if include_candles:
            candles = await data_fetcher.get_candles(symbol, interval="1d", limit=200)
            if candles:
                await firestore_writer.write_candles(symbol, candles)

                # 4. Calculate indicators if we have candles
                if include_indicators:
                    indicators = indicator_service.calculate_indicators(
                        symbol=symbol,
                        candles=candles,
                        current_price=quote.price
                    )
                    if indicators:
                        await firestore_writer.write_indicators(indicators)

        # 5. Calculate valuation if requested
        if include_valuation:
            dcf = await valuation_service.calculate_dcf(symbol)
            if dcf:
                await firestore_writer.write_dcf_valuation(dcf)

            metrics = await valuation_service.calculate_metrics(symbol)
            if metrics:
                await firestore_writer.write_valuation_metrics(metrics)

        logger.info(f"Successfully refreshed {symbol}")
        return True

    except Exception as e:
        logger.error(f"Error refreshing {symbol}: {e}")
        return False


@router.post("/refresh-watchlist", response_model=RefreshResponse)
async def refresh_watchlist(
    request: RefreshRequest,
    background_tasks: BackgroundTasks
):
    """
    Refresh market data for watchlist symbols

    This endpoint is designed to be called by scheduled jobs (e.g., Cloud Scheduler)
    to keep Firestore data up-to-date.
    """

    # Get symbols to refresh
    if request.symbols:
        symbols = request.symbols
    else:
        symbols = await firestore_writer.get_watchlist()

    if not symbols:
        raise HTTPException(status_code=400, detail="No symbols to refresh")

    logger.info(f"Starting watchlist refresh for {len(symbols)} symbols")

    # Process symbols
    processed = 0
    failed = []

    for symbol in symbols:
        success = await refresh_symbol_data(
            symbol=symbol,
            include_indicators=request.include_indicators,
            include_candles=request.include_candles,
            include_valuation=request.include_valuation
        )

        if success:
            processed += 1
        else:
            failed.append(symbol)

    return RefreshResponse(
        success=len(failed) == 0,
        processed=processed,
        failed=failed,
        message=f"Refreshed {processed}/{len(symbols)} symbols"
    )


@router.post("/refresh-symbol/{symbol}")
async def refresh_single_symbol(
    symbol: str,
    include_indicators: bool = True,
    include_candles: bool = True,
    include_valuation: bool = False
):
    """Refresh data for a single symbol"""

    success = await refresh_symbol_data(
        symbol=symbol,
        include_indicators=include_indicators,
        include_candles=include_candles,
        include_valuation=include_valuation
    )

    if not success:
        raise HTTPException(status_code=500, detail=f"Failed to refresh {symbol}")

    return {"success": True, "symbol": symbol, "message": "Data refreshed successfully"}


@router.get("/health")
async def internal_health():
    """Internal health check with service status"""

    return {
        "status": "healthy",
        "services": {
            "data_fetcher": "operational",
            "indicator_service": "operational",
            "valuation_service": "operational",
            "firestore_writer": "operational" if firestore_writer.db else "unavailable"
        }
    }
