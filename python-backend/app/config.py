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
    OPENAI_API_KEY: str = ""

    # Reddit PRAW (Phase 4 — sentiment scraper)
    # Create a script app at https://www.reddit.com/prefs/apps
    REDDIT_CLIENT_ID: str = ""
    REDDIT_CLIENT_SECRET: str = ""
    REDDIT_USER_AGENT: str = "MarketCoach/1.0 by u/marketcoach_bot"

    # Redis (for voice session working memory and usage counters)
    REDIS_URL: str = "redis://localhost:6379"
    REDIS_TTL_SESSION: int = 10800   # 3 hours — live voice session state
    REDIS_TTL_USAGE: int = 3024000   # 35 days — billing period counter
    REDIS_TTL_CTX: int = 1800        # 30 minutes — active user context

    # AI Analysis Settings
    USE_MOCK_ANALYSIS: bool = False  # Set to True to use mock analysis without API calls

    # Firebase
    FIREBASE_PROJECT_ID: str = ""
    FIREBASE_CREDENTIALS_PATH: str = ""
    FIREBASE_CREDENTIALS_JSON: str = ""  # base64-encoded service account JSON (used in production/Railway)

    # Development auth bypass — decodes JWT without signature verification.
    # NEVER enable in production.  Set DEV_BYPASS_AUTH=true in .env for local dev.
    DEV_BYPASS_AUTH: bool = False

    # Jarvis local AI — set JARVIS_URL to the address of your running Jarvis API.
    # Default assumes both services run on the same machine.
    # Set JARVIS_URL=http://<host-ip>:7700 when running on separate machines.
    JARVIS_URL: str = "http://localhost:7700"
    JARVIS_TIMEOUT_SECONDS: int = 25

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

    # ── Analyst Cycle Upgrade ─────────────────────────────────────────────────

    # PostgreSQL + pgvector
    POSTGRES_HOST: str = "postgres"
    POSTGRES_PORT: int = 5432
    POSTGRES_DB: str = "marketcoach"
    POSTGRES_USER: str = "mcuser"
    POSTGRES_PASSWORD: str = ""

    @property
    def POSTGRES_DSN(self) -> str:
        return (
            f"postgresql://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}"
            f"@{self.POSTGRES_HOST}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"
        )

    # Cartesia TTS
    # API key: https://play.cartesia.ai → Settings → API Keys
    CARTESIA_API_KEY: str = ""
    # Voice: Dean persona — sonic-3 model (Cartesia-Version: 2026-03-01)
    CARTESIA_VOICE_ID: str = "a167e0f3-df7e-4d52-a9c3-f949145efdab"

    # Deepgram STT
    DEEPGRAM_API_KEY: str = ""

    # Ollama
    OLLAMA_BASE_URL: str = "http://ollama:11434"

    # Analyst Graph models & limits
    ANALYST_DEEPSEEK_MODEL: str = "deepseek-r1:14b"
    ANALYST_INTENT_MODEL: str = "mistral"
    ANALYST_EMBED_MODEL: str = "nomic-embed-text"
    ANALYST_MAX_REASONING_TOKENS: int = 1500
    ANALYST_VERIFICATION_THRESHOLD: float = 0.75
    ANALYST_MAX_RETRIES: int = 2

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore"
    )


# Create global settings instance
settings = Settings()
