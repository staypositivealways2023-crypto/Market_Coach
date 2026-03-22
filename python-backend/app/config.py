"""Application Configuration using Pydantic Settings"""

from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import List
import os


class Settings(BaseSettings):
    """Application settings with environment variable support"""

    # Environment
    ENVIRONMENT: str = "development"
    DEBUG: bool = True

    # API Keys
    MASSIVE_API_KEY: str = ""  # Massive.com (formerly Polygon.io)
    FRED_API_KEY: str = ""    # FRED macro data — free at fred.stlouisfed.org/docs/api/api_key.html
    ALPHA_VANTAGE_API_KEY: str = ""
    FINNHUB_API_KEY: str = ""
    ANTHROPIC_API_KEY: str = ""

    # AI Analysis Settings
    USE_MOCK_ANALYSIS: bool = False  # Set to True to use mock analysis without API calls

    # Firebase
    FIREBASE_PROJECT_ID: str = ""
    FIREBASE_CREDENTIALS_PATH: str = ""
    FIREBASE_CREDENTIALS_JSON: str = ""  # base64-encoded service account JSON (used in production/Railway)

    # API Rate Limits (requests per minute)
    ALPHA_VANTAGE_RATE_LIMIT: int = 5
    FINNHUB_RATE_LIMIT: int = 60

    # Cache Settings
    CACHE_TTL_SECONDS: int = 300  # 5 minutes
    QUOTE_CACHE_TTL: int = 60     # 1 minute for quotes
    CANDLE_CACHE_TTL: int = 300   # 5 minutes for candles

    # CORS
    CORS_ORIGINS: List[str] = ["*"]

    # Watchlist
    DEFAULT_WATCHLIST: List[str] = [
        "AAPL", "GOOGL", "MSFT", "AMZN", "TSLA",
        "NVDA", "META", "BTC-USD", "ETH-USD"
    ]

    # Indicator Settings
    RSI_PERIOD: int = 14
    MACD_FAST: int = 12
    MACD_SLOW: int = 26
    MACD_SIGNAL: int = 9
    BOLLINGER_PERIOD: int = 20
    BOLLINGER_STD: int = 2

    # Valuation Settings
    RISK_FREE_RATE: float = 0.045  # 4.5% (10-year Treasury)
    MARKET_RISK_PREMIUM: float = 0.08  # 8% historical average

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore"
    )


# Create global settings instance
settings = Settings()
