"""Backtest router — run portfolio backtests via the backtest engine."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from typing import List
import logging

from app.services.backtest_engine import BacktestHolding, run_portfolio_backtest

logger = logging.getLogger(__name__)
router = APIRouter()


class HoldingInput(BaseModel):
    symbol: str = Field(..., description="Ticker symbol, e.g. AAPL or BTC")
    shares: float = Field(..., gt=0, description="Number of shares/units held")
    avg_cost: float = Field(..., gt=0, description="Average cost per share/unit")


class BacktestRequest(BaseModel):
    holdings: List[HoldingInput] = Field(..., min_items=1)
    period: str = Field("1y", description="Backtest period: 1mo | 3mo | 6mo | 1y | 2y | 5y")
    initial_value: float = Field(10000.0, gt=0, description="Hypothetical starting portfolio value")


_VALID_PERIODS = {"1mo", "3mo", "6mo", "1y", "2y", "5y"}


@router.post("/run")
async def run_backtest(req: BacktestRequest):
    """
    Run a portfolio backtest.
    Returns equity curve, total return, annualised return, max drawdown,
    volatility, and Sharpe ratio for the given holdings and period.
    """
    if req.period not in _VALID_PERIODS:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid period '{req.period}'. Valid options: {sorted(_VALID_PERIODS)}",
        )

    holdings = [
        BacktestHolding(
            symbol=h.symbol.upper(),
            shares=h.shares,
            avg_cost=h.avg_cost,
        )
        for h in req.holdings
    ]

    try:
        result = run_portfolio_backtest(
            holdings=holdings,
            period=req.period,
            initial_value=req.initial_value,
        )
        return result
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    except Exception as exc:
        logger.exception("Backtest error for %s", [h.symbol for h in req.holdings])
        raise HTTPException(status_code=500, detail=f"Backtest failed: {exc}")
