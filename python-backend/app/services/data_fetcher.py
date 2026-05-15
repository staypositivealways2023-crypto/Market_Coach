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
        # Hard timeout of 5 s: if Binance is unreachable the batch fails fast
        # and crypto symbols fall through to the individual yfinance fallback,
        # which must complete before Flutter's 15 s HTTP timeout fires.
        if crypto_syms:
            try:
                binance_batch = await asyncio.wait_for(
                    self._fetch_binance_quotes_batch(crypto_syms),
                    timeout=5.0,
                )
            except asyncio.TimeoutError:
                logger.warning(
                    f"[quotes] Binance batch timed out for {crypto_syms} — "
                    "falling back to individual yfinance"
                )
                binance_batch = {}
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
        stale_cache_key = f"candles_stale:{symbol}:{interval}:{limit}"
        cached = cache_manager.get(cache_key)
        if cached:
            logger.info(
                "[CandleProvider] symbol=%s interval=%s provider=cache returned=%s",
                symbol,
                interval,
                len(cached),
            )
            logger.info(
                "[CandleEndpoint] symbol=%s interval=%s requested=%s returned=%s source=cache",
                symbol,
                interval,
                limit,
                len(cached),
            )
            return [Candle(**c) for c in cached]

        candles: List[Candle] = []
        source = ""
        min_rows = _min_expected_candles(interval, limit)

        # 1. Massive.com (primary)
        if self.massive.is_configured:
            try:
                candles = await asyncio.wait_for(
                    self.massive.get_candles(symbol, interval, limit),
                    timeout=4.0,
                )
            except asyncio.TimeoutError:
                logger.warning(
                    "Massive candles timed out for %s (%s); falling back",
                    symbol,
                    interval,
                )
                logger.warning(
                    "[CandleProvider] symbol=%s interval=%s provider=polygon failed reason=timeout",
                    symbol,
                    interval,
                )
            except Exception as e:
                logger.warning(
                    "[CandleProvider] symbol=%s interval=%s provider=polygon failed reason=%s",
                    symbol,
                    interval,
                    type(e).__name__,
                )
            if candles:
                logger.info(
                    "[CandleProvider] symbol=%s interval=%s provider=polygon returned=%s",
                    symbol,
                    interval,
                    len(candles),
                )
                if len(candles) >= min_rows:
                    source = "polygon"
                else:
                    logger.warning(
                        "[CandleProvider] symbol=%s interval=%s provider=polygon failed reason=too_few returned=%s minExpected=%s",
                        symbol,
                        interval,
                        len(candles),
                        min_rows,
                    )
                    candles = []
            else:
                logger.warning(
                    "[CandleProvider] symbol=%s interval=%s provider=polygon failed reason=empty",
                    symbol,
                    interval,
                )
        else:
            logger.info(
                "[CandleProvider] symbol=%s interval=%s provider=polygon failed reason=unconfigured",
                symbol,
                interval,
            )

        # 2. Fallback: yfinance
        if not candles:
            try:
                candles = await asyncio.wait_for(
                    self._fetch_yfinance_candles(symbol, interval, limit),
                    timeout=3.0,
                )
            except asyncio.TimeoutError:
                logger.warning("yfinance candles timed out for %s (%s)", symbol, interval)
                logger.warning(
                    "[CandleProvider] symbol=%s interval=%s provider=yfinance failed reason=timeout",
                    symbol,
                    interval,
                )
            except Exception as e:
                logger.warning(
                    "[CandleProvider] symbol=%s interval=%s provider=yfinance failed reason=%s",
                    symbol,
                    interval,
                    type(e).__name__,
                )
            if candles:
                logger.info(
                    "[CandleProvider] symbol=%s interval=%s provider=yfinance returned=%s",
                    symbol,
                    interval,
                    len(candles),
                )
                if len(candles) >= min_rows:
                    source = "yfinance"
                else:
                    logger.warning(
                        "[CandleProvider] symbol=%s interval=%s provider=yfinance failed reason=too_few returned=%s minExpected=%s",
                        symbol,
                        interval,
                        len(candles),
                        min_rows,
                    )
                    candles = []
            else:
                logger.warning(
                    "[CandleProvider] symbol=%s interval=%s provider=yfinance failed reason=empty",
                    symbol,
                    interval,
                )

        # 3. Fallback: Yahoo chart API directly
        if not candles:
            try:
                candles = await self._fetch_yahoo_chart_api_candles(symbol, interval, limit)
            except Exception as e:
                logger.warning(
                    "[CandleProvider] symbol=%s interval=%s provider=yahoo_chart failed reason=%s",
                    symbol,
                    interval,
                    type(e).__name__,
                )
            if candles:
                logger.info(
                    "[CandleProvider] symbol=%s interval=%s provider=yahoo_chart returned=%s",
                    symbol,
                    interval,
                    len(candles),
                )
                source = "yahoo_chart"
            else:
                logger.warning(
                    "[CandleProvider] symbol=%s interval=%s provider=yahoo_chart failed reason=empty",
                    symbol,
                    interval,
                )

        if candles:
            payload = [c.model_dump() for c in candles]
            cache_manager.set(
                cache_key,
                payload,
                ttl=settings.CANDLE_CACHE_TTL
            )
            cache_manager.set(stale_cache_key, payload, ttl=86400)
            logger.info(
                "[CandleEndpoint] symbol=%s interval=%s requested=%s returned=%s source=%s",
                symbol,
                interval,
                limit,
                len(candles),
                source,
            )
        else:
            stale = cache_manager.get(stale_cache_key)
            if stale:
                logger.warning(
                    "Returning stale candles for %s (%s) after provider failure",
                    symbol,
                    interval,
                )
                logger.info(
                    "[CandleProvider] symbol=%s interval=%s provider=cache returned=%s warning=provider_timeout",
                    symbol,
                    interval,
                    len(stale),
                )
                logger.info(
                    "[CandleEndpoint] symbol=%s interval=%s requested=%s returned=%s source=stale_cache warning=provider_timeout",
                    symbol,
                    interval,
                    limit,
                    len(stale),
                )
                return [Candle(**c) for c in stale]

            logger.error(
                "[CandleEndpoint] symbol=%s interval=%s requested=%s returned=0 source=none",
                symbol,
                interval,
                limit,
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
                # quoteVolume = USD-denominated volume; much more useful than base-asset volume
                volume=int(float(data.get("quoteVolume") or 0)),
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

            # Binance requires the symbols param to be a URL-encoded JSON array.
            # Using aiohttp params dict ensures proper percent-encoding of [ ] " chars.
            symbols_json = json.dumps(list(sym_map.keys()))

            async with aiohttp.ClientSession() as session:
                async with session.get(
                    "https://api.binance.com/api/v3/ticker/24hr",
                    params={"symbols": symbols_json},
                    timeout=aiohttp.ClientTimeout(total=10),
                ) as resp:
                    if resp.status != 200:
                        body = await resp.text()
                        logger.warning(f"[binance] batch HTTP {resp.status}: {body[:120]}")
                        # Fall back to individual calls so at least some quotes land
                        return await self._fetch_binance_individual_fallback(sym_map)
                    data = await resp.json()

            if not isinstance(data, list):
                logger.warning(f"[binance] batch unexpected response type {type(data)}")
                return await self._fetch_binance_individual_fallback(sym_map)

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
                    volume=int(float(item.get("quoteVolume") or 0)),  # quoteVolume = USD-denominated
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

    async def _fetch_binance_individual_fallback(self, sym_map: Dict[str, str]) -> Dict[str, Quote]:
        """Per-symbol Binance fallback when the batch call fails."""
        results: Dict[str, Quote] = {}
        for binance_sym, our_sym in sym_map.items():
            try:
                quote = await self._fetch_binance_quote(our_sym)
                if quote:
                    results[our_sym] = quote
            except Exception:
                pass
        return results

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

                def _clean_int(v):
                    f = _clean(v)
                    return int(f) if f is not None else None

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
                volume = None
                market_cap = None
                pe_ratio = None
                open_price = None

                if fi:
                    price = _clean(getattr(fi, "last_price", None))
                    previous_close = _clean(getattr(fi, "previous_close", None))
                    high = _clean(getattr(fi, "day_high", None))
                    low  = _clean(getattr(fi, "day_low",  None))
                    volume = _clean_int(getattr(fi, "last_volume", None))
                    market_cap = _clean(getattr(fi, "market_cap", None))

                # --- ticker.info fills fields fast_info often omits (volume, cap, PE, open) ---
                info: dict = {}
                needs_info = (
                    not price or
                    volume is None or
                    market_cap is None or
                    pe_ratio is None or
                    open_price is None or
                    previous_close is None or
                    high is None or
                    low is None
                )
                if needs_info:
                    try:
                        info = ticker.info or {}
                        price = price or _clean(
                            info.get("regularMarketPrice")
                            or info.get("currentPrice")
                            or info.get("ask")
                        )
                        previous_close = previous_close or _clean(
                            info.get("previousClose")
                            or info.get("regularMarketPreviousClose")
                        )
                        high = high or _clean(info.get("dayHigh") or info.get("regularMarketDayHigh"))
                        low  = low  or _clean(info.get("dayLow")  or info.get("regularMarketDayLow"))
                        volume = volume or _clean_int(
                            info.get("volume") or info.get("regularMarketVolume")
                        )
                        market_cap = market_cap or info.get("marketCap")
                        pe_ratio = info.get("trailingPE")
                        open_price = _clean(info.get("regularMarketOpen") or info.get("open"))
                    except Exception:
                        logger.debug(f"[yfinance] ticker.info unavailable for {symbol}")

                if not price:
                    return None

                missing = [
                    name for name, value in {
                        "volume": volume,
                        "market_cap": market_cap,
                        "pe_ratio": pe_ratio,
                        "open": open_price,
                    }.items()
                    if value is None
                ]
                if missing:
                    logger.debug(
                        "[yfinance] quote %s missing fields after fallback: %s",
                        symbol,
                        ",".join(missing),
                    )

                prev = float(previous_close or 0)
                change = float(price) - prev
                change_pct = (change / prev * 100) if prev else 0

                return Quote(
                    symbol=symbol,
                    price=float(price),
                    change=change,
                    change_percent=change_pct,
                    volume=volume,
                    market_cap=market_cap,
                    pe_ratio=pe_ratio,
                    high=high,
                    low=low,
                    open=open_price,
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
                    "1m":  "5d",
                    "5m":  "30d",
                    "15m": "60d",
                    "30m": "60d",
                    "1h":  "2y",
                    "2h":  "2y",
                    "4h":  "2y",
                    "12h": "2y",
                    "1d":  "5y",
                    "1wk": "10y",
                    "1mo": "max",
                }
                base_interval_map = {
                    "2h": "1h",
                    "4h": "1h",
                    "12h": "1h",
                }
                aggregate_hours = {
                    "2h": 2,
                    "4h": 4,
                    "12h": 12,
                }
                # Normalise unsupported intervals; fall back to "1y" not "2y"
                # (avoids "No data found" errors for short intraday frames).
                period = period_map.get(interval, "1y")
                yf_interval = base_interval_map.get(interval, interval)
                logger.info(
                    "[CandleRange] interval=%s period=%s providerInterval=%s provider=yfinance",
                    interval,
                    period,
                    yf_interval,
                )
                yf_symbol = _to_yfinance_symbol(symbol)
                ticker = yf.Ticker(yf_symbol)
                hist = ticker.history(period=period, interval=yf_interval)

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

                if interval in aggregate_hours:
                    source_rows = len(candles)
                    candles = _aggregate_hourly_candles(candles, aggregate_hours[interval])
                    logger.info(
                        "[CandleAggregate] sourceInterval=1h targetInterval=%s sourceRows=%s aggregatedRows=%s",
                        interval,
                        source_rows,
                        len(candles),
                    )

                candles = _sort_candles(candles)
                result = candles[-limit:] if len(candles) > limit else candles
                logger.info(
                    "[CandleEndpoint] symbol=%s interval=%s requestedLimit=%s provider=yfinance rawRows=%s returned=%s",
                    symbol,
                    interval,
                    limit,
                    len(candles),
                    len(result),
                )
                return result
            except Exception as e:
                logger.error(
                    "[CandleError] provider=yfinance interval=%s error=%s",
                    interval,
                    e,
                )
                return []

        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, _sync_fetch)

    async def _fetch_yahoo_chart_api_candles(
        self,
        symbol: str,
        interval: str,
        limit: int,
    ) -> List[Candle]:
        """Fetch candles directly from Yahoo chart API with short timeout."""
        range_map = {
            "1m": "5d",
            "5m": "30d",
            "15m": "60d",
            "30m": "60d",
            "1h": "2y",
            "2h": "2y",
            "4h": "2y",
            "12h": "2y",
            "1d": "5y",
            "1wk": "10y",
            "1mo": "max",
        }
        base_interval_map = {
            "2h": "1h",
            "4h": "1h",
            "12h": "1h",
        }
        aggregate_hours = {
            "2h": 2,
            "4h": 4,
            "12h": 12,
        }

        yf_symbol = _to_yfinance_symbol(symbol)
        yf_interval = base_interval_map.get(interval, interval)
        yf_range = range_map.get(interval, "5y")
        logger.info(
            "[CandleRange] interval=%s period=%s providerInterval=%s provider=yahoo_chart",
            interval,
            yf_range,
            yf_interval,
        )
        url = f"https://query2.finance.yahoo.com/v8/finance/chart/{yf_symbol}"
        params = {
            "interval": yf_interval,
            "range": yf_range,
            "includePrePost": "false",
        }
        headers = {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/124.0.0.0 Safari/537.36"
            ),
            "Accept": "application/json",
            "Accept-Language": "en-US,en;q=0.9",
            "Origin": "https://finance.yahoo.com",
            "Referer": "https://finance.yahoo.com/",
        }

        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(
                    url,
                    params=params,
                    headers=headers,
                    timeout=aiohttp.ClientTimeout(total=7.0),
                ) as resp:
                    if resp.status != 200:
                        logger.warning(
                            "[CandleProvider] symbol=%s interval=%s provider=yahoo_chart failed reason=http_%s",
                            symbol,
                            interval,
                            resp.status,
                        )
                        return []
                    data = await resp.json()
        except asyncio.TimeoutError:
            logger.warning(
                "[CandleProvider] symbol=%s interval=%s provider=yahoo_chart failed reason=timeout",
                symbol,
                interval,
            )
            return []

        result = ((data.get("chart") or {}).get("result") or [None])[0]
        if not result:
            return []
        timestamps = result.get("timestamp") or []
        quote = (((result.get("indicators") or {}).get("quote") or [None])[0]) or {}
        opens = quote.get("open") or []
        highs = quote.get("high") or []
        lows = quote.get("low") or []
        closes = quote.get("close") or []
        volumes = quote.get("volume") or []

        candles: List[Candle] = []
        for i, ts in enumerate(timestamps):
            close = closes[i] if i < len(closes) else None
            if close is None:
                continue
            open_ = opens[i] if i < len(opens) and opens[i] is not None else close
            high = highs[i] if i < len(highs) and highs[i] is not None else close
            low = lows[i] if i < len(lows) and lows[i] is not None else close
            volume = volumes[i] if i < len(volumes) and volumes[i] is not None else 0
            candles.append(Candle(
                symbol=symbol,
                timestamp=datetime.utcfromtimestamp(int(ts)),
                open=float(open_),
                high=float(high),
                low=float(low),
                close=float(close),
                volume=int(float(volume or 0)),
            ))

        if interval in aggregate_hours:
            source_rows = len(candles)
            candles = _aggregate_hourly_candles(candles, aggregate_hours[interval])
            logger.info(
                "[CandleAggregate] sourceInterval=1h targetInterval=%s sourceRows=%s aggregatedRows=%s",
                interval,
                source_rows,
                len(candles),
            )

        candles = _sort_candles(candles)
        result_candles = candles[-limit:] if len(candles) > limit else candles
        logger.info(
            "[CandleEndpoint] symbol=%s interval=%s requestedLimit=%s provider=yahoo_chart rawRows=%s returned=%s",
            symbol,
            interval,
            limit,
            len(candles),
            len(result_candles),
        )
        return result_candles

    async def _fetch_yfinance_info(self, symbol: str) -> Optional[StockInfo]:
        """Fetch stock info from yfinance"""
        try:
            info = await asyncio.to_thread(lambda: yf.Ticker(symbol).info)

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


