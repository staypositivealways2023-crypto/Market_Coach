"""Technical Indicator Models"""

from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime


class RSIData(BaseModel):
    """RSI (Relative Strength Index) data"""
    value: float = Field(..., ge=0, le=100, description="RSI value (0-100)")
    signal: str = Field(..., description="overbought|oversold|neutral")
    timestamp: datetime = Field(default_factory=datetime.utcnow)

    class Config:
        json_schema_extra = {
            "example": {
                "value": 67.5,
                "signal": "neutral",
                "timestamp": "2026-02-08T10:30:00Z"
            }
        }


class MACDData(BaseModel):
    """MACD (Moving Average Convergence Divergence) data"""
    macd: float = Field(..., description="MACD line")
    signal: float = Field(..., description="Signal line")
    histogram: float = Field(..., description="MACD histogram")
    trend: str = Field(..., description="bullish|bearish|neutral")
    timestamp: datetime = Field(default_factory=datetime.utcnow)

    class Config:
        json_schema_extra = {
            "example": {
                "macd": 1.25,
                "signal": 0.85,
                "histogram": 0.40,
                "trend": "bullish",
                "timestamp": "2026-02-08T10:30:00Z"
            }
        }


class BollingerBandsData(BaseModel):
    """Bollinger Bands data"""
    upper: float = Field(..., description="Upper band")
    middle: float = Field(..., description="Middle band (SMA)")
    lower: float = Field(..., description="Lower band")
    percent_b: Optional[float] = Field(None, description="Position within bands")
    bandwidth: Optional[float] = Field(None, description="Band width")
    timestamp: datetime = Field(default_factory=datetime.utcnow)

    class Config:
        json_schema_extra = {
            "example": {
                "upper": 178.50,
                "middle": 175.00,
                "lower": 171.50,
                "percent_b": 0.55,
                "bandwidth": 4.0,
                "timestamp": "2026-02-08T10:30:00Z"
            }
        }


class TechnicalIndicators(BaseModel):
    """Complete technical indicators for a symbol"""
    symbol: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)

    # Indicators
    rsi: Optional[RSIData] = None
    macd: Optional[MACDData] = None
    bollinger_bands: Optional[BollingerBandsData] = None

    # Moving averages
    sma_20: Optional[float] = None
    sma_50: Optional[float] = None
    sma_200: Optional[float] = None
    ema_12: Optional[float] = None
    ema_26: Optional[float] = None

    # Price vs MA signals
    price: Optional[float] = None
    above_sma_20: Optional[bool] = None
    above_sma_50: Optional[bool] = None
    above_sma_200: Optional[bool] = None

    class Config:
        json_schema_extra = {
            "example": {
                "symbol": "AAPL",
                "timestamp": "2026-02-08T10:30:00Z",
                "rsi": {
                    "value": 67.5,
                    "signal": "neutral"
                },
                "macd": {
                    "macd": 1.25,
                    "signal": 0.85,
                    "histogram": 0.40,
                    "trend": "bullish"
                },
                "bollinger_bands": {
                    "upper": 178.50,
                    "middle": 175.00,
                    "lower": 171.50,
                    "percent_b": 0.55,
                    "bandwidth": 4.0
                },
                "sma_20": 175.00,
                "sma_50": 172.30,
                "sma_200": 168.50,
                "price": 175.43,
                "above_sma_20": True,
                "above_sma_50": True,
                "above_sma_200": True
            }
        }
