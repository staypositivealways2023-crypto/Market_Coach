"""Market Data Fetcher - Multi-source data aggregation"""

import asyncio
import aiohttp
import yfinance as yf
from typing import Optional, List
from datetime import datetime, timedelta
import logging

from app.models.stock import Quote, Candle, StockInfo
from app.config import settings
from app.utils.rate_limiter import APIRateLimiter
from app.utils.cache import cache_manager
from app.services.massive_service import MassiveService

logger = logging.getLogger(__name__)


class MarketDataFetcher:
    """Fetches market data from multiple sources with fallback"""

    def __init__(self):
        self.alpha_vantage_key = settings.ALPHA_VANTAGE_API_KEY
        self.finnhub_key = settings.FINNHUB_API_KEY
        self.massive = MassiveService()

        # Rate limiters
        self.av_limiter = APIRateLimiter(max_requests=settings.ALPHA_VANTAGE_RATE_LIMIT)
        self.fh_limiter = APIRateLimiter(max_requests=settings.FINNHUB_RATE_LIMIT)

    async def get_quote(self, symbol: str) -> Optional[Quote]:
        """Get real-time quote with fallback strategy"""

        # Check cache first
        cache_key = f"quote:{symbol}"
        cached = cache_manager.get(cache_key)
        if cached:
            logger.info(f"Quote cache hit for {symbol}")
            return Quote(**cached)

        is_crypto = _is_crypto_symbol(symbol)
        quote = None

        # 1. Massive.com (primary — handles both stocks and crypto)
        if self.massive.is_configured:
            quote = await self.massive.get_quote(symbol)
            if quote:
                logger.info(f"Fetched quote for {symbol} from Massive")

        # 2. Fallback: Finnhub (stocks only — doesn't support crypto well)
        if not quote and not is_crypto and self.finnhub_key and self.fh_limiter.can_proceed():
            quote = await self._fetch_finnhub_quote(symbol)
            if quote:
                logger.info(f"Fetched quote for {symbol} from Finnhub")

        # 3. Fallback: Alpha Vantage (stocks only)
        if not quote and not is_crypto and self.alpha_vantage_key and self.av_limiter.can_proceed():
            quote = await self._fetch_alpha_vantage_quote(symbol)
            if quote:
                logger.info(f"Fetched quote for {symbol} from Alpha Vantage")

        # 4. Last resort: yfinance (maps crypto to Yahoo format, e.g. BTC → BTC-USD)
        if not quote:
            quote = await self._fetch_yfinance_quote(symbol)
            if quote:
                logger.info(f"Fetched quote for {symbol} from yfinance")

        if quote:
            cache_manager.set(cache_key, quote.model_dump(), ttl=settings.QUOTE_CACHE_TTL)

        return quote

    async def get_candles(
        self,
        symbol: str,
        interval: str = "1d",
        limit: int = 100
    ) -> List[Candle]:
        """Get historical candles"""

        cache_key = f"candles:{symbol}:{interval}:{limit}"
        cached = cache_manager.get(cache_key)
        if cached:
            logger.info(f"Candles cache hit for {symbol}")
            return [Candle(**c) for c in cached]

        candles: List[Candle] = []

        # 1. Massive.com (primary)
        if self.massive.is_configured:
            candles = await self.massive.get_candles(symbol, interval, limit)
            if candles:
                logger.info(f"Fetched {len(candles)} candles for {symbol} from Massive")

        # 2. Fallback: yfinance
        if not candles:
            candles = await self._fetch_yfinance_candles(symbol, interval, limit)
            if candles:
                logger.info(f"Fetched {len(candles)} candles for {symbol} from yfinance")

        if candles:
            cache_manager.set(
                cache_key,
                [c.model_dump() for c in candles],
                ttl=settings.CANDLE_CACHE_TTL
            )

        return candles

    async def get_stock_info(self, symbol: str) -> Optional[StockInfo]:
        """Get detailed stock information"""

        cache_key = f"info:{symbol}"
        cached = cache_manager.get(cache_key)
        if cached:
            return StockInfo(**cached)

        info: Optional[StockInfo] = None

        # 1. Massive.com (richer company data)
        if self.massive.is_configured:
            info = await self.massive.get_stock_info(symbol)

        # 2. Fallback: yfinance
        if not info:
            info = await self._fetch_yfinance_info(symbol)

        if info:
            cache_manager.set(cache_key, info.model_dump(), ttl=3600)

        return info

    # ===== Finnhub Methods =====

    async def _fetch_finnhub_quote(self, symbol: str) -> Optional[Quote]:
        """Fetch quote from Finnhub"""
        try:
            url = f"https://finnhub.io/api/v1/quote?symbol={symbol}&token={self.finnhub_key}"

            async with aiohttp.ClientSession() as session:
                async with session.get(url) as response:
                    if response.status == 200:
                        data = await response.json()

                        if data.get('c') is None:
                            return None

                        current = data['c']
                        previous = data['pc']
                        change = current - previous
                        change_percent = (change / previous * 100) if previous else 0

                        return Quote(
                            symbol=symbol,
                            price=current,
                            change=change,
                            change_percent=change_percent,
                            high=data.get('h'),
                            low=data.get('l'),
                            open=data.get('o'),
                            previous_close=previous,
                            timestamp=datetime.utcnow()
                        )
        except Exception as e:
            logger.error(f"Finnhub error for {symbol}: {e}")

        return None

    # ===== Alpha Vantage Methods =====

    async def _fetch_alpha_vantage_quote(self, symbol: str) -> Optional[Quote]:
        """Fetch quote from Alpha Vantage"""
        try:
            url = (
                f"https://www.alphavantage.co/query?"
                f"function=GLOBAL_QUOTE&symbol={symbol}&apikey={self.alpha_vantage_key}"
            )

            async with aiohttp.ClientSession() as session:
                async with session.get(url) as response:
                    if response.status == 200:
                        data = await response.json()

                        if 'Global Quote' not in data:
                            return None

                        quote_data = data['Global Quote']

                        if not quote_data:
                            return None

                        return Quote(
                            symbol=symbol,
                            price=float(quote_data['05. price']),
                            change=float(quote_data['09. change']),
                            change_percent=float(quote_data['10. change percent'].rstrip('%')),
                            volume=int(quote_data.get('06. volume', 0)),
                            high=float(quote_data.get('03. high', 0)),
                            low=float(quote_data.get('04. low', 0)),
                            open=float(quote_data.get('02. open', 0)),
                            previous_close=float(quote_data.get('08. previous close', 0)),
                            timestamp=datetime.utcnow()
                        )
        except Exception as e:
            logger.error(f"Alpha Vantage error for {symbol}: {e}")

        return None

    # ===== yfinance Methods =====

    async def _fetch_yfinance_quote(self, symbol: str) -> Optional[Quote]:
        """Fetch quote from yfinance (fallback, run in executor)"""
        def _sync_fetch():
            try:
                yf_symbol = _to_yfinance_symbol(symbol)
                ticker = yf.Ticker(yf_symbol)
                info = ticker.info or {}

                # Price: info keys differ between stocks and crypto
                price = (
                    info.get('regularMarketPrice')
                    or info.get('currentPrice')
                    or info.get('ask')         # crypto sometimes uses ask
                )
                # fast_info.last_price is reliable for both stocks and crypto
                if not price:
                    try:
                        price = ticker.fast_info.last_price
                    except Exception:
                        pass
                if not price:
                    return None

                previous_close = (
                    info.get('previousClose')
                    or info.get('regularMarketPreviousClose')
                    or 0
                )
                change = float(price) - float(previous_close)
                change_percent = (change / float(previous_close) * 100) if previous_close else 0

                # High/Low: stocks use dayHigh/dayLow; crypto uses regularMarketDayHigh/Low
                high = (
                    info.get('dayHigh')
                    or info.get('regularMarketDayHigh')
                )
                low = (
                    info.get('dayLow')
                    or info.get('regularMarketDayLow')
                )

                return Quote(
                    symbol=symbol,
                    price=float(price),
                    change=float(change),
                    change_percent=float(change_percent),
                    volume=info.get('volume') or info.get('regularMarketVolume'),
                    market_cap=info.get('marketCap'),
                    pe_ratio=info.get('trailingPE'),
                    high=float(high) if high else None,
                    low=float(low) if low else None,
                    open=info.get('regularMarketOpen') or info.get('open'),
                    previous_close=float(previous_close),
                    timestamp=datetime.utcnow()
                )
            except Exception as e:
                logger.error(f"yfinance quote error for {symbol}: {e}")
                return None

        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, _sync_fetch)

    async def _fetch_yfinance_candles(
        self,
        symbol: str,
        interval: str,
        limit: int
    ) -> List[Candle]:
        """Fetch historical candles from yfinance (run in executor to avoid blocking)"""
        def _sync_fetch():
            try:
                period_map = {
                    "1m":  "1d",
                    "5m":  "5d",
                    "15m": "5d",
                    "1h":  "1mo",
                    "4h":  "3mo",
                    "1d":  "2y",
                    "1wk": "5y",
                }
                period = period_map.get(interval, "2y")
                yf_symbol = _to_yfinance_symbol(symbol)
                ticker = yf.Ticker(yf_symbol)
                hist = ticker.history(period=period, interval=interval)

                if hist.empty:
                    logger.warning(f"yfinance returned empty history for {symbol} ({interval})")
                    return []

                candles = []
                for index, row in hist.iterrows():
                    candles.append(Candle(
                        symbol=symbol,
                        timestamp=index.to_pydatetime().replace(tzinfo=None),
                        open=float(row['Open']),
                        high=float(row['High']),
                        low=float(row['Low']),
                        close=float(row['Close']),
                        volume=int(row['Volume'])
                    ))

                result = candles[-limit:] if len(candles) > limit else candles
                logger.info(f"yfinance: {len(result)} candles for {symbol} ({interval})")
                return result
            except Exception as e:
                logger.error(f"yfinance candles error for {symbol}: {e}")
                return []

        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, _sync_fetch)

    async def _fetch_yfinance_info(self, symbol: str) -> Optional[StockInfo]:
        """Fetch stock info from yfinance"""
        try:
            ticker = yf.Ticker(symbol)
            info = ticker.info

            if not info:
                return None

            return StockInfo(
                symbol=symbol,
                name=info.get('longName', symbol),
                exchange=info.get('exchange'),
                currency=info.get('currency', 'USD'),
                sector=info.get('sector'),
                industry=info.get('industry'),
                market_cap=info.get('marketCap'),
                description=info.get('longBusinessSummary'),
                website=info.get('website'),
                employees=info.get('fullTimeEmployees'),
                pe_ratio=info.get('trailingPE'),
                pb_ratio=info.get('priceToBook'),
                dividend_yield=info.get('dividendYield'),
                eps=info.get('trailingEps'),
                beta=info.get('beta'),
                revenue=info.get('totalRevenue'),
                profit_margin=info.get('profitMargins'),
                operating_margin=info.get('operatingMargins'),
                roe=info.get('returnOnEquity'),
                debt_to_equity=info.get('debtToEquity')
            )
        except Exception as e:
            logger.error(f"yfinance info error for {symbol}: {e}")
            return None


# ── Helpers ───────────────────────────────────────────────────────────────────

_CRYPTO_SYMBOLS = {
    "BTC", "ETH", "BNB", "SOL", "ADA", "XRP", "DOGE",
    "DOT", "AVAX", "MATIC", "LINK", "UNI", "LTC", "BCH", "XLM",
}


def _is_crypto_symbol(symbol: str) -> bool:
    return "-" in symbol or "/" in symbol or symbol.upper() in _CRYPTO_SYMBOLS


def _to_yfinance_symbol(symbol: str) -> str:
    """Map internal symbol to Yahoo Finance format.
    BTC → BTC-USD, ETH → ETH-USD, BTC-USD → BTC-USD (already correct).
    """
    s = symbol.upper()
    if "-" in s or "/" in s:
        return s.replace("/", "-")  # already has quote currency
    if s in _CRYPTO_SYMBOLS:
        return f"{s}-USD"
    return s  # regular stock ticker unchanged
