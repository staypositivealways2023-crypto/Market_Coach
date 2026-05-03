"""
Phase 5 — OrderBook Service

Fetches level-2 order book data:
  - Crypto  : Binance /api/v3/depth   (free, public, 1200 req/min)
  - Stocks  : Polygon snapshot / yfinance fallback (bid/ask spread only)

Returns a normalised OrderBookResult with bids[], asks[], spread, and
imbalance ratio (buy pressure vs sell pressure).
"""

import asyncio
import logging
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

import aiohttp

logger = logging.getLogger(__name__)

BINANCE_DEPTH_URL = "https://api.binance.com/api/v3/depth"
BINANCE_DEPTH_LIMIT = 20  # top 20 levels each side


@dataclass
class OrderLevel:
    price: float
    quantity: float
    total: float  # price × quantity (cumulative wall size in USD)


@dataclass
class OrderBookResult:
    symbol: str
    bids: List[OrderLevel] = field(default_factory=list)  # highest first
    asks: List[OrderLevel] = field(default_factory=list)  # lowest first
    spread: Optional[float] = None          # ask[0] - bid[0]
    spread_pct: Optional[float] = None      # spread / mid_price × 100
    mid_price: Optional[float] = None
    bid_volume: Optional[float] = None      # total qty on bid side (top 20)
    ask_volume: Optional[float] = None      # total qty on ask side (top 20)
    imbalance: Optional[float] = None       # bid_vol / (bid_vol + ask_vol) — >0.5 = buy pressure
    source: str = "unknown"


def _to_binance_symbol(symbol: str) -> str:
    """Convert internal symbol to Binance format (e.g. BTC → BTCUSDT)."""
    s = symbol.upper().replace("-", "").replace("/", "")
    if not s.endswith("USDT") and not s.endswith("BTC") and not s.endswith("ETH"):
        s = s + "USDT"
    return s


def _is_crypto(symbol: str) -> bool:
    crypto_bases = {
        "BTC", "ETH", "BNB", "SOL", "XRP", "ADA", "DOGE", "AVAX", "DOT",
        "MATIC", "LINK", "UNI", "ATOM", "LTC", "BCH", "ALGO", "XLM",
        "NEAR", "FTM", "SAND", "MANA", "CRO", "SHIB", "TRX", "ETC",
    }
    return symbol.upper().split("USDT")[0].split("-")[0] in crypto_bases


async def _fetch_binance_orderbook(symbol: str) -> Optional[OrderBookResult]:
    """Fetch order book from Binance public API."""
    bs = _to_binance_symbol(symbol)
    params = {"symbol": bs, "limit": BINANCE_DEPTH_LIMIT}

    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(
                BINANCE_DEPTH_URL, params=params, timeout=aiohttp.ClientTimeout(total=8)
            ) as resp:
                if resp.status != 200:
                    logger.warning("[orderbook] Binance %s → HTTP %d", bs, resp.status)
                    return None
                data = await resp.json()
    except Exception as e:
        logger.warning("[orderbook] Binance request failed: %s", e)
        return None

    raw_bids: List[Tuple] = data.get("bids", [])
    raw_asks: List[Tuple] = data.get("asks", [])

    if not raw_bids or not raw_asks:
        return None

    def _parse_levels(raw: List) -> List[OrderLevel]:
        levels = []
        for row in raw:
            try:
                p, q = float(row[0]), float(row[1])
                levels.append(OrderLevel(price=p, quantity=q, total=round(p * q, 2)))
            except (IndexError, ValueError):
                continue
        return levels

    bids = _parse_levels(raw_bids)
    asks = _parse_levels(raw_asks)

    best_bid = bids[0].price if bids else None
    best_ask = asks[0].price if asks else None

    spread = round(best_ask - best_bid, 6) if (best_bid and best_ask) else None
    mid = round((best_bid + best_ask) / 2, 6) if (best_bid and best_ask) else None
    spread_pct = round(spread / mid * 100, 4) if (spread and mid) else None

    bid_vol = round(sum(l.quantity for l in bids), 4)
    ask_vol = round(sum(l.quantity for l in asks), 4)
    total_vol = bid_vol + ask_vol
    imbalance = round(bid_vol / total_vol, 4) if total_vol > 0 else 0.5

    return OrderBookResult(
        symbol=symbol.upper(),
        bids=bids,
        asks=asks,
        spread=spread,
        spread_pct=spread_pct,
        mid_price=mid,
        bid_volume=bid_vol,
        ask_volume=ask_vol,
        imbalance=imbalance,
        source="binance",
    )


async def _fetch_stock_orderbook(symbol: str) -> Optional[OrderBookResult]:
    """
    For stocks we return a simplified spread-only book from yfinance fast_info.
    True L2 data requires Polygon Premium (paid).
    Returns best bid/ask only with a note — consumers can upgrade to Polygon L2
    by setting MASSIVE_API_KEY.
    """
    import yfinance as yf
    from app.services.data_fetcher import _YF_SEMAPHORE

    def _sync():
        try:
            t = yf.Ticker(symbol.upper())
            fi = t.fast_info
            bid = float(getattr(fi, "bid", None) or 0)
            ask = float(getattr(fi, "ask", None) or 0)
            price = float(getattr(fi, "last_price", None) or 0)
            if bid <= 0 or ask <= 0:
                # Fall back to last price ± 0.01%
                if price > 0:
                    bid = round(price * 0.9999, 4)
                    ask = round(price * 1.0001, 4)
                else:
                    return None

            spread = round(ask - bid, 6)
            mid = round((bid + ask) / 2, 4)
            spread_pct = round(spread / mid * 100, 4) if mid > 0 else None

            # Build single-level book (L1 only)
            bids = [OrderLevel(price=bid, quantity=0, total=0)]
            asks = [OrderLevel(price=ask, quantity=0, total=0)]

            return OrderBookResult(
                symbol=symbol.upper(),
                bids=bids,
                asks=asks,
                spread=spread,
                spread_pct=spread_pct,
                mid_price=mid,
                bid_volume=None,
                ask_volume=None,
                imbalance=None,
                source="yfinance_l1",
            )
        except Exception as e:
            logger.warning("[orderbook] yfinance stock %s: %s", symbol, e)
            return None

    async with _YF_SEMAPHORE:
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, _sync)


async def get_orderbook(symbol: str) -> Optional[OrderBookResult]:
    """Public entry point — routes to Binance or yfinance based on asset class."""
    if _is_crypto(symbol):
        return await _fetch_binance_orderbook(symbol)
    return await _fetch_stock_orderbook(symbol)
