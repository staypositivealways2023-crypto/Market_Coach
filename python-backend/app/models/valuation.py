"""Valuation Models"""

from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class DCFValuation(BaseModel):
    """Discounted Cash Flow valuation"""
    symbol: str
    intrinsic_value: float = Field(..., description="Calculated intrinsic value per share")
    current_price: float = Field(..., description="Current market price")
    upside_percent: float = Field(..., description="Upside/downside percentage")

    # DCF inputs
    fcf: float = Field(..., description="Free cash flow")
    growth_rate: float = Field(..., description="Assumed growth rate")
    terminal_growth: float = Field(..., description="Terminal growth rate")
    wacc: float = Field(..., description="Weighted average cost of capital")
    shares_outstanding: Optional[float] = None

    # Valuation signals
    signal: str = Field(..., description="undervalued|overvalued|fair")
    confidence: str = Field(..., description="high|medium|low")

    timestamp: datetime = Field(default_factory=datetime.utcnow)

    class Config:
        json_schema_extra = {
            "example": {
                "symbol": "AAPL",
                "intrinsic_value": 195.50,
                "current_price": 175.43,
                "upside_percent": 11.45,
                "fcf": 100000000000,
                "growth_rate": 0.08,
                "terminal_growth": 0.03,
                "wacc": 0.09,
                "shares_outstanding": 15500000000,
                "signal": "undervalued",
                "confidence": "medium",
                "timestamp": "2026-02-08T10:30:00Z"
            }
        }


class ValuationMetrics(BaseModel):
    """Comparative valuation metrics"""
    symbol: str

    # Price ratios
    pe_ratio: Optional[float] = None
    pb_ratio: Optional[float] = None
    ps_ratio: Optional[float] = None
    peg_ratio: Optional[float] = None

    # Profitability
    roe: Optional[float] = None
    roa: Optional[float] = None
    profit_margin: Optional[float] = None
    operating_margin: Optional[float] = None

    # Financial health
    debt_to_equity: Optional[float] = None
    current_ratio: Optional[float] = None
    quick_ratio: Optional[float] = None

    # Growth
    revenue_growth: Optional[float] = None
    earnings_growth: Optional[float] = None

    # Dividend
    dividend_yield: Optional[float] = None
    payout_ratio: Optional[float] = None

    # Valuation signals
    value_score: Optional[float] = Field(None, ge=0, le=100, description="Overall value score (0-100)")
    grade: Optional[str] = Field(None, description="A|B|C|D|F")

    timestamp: datetime = Field(default_factory=datetime.utcnow)

    class Config:
        json_schema_extra = {
            "example": {
                "symbol": "AAPL",
                "pe_ratio": 28.5,
                "pb_ratio": 45.2,
                "ps_ratio": 7.8,
                "peg_ratio": 2.1,
                "roe": 0.147,
                "roa": 0.267,
                "profit_margin": 0.258,
                "operating_margin": 0.308,
                "debt_to_equity": 1.96,
                "current_ratio": 0.93,
                "revenue_growth": 0.082,
                "earnings_growth": 0.135,
                "dividend_yield": 0.0052,
                "payout_ratio": 0.15,
                "value_score": 72.5,
                "grade": "B",
                "timestamp": "2026-02-08T10:30:00Z"
            }
        }
