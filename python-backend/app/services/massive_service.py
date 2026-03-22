"""Massive.com (formerly Polygon.io) Market Data Service"""

import aiohttp
from typing import Optional, List
from datetime import datetime, timedelta
import logging

from app.models.stock import Quote, Candle, StockInfo
from app.config import settings

logger = logging.getLogger(__name__)

BASE_URL = "https://api.massive.com"


class MassiveService:
    """Fetches quotes, candles, and stock info from Massive.com API"""

    def __init__(self):
        self.api_key = settings.MASSIVE_API_KEY

    @property
    def is_configured(self) -> bool:
        return bool(self.api_key)

    # ── Quotes ────────────────────────────────────────────────────────────────

    async def get_quote(self, symbol: str) -> Optional[Quote]:
        """Snapshot quote for a stock or crypto symbol"""
        if not self.is_configured:
            return None
        try:
            if _is_crypto(symbol):
                return await self._crypto_quote(symbol)
            return await self._stock_quote(symbol)
        except Exception as e:
            logger.error(f"Massive quote error for {symbol}: {e}")
            return None

    async def _stock_quote(self, symbol: str) -> Optional[Quote]:
        url = (
            f"{BASE_URL}/v2/snapshot/locale/us/markets/stocks/tickers/{symbol}"
            f"?apiKey={self.api_key}"
        )
        async with aiohttp.ClientSession() as session:
            async with session.get(url) as resp:
                if resp.status != 200:
                    logger.warning(f"Massive stock snapshot {symbol}: HTTP {resp.status}")
                    return None
                data = await resp.json()

        ticker = data.get("ticker", {})
        if not ticker:
            return None

        day = ticker.get("day", {})
        prev = ticker.get("prevDay", {})
        price = day.get("c") or ticker.get("lastTrade", {}).get("p")
        prev_close = prev.get("c", 0)
        change = (price - prev_close) if price and prev_close else 0
        change_pct = ticker.get("todaysChangePerc", (change / prev_close * 100) if prev_close else 0)

        return Quote(
            symbol=symbol,
            price=float(price or 0),
            change=float(change),
            change_percent=float(change_pct),
            volume=int(day.get("v", 0)),
            high=float(day.get("h", 0)) or None,
            low=float(day.get("l", 0)) or None,
            open=float(day.get("o", 0)) or None,
            previous_close=float(prev_close) or None,
            timestamp=datetime.utcnow(),
        )

    async def _crypto_quote(self, symbol: str) -> Optional[Quote]:
        # Convert BTC-USD → X:BTCUSD format
        pair = symbol.replace("-", "").replace("/", "")
        url = (
            f"{BASE_URL}/v2/snapshot/locale/global/markets/crypto/tickers/X:{pair}"
            f"?apiKey={self.api_key}"
        )
        async with aiohttp.ClientSession() as session:
            async with session.get(url) as resp:
                if resp.status != 200:
                    logger.warning(f"Massive crypto snapshot {symbol}: HTTP {resp.status}")
                    return None
                data = await resp.json()

        ticker = data.get("ticker", {})
        if not ticker:
            return None

        day = ticker.get("day", {})
        prev = ticker.get("prevDay", {})
        price = day.get("c")
        prev_close = prev.get("c", 0)
        change = (price - prev_close) if price and prev_close else 0
        change_pct = ticker.get("todaysChangePerc", (change / prev_close * 100) if prev_close else 0)

        return Quote(
            symbol=symbol,
            price=float(price or 0),
            change=float(change),
            change_percent=float(change_pct),
            volume=int(day.get("v", 0)),
            high=float(day.get("h", 0)) or None,
            low=float(day.get("l", 0)) or None,
            open=float(day.get("o", 0)) or None,
            previous_close=float(prev_close) or None,
            timestamp=datetime.utcnow(),
        )

    # ── Candles ───────────────────────────────────────────────────────────────

    async def get_candles(
        self, symbol: str, interval: str = "1d", limit: int = 200
    ) -> List[Candle]:
        """OHLCV aggregates. interval: 1m 5m 15m 1h 4h 1d 1wk"""
        if not self.is_configured:
            return []
        try:
            multiplier, timespan = _parse_interval(interval)
            from_date, to_date = _date_range(timespan, limit)

            if _is_crypto(symbol):
                pair = symbol.replace("-", "").replace("/", "")
                ticker_path = f"X:{pair}"
            else:
                ticker_path = symbol

            url = (
                f"{BASE_URL}/v2/aggs/ticker/{ticker_path}/range"
                f"/{multiplier}/{timespan}/{from_date}/{to_date}"
                f"?adjusted=true&sort=asc&limit={limit}&apiKey={self.api_key}"
            )

            async with aiohttp.ClientSession() as session:
                async with session.get(url) as resp:
                    if resp.status != 200:
                        logger.warning(f"Massive aggs {symbol}: HTTP {resp.status}")
                        return []
                    data = await resp.json()

            results = data.get("results", [])
            candles = []
            for r in results:
                ts = datetime.utcfromtimestamp(r["t"] / 1000)
                candles.append(Candle(
                    symbol=symbol,
                    timestamp=ts,
                    open=float(r["o"]),
                    high=float(r["h"]),
                    low=float(r["l"]),
                    close=float(r["c"]),
                    volume=int(r.get("v", 0)),
                ))

            logger.info(f"Massive: {len(candles)} candles for {symbol} ({interval})")
            return candles

        except Exception as e:
            logger.error(f"Massive candles error for {symbol}: {e}")
            return []

    # ── Stock Info ────────────────────────────────────────────────────────────

    async def get_stock_info(self, symbol: str) -> Optional[StockInfo]:
        """Company details from Massive ticker details endpoint"""
        if not self.is_configured or _is_crypto(symbol):
            return None
        try:
            url = f"{BASE_URL}/v3/reference/tickers/{symbol}?apiKey={self.api_key}"
            async with aiohttp.ClientSession() as session:
                async with session.get(url) as resp:
                    if resp.status != 200:
                        return None
                    data = await resp.json()

            result = data.get("results", {})
            if not result:
                return None

            return StockInfo(
                symbol=symbol,
                name=result.get("name", symbol),
                exchange=result.get("primary_exchange"),
                currency=result.get("currency_name", "USD").upper(),
                sector=result.get("sic_description"),
                market_cap=result.get("market_cap"),
                description=result.get("description"),
                website=result.get("homepage_url"),
                employees=result.get("total_employees"),
            )
        except Exception as e:
            logger.error(f"Massive stock info error for {symbol}: {e}")
            return None


