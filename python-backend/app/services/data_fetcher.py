"""Market Data Fetcher - Multi-source data aggregation

Provider priority (per asset class):
  Crypto  : Binance (free, 1200 req/min) → Polygon → yfinance [semaphore-throttled]
  Stocks  : Polygon → Finnhub → Alpha Vantage → yfinance [semaphore-throttled]
"""

import asyncio
import aiohttp
import json
import math
import yfinance as yf
from typing import Optional, List, Dict
from datetime import datetime, timedelta
import logging

from app.models.stock import Quote, Candle, StockInfo
from app.config import settings
from app.utils.rate_limiter import APIRateLimiter
from app.utils.cache import cache_manager
from app.services.massive_service import MassiveService

logger = logging.getLogger(__name__)

# Limit concurrent yfinance calls to avoid Yahoo 429 storms.
# yfinance hits quoteSummary (unofficial Yahoo endpoint) — ~5 req/min IP limit.
_YF_SEMAPHORE = asyncio.Semaphore(2)


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
        """Get real-time quote with provider fallback chain."""

        cache_key = f"quote:{symbol}"
        cached = cache_manager.get(cache_key)
        if cached:
            logger.info(f"[quote] {symbol} cache hit")
            return Quote(**cached)

        is_crypto = _is_crypto_symbol(symbol)
        quote = None

        # ── 1. Binance (crypto-native, free public API, 1200 req/min) ────────
        if is_crypto:
            quote = await self._fetch_binance_quote(symbol)
            if quote:
                logger.info(
                    f"[quote] {symbol} provider=Binance "
                    f"price={quote.price} high={quote.high} low={quote.low}"
                )
            else:
                logger.warning(f"[quote] {symbol} Binance returned nothing")

        # ── 2. Polygon (stocks + crypto, requires MASSIVE_API_KEY) ───────────
        if not quote and self.massive.is_configured:
            quote = await self.massive.get_quote(symbol)
            if quote:
                logger.info(
                    f"[quote] {symbol} provider=Polygon "
                    f"price={quote.price} high={quote.high} low={quote.low}"
                )
            else:
                logger.warning(f"[quote] {symbol} Polygon returned nothing")

        # ── 3. Finnhub (stocks only) ──────────────────────────────────────────
        if not quote and not is_crypto and self.finnhub_key and self.fh_limiter.can_proceed():
            quote = await self._fetch_finnhub_quote(symbol)
            if quote:
                logger.info(
                    f"[quote] {symbol} provider=Finnhub "
                    f"price={quote.price} high={quote.high} low={quote.low}"
                )

        # ── 4. Alpha Vantage (stocks only, 5 req/min) ────────────────────────
        if not quote and not is_crypto and self.alpha_vantage_key and self.av_limiter.can_proceed():
            quote = await self._fetch_alpha_vantage_quote(symbol)
            if quote:
                logger.info(
                    f"[quote] {symbol} provider=AlphaVantage "
                    f"price={quote.price} high={quote.high} low={quote.low}"
                )

        # ── 5. yfinance (weak fallback — semaphore-throttled to avoid 429) ────
        if not quote:
            quote = await self._fetch_yfinance_quote(symbol)
            if quote:
                logger.info(
                    f"[quote] {symbol} provider=yfinance "
                    f"price={quote.price} high={quote.high} low={quote.low}"
                )
            else:
                logger.error(f"[quote] {symbol} ALL providers failed — returning None")

        if quote:
            cache_manager.set(cache_key, quote.model_dump(), ttl=settings.QUOTE_CACHE_TTL)

        return quote

    async def get_quotes_batch(self, symbols: List[str]) -> List[Quote]:
        """
        Efficient batch quote fetch.

        - Crypto  → Binance batch (one HTTP call for all crypto symbols)
        - Stocks  → Polygon batch (one HTTP call for all stock symbols)
        - Missing → individual fallback with per-symbol cache + yfinance semaphore

        All symbols served from per-symbol cache if warm.
        """
        results: Dict[str, Quote] = {}

        # Serve from cache first
        uncached: List[str] = []
        for sym in symbols:
            cached = cache_manager.get(f"quote:{sym}")
            if cached:
                results[sym] = Quote(**cached)
                logger.info(f"[quotes] {sym} cache hit")
            else:
                uncached.append(sym)

        if not uncached:
            return [results[s] for s in symbols if s in results]

        crypto_syms = [s for s in uncached if _is_crypto_symbol(s)]
        stock_syms  = [s for s in uncached if not _is_crypto_symbol(s)]

        # ── Binance batch for crypto ─────────────────────────────────────────
        if crypto_syms:
            binance_batch = await self._fetch_binance_quotes_batch(crypto_syms)
            for sym, q in binance_batch.items():
                results[sym] = q
                cache_manager.set(f"quote:{sym}", q.model_dump(), ttl=settings.QUOTE_CACHE_TTL)
                logger.info(f"[quotes] {sym} provider=Binance(batch) price={q.price}")

        # ── Polygon batch for stocks ─────────────────────────────────────────
        if stock_syms and self.massive.is_configured:
            polygon_batch = await self.massive.get_quotes_batch(stock_syms)
            for sym, q in polygon_batch.items():
                results[sym] = q
                cache_manager.set(f"quote:{sym}", q.model_dump(), ttl=settings.QUOTE_CACHE_TTL)
                logger.info(f"[quotes] {sym} provider=Polygon(batch) price={q.price}")

        # ── Individual fallback for anything still missing ────────────────────
        still_missing = [s for s in uncached if s not in results]
        if still_missing:
            logger.warning(
                f"[quotes] batch fallback for {len(still_missing)} symbols: {still_missing}"
            )
            fallback = await asyncio.gather(
                *[self.get_quote(s) for s in still_missing],
                return_exceptions=True,
            )
            for sym, r in zip(still_missing, fallback):
                if isinstance(r, Quote):
                    results[sym] = r

        return [results[s] for s in symbols if s in results]

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

    # ===== Binance Methods (crypto-native, no auth, 1200 req/min) =====

    async def _fetch_binance_quote(self, symbol: str) -> Optional[Quote]:
        """Fetch single crypto quote from Binance public API."""
        try:
            sym = symbol.upper()
            base = sym.split("-")[0].split("/")[0] if ("-" in sym or "/" in sym) else sym
            binance_sym = f"{base}USDT"
            url = f"https://api.binance.com/api/v3/ticker/24hr?symbol={binance_sym}"

            async with aiohttp.ClientSession() as session:
                async with session.get(url, timeout=aiohttp.ClientTimeout(total=8)) as resp:
                    if resp.status != 200:
                        logger.warning(f"[binance] {symbol} ({binance_sym}) HTTP {resp.status}")
                        return None
                    data = await resp.json()

            price = float(data.get("lastPrice") or 0)
            if not price:
                return None

            return Quote(
                symbol=symbol,
                price=price,
                change=float(data.get("priceChange") or 0),
                change_percent=float(data.get("priceChangePercent") or 0),
                volume=int(float(data.get("volume") or 0)),  # Binance volume is fractional BTC
                high=float(data.get("highPrice") or 0) or None,
                low=float(data.get("lowPrice") or 0) or None,
                open=float(data.get("openPrice") or 0) or None,
                previous_close=float(data.get("prevClosePrice") or 0) or None,
                timestamp=datetime.utcnow(),
            )
        except Exception as e:
            logger.warning(f"[binance] {symbol} error: {e}")
            return None

    async def _fetch_binance_quotes_batch(self, symbols: List[str]) -> Dict[str, Quote]:
        """Fetch multiple crypto quotes from Binance in one HTTP call."""
        if not symbols:
            return {}
        try:
            # Build Binance symbol → our symbol map
            sym_map: Dict[str, str] = {}  # BTCUSDT → BTC
            for s in symbols:
                sym = s.upper()
                base = sym.split("-")[0].split("/")[0] if ("-" in sym or "/" in sym) else sym
                if base in _CRYPTO_SYMBOLS:
                    sym_map[f"{base}USDT"] = s

            if not sym_map:
                return {}

            symbols_json = json.dumps(list(sym_map.keys()))
            url = f"https://api.binance.com/api/v3/ticker/24hr?symbols={symbols_json}"

            async with aiohttp.ClientSession() as session:
                async with session.get(url, timeout=aiohttp.ClientTimeout(total=10)) as resp:
                    if resp.status != 200:
                        body = await resp.text()
                        logger.warning(f"[binance] batch HTTP {resp.status}: {body[:120]}")
                        return {}
                    data = await resp.json()

            results: Dict[str, Quote] = {}
            for item in data:
                binance_sym = item.get("symbol", "")
                our_sym = sym_map.get(binance_sym)
                if not our_sym:
                    continue
                price = float(item.get("lastPrice") or 0)
                if not price:
                    continue
                results[our_sym] = Quote(
                    symbol=our_sym,
                    price=price,
                    change=float(item.get("priceChange") or 0),
                    change_percent=float(item.get("priceChangePercent") or 0),
                    volume=int(float(item.get("volume") or 0)),  # Binance volume is fractional
                    high=float(item.get("highPrice") or 0) or None,
                    low=float(item.get("lowPrice") or 0) or None,
                    open=float(item.get("openPrice") or 0) or None,
                    previous_close=float(item.get("prevClosePrice") or 0) or None,
                    timestamp=datetime.utcnow(),
                )

            logger.info(f"[binance] batch: {len(results)}/{len(sym_map)} crypto resolved")
            return results
        except Exception as e:
            logger.warning(f"[binance] batch error: {e}")
            return {}

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
        """
        Fetch quote from yfinance — weak fallback only.
        Semaphore-throttled to 2 concurrent calls to prevent Yahoo 429.
        Prefers fast_info (v7/quote, lighter) over ticker.info (quoteSummary, heavier).
        """
        def _sync_fetch():
            try:
                yf_symbol = _to_yfinance_symbol(symbol)
                ticker = yf.Ticker(yf_symbol)

                def _clean(v):
                    if v is None:
                        return None
                    try:
                        f = float(v)
                        return None if math.isnan(f) or math.isinf(f) else f
                    except (TypeError, ValueError):
                        return None

                # --- fast_info first (lighter Yahoo endpoint, less rate-limited) ---
                fi = None
                try:
                    fi = ticker.fast_info
                except Exception:
                    pass

                price = None
                previous_close = None
                high = None
                low = None

                if fi:
                    price = _clean(getattr(fi, "last_price", None))
                    previous_close = _clean(getattr(fi, "previous_close", None))
                    high = _clean(getattr(fi, "day_high", None))
                    low  = _clean(getattr(fi, "day_low",  None))

                # --- fall back to ticker.info (quoteSummary) only if fast_info missed price ---
                info: dict = {}
                if not price:
                    try:
                        info = ticker.info or {}
                        price = _clean(
                            info.get("regularMarketPrice")
                            or info.get("currentPrice")
                            or info.get("ask")
                        )
                        if not previous_close:
                            previous_close = _clean(
                                info.get("previousClose")
                                or info.get("regularMarketPreviousClose")
                            )
                        if not high:
                            high = _clean(info.get("dayHigh") or info.get("regularMarketDayHigh"))
                        if not low:
                            low  = _clean(info.get("dayLow")  or info.get("regularMarketDayLow"))
                    except Exception:
                        pass

                if not price:
                    return None

                prev = float(previous_close or 0)
                change = float(price) - prev
                change_pct = (change / prev * 100) if prev else 0

                return Quote(
                    symbol=symbol,
                    price=float(price),
                    change=change,
                    change_percent=change_pct,
                    volume=info.get("volume") or info.get("regularMarketVolume"),
                    market_cap=info.get("marketCap"),
                    pe_ratio=info.get("trailingPE"),
                    high=high,
                    low=low,
                    open=_clean(info.get("regularMarketOpen") or info.get("open")),
                    previous_close=prev or None,
                    timestamp=datetime.utcnow(),
                )
            except Exception as e:
                logger.error(f"[yfinance] quote error for {symbol}: {e}")
                return None

        # Semaphore prevents concurrent Yahoo calls from triggering IP-level 429
        async with _YF_SEMAPHORE:
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
