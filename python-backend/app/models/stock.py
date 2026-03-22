"""Stock Data Models"""

from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class Quote(BaseModel):
    """Real-time stock quote"""
    symbol: str
    price: float = Field(..., description="Current price")
    change: float = Field(..., description="Price change")
    change_percent: float = Field(..., description="Percentage change")
    volume: Optional[int] = None
    market_cap: Optional[float] = None
    pe_ratio: Optional[float] = None
    high: Optional[float] = None
    low: Optional[float] = None
    open: Optional[float] = None
    previous_close: Optional[float] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)

    class Config:
        json_schema_extra = {
            "example": {
                "symbol": "AAPL",
                "price": 175.43,
                "change": 2.15,
                "change_percent": 1.24,
                "volume": 52487900,
                "market_cap": 2750000000000,
                "pe_ratio": 28.5,
                "high": 176.12,
                "low": 173.80,
                "open": 174.20,
                "previous_close": 173.28,
                "timestamp": "2026-02-08T10:30:00Z"
            }
        }


class Candle(BaseModel):
    """OHLCV candlestick data"""
    symbol: str
    timestamp: datetime
    open: float
    high: float
    low: float
    close: float
    volume: int

    class Config:
        json_schema_extra = {
            "example": {
                "symbol": "AAPL",
                "timestamp": "2026-02-08T10:00:00Z",
                "open": 174.20,
                "high": 175.50,
                "low": 173.80,
                "close": 175.43,
                "volume": 5248790
            }
        }


class StockInfo(BaseModel):
    """Detailed stock information"""
    symbol: str
    name: str
    exchange: Optional[str] = None
    currency: Optional[str] = "USD"
    sector: Optional[str] = None
    industry: Optional[str] = None
    market_cap: Optional[float] = None
    description: Optional[str] = None
    website: Optional[str] = None
    ceo: Optional[str] = None
    employees: Optional[int] = None

    # Fundamental metrics
    pe_ratio: Optional[float] = None
    pb_ratio: Optional[float] = None
    dividend_yield: Optional[float] = None
    eps: Optional[float] = None
    beta: Optional[float] = None

    # Financial data
    revenue: Optional[float] = None
    profit_margin: Optional[float] = None
    operating_margin: Optional[float] = None
    roe: Optional[float] = None
    debt_to_equity: Optional[float] = None

    class Config:
        json_schema_extra = {
            "example": {
                "symbol": "AAPL",
                "name": "Apple Inc.",
                "exchange": "NASDAQ",
                "currency": "USD",
                "sector": "Technology",
                "industry": "Consumer Electronics",
                "market_cap": 2750000000000,
                "pe_ratio": 28.5,
                "pb_ratio": 45.2,
                "dividend_yield": 0.52,
                "eps": 6.15,
                "beta": 1.24
            }
        }