def _min_expected_candles(interval: str, limit: int) -> int:
    if limit <= 0:
        return 1
    if interval == "1mo":
        return min(limit, 192)
    if interval == "1wk":
        return min(limit, 240)
    return min(limit, 400)


def _sort_candles(candles: List[Candle]) -> List[Candle]:
    return sorted(candles, key=lambda c: c.timestamp)


def _aggregate_hourly_candles(candles: List[Candle], hours: int) -> List[Candle]:
    """Aggregate Yahoo 1h candles into supported 2h/4h/12h bars."""
    if hours <= 1 or not candles:
        return candles

    buckets: Dict[datetime, List[Candle]] = {}
    for candle in candles:
        ts = candle.timestamp.replace(minute=0, second=0, microsecond=0)
        bucket_hour = (ts.hour // hours) * hours
        bucket_start = ts.replace(hour=bucket_hour)
        buckets.setdefault(bucket_start, []).append(candle)

    aggregated: List[Candle] = []
    for bucket_start in sorted(buckets):
        bucket = sorted(buckets[bucket_start], key=lambda c: c.timestamp)
        if not bucket:
            continue
        aggregated.append(Candle(
            symbol=bucket[0].symbol,
            timestamp=bucket_start,
            open=bucket[0].open,
            high=max(c.high for c in bucket),
            low=min(c.low for c in bucket),
            close=bucket[-1].close,
            volume=sum(c.volume for c in bucket),
        ))

    return aggregated