# ── Helpers ────────────────────────────────────────────────────────────────────

def _is_crypto(symbol: str) -> bool:
    return "-" in symbol or "/" in symbol or symbol.upper() in {"BTC", "ETH", "BNB", "XRP", "SOL"}


def _parse_interval(interval: str):
    """Return (multiplier, timespan) for Massive aggregates"""
    mapping = {
        "1m":  (1,  "minute"),
        "5m":  (5,  "minute"),
        "15m": (15, "minute"),
        "30m": (30, "minute"),
        "1h":  (1,  "hour"),
        "4h":  (4,  "hour"),
        "1d":  (1,  "day"),
        "1wk": (1,  "week"),
        "1mo": (1,  "month"),
    }
    return mapping.get(interval, (1, "day"))


def _date_range(timespan: str, limit: int):
    """Return (from_date, to_date) strings based on timespan + limit"""
    now = datetime.utcnow()
    if timespan == "minute":
        delta = timedelta(days=7)
    elif timespan == "hour":
        delta = timedelta(days=60)
    elif timespan == "day":
        delta = timedelta(days=max(limit * 1.5, 365))
    elif timespan == "week":
        delta = timedelta(weeks=max(limit * 2, 104))
    else:
        delta = timedelta(days=365 * 3)

    from_dt = now - delta
    return from_dt.strftime("%Y-%m-%d"), now.strftime("%Y-%m-%d")
