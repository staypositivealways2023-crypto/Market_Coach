"""
Screener Service — multi-factor stock/crypto screening with RSI signals.

Filters applied in order:
  1. asset_type  (all | stock | crypto)
  2. sector      (Tech | Finance | Healthcare | Energy | ETF | Crypto | ...)
  3. min_volume / min_market_cap / max_market_cap
  4. min_change / max_change  (daily %)
  5. signal      (OVERSOLD | OVERBOUGHT | any)   — uses RSI 14

RSI is computed only for symbols that survive the price/volume filters,
so the slow candle-fetch step hits at most ~20 symbols rather than the
full universe.
"""

import asyncio
import logging
from typing import Optional

import pandas as pd
from ta.momentum import RSIIndicator

from app.services.data_fetcher import MarketDataFetcher, _is_crypto_symbol
from app.utils.cache import cache_manager

logger = logging.getLogger(__name__)

_data_fetcher = MarketDataFetcher()

# ── Screener universe ─────────────────────────────────────────────────────────
# symbol → (sector, is_crypto)
_UNIVERSE: dict[str, tuple[str, bool]] = {
    # Tech
    "AAPL":  ("Tech",       False),
    "MSFT":  ("Tech",       False),
    "NVDA":  ("Tech",       False),
    "GOOGL": ("Tech",       False),
    "AMZN":  ("Tech",       False),
    "META":  ("Tech",       False),
    "TSLA":  ("Tech",       False),
    "ADBE":  ("Tech",       False),
    "CRM":   ("Tech",       False),
    "CSCO":  ("Tech",       False),
    "INTC":  ("Tech",       False),
    "AMD":   ("Tech",       False),
    "QCOM":  ("Tech",       False),
    "AVGO":  ("Tech",       False),
    "NFLX":  ("Tech",       False),
    # Finance
    "BRK-B": ("Finance",    False),
    "JPM":   ("Finance",    False),
    "V":     ("Finance",    False),
    "MA":    ("Finance",    False),
    "BAC":   ("Finance",    False),
    "GS":    ("Finance",    False),
    "MS":    ("Finance",    False),
    # Healthcare
    "JNJ":   ("Healthcare", False),
    "UNH":   ("Healthcare", False),
    "PFE":   ("Healthcare", False),
    "MRK":   ("Healthcare", False),
    "ABBV":  ("Healthcare", False),
    "LLY":   ("Healthcare", False),
    "TMO":   ("Healthcare", False),
    # Energy
    "XOM":   ("Energy",     False),
    "CVX":   ("Energy",     False),
    # Consumer
    "WMT":   ("Consumer",   False),
    "HD":    ("Consumer",   False),
    "COST":  ("Consumer",   False),
    "PG":    ("Consumer",   False),
    "PEP":   ("Consumer",   False),
    "KO":    ("Consumer",   False),
    "DIS":   ("Consumer",   False),
    "ACN":   ("Consumer",   False),
    # ETFs
    "SPY":   ("ETF",        False),
    "QQQ":   ("ETF",        False),
    "ARKK":  ("ETF",        False),
    "IWM":   ("ETF",        False),
    # Crypto
    "BTC":   ("Crypto",     True),
    "ETH":   ("Crypto",     True),
    "BNB":   ("Crypto",     True),
    "SOL":   ("Crypto",     True),
    "ADA":   ("Crypto",     True),
    "DOT":   ("Crypto",     True),
    "AVAX":  ("Crypto",     True),
    "XRP":   ("Crypto",     True),
}

RSI_OVERSOLD   = 35.0
RSI_OVERBOUGHT = 65.0
RSI_PERIOD       = 14
RSI_CANDLE_LIMIT = 30    # candles needed for stable RSI-14
_RSI_TIMEOUT_S   = 6.0   # per-symbol timeout; prevents one slow symbol hanging the whole screener


async def _compute_rsi(symbol: str) -> Optional[float]:
    """Fetch 30 daily candles and compute the latest RSI-14 value.

    A per-symbol timeout of _RSI_TIMEOUT_S seconds ensures the screener
    never stalls when a data provider is slow on a specific symbol.
    """
    cache_key = f"screener_rsi:{symbol}"
    cached = cache_manager.get(cache_key)
    if cached is not None:
        return cached

    try:
        async def _fetch_and_compute():
            candles = await _data_fetcher.get_candles(
                symbol, interval="1d", limit=RSI_CANDLE_LIMIT
            )
            if not candles or len(candles) < RSI_PERIOD + 1:
                return None
            closes = pd.Series([c.close for c in candles], dtype=float)
            # Guard against all-same-price series (e.g. illiquid crypto) to avoid NaN RSI.
            if closes.std() < 1e-10:
                return 50.0
            rsi_val = RSIIndicator(close=closes, window=RSI_PERIOD).rsi().iloc[-1]
            return round(float(rsi_val), 1) if not pd.isna(rsi_val) else None

        result = await asyncio.wait_for(_fetch_and_compute(), timeout=_RSI_TIMEOUT_S)
        if result is not None:
            cache_manager.set(cache_key, result, ttl=300)  # 5-min cache
        return result
    except asyncio.TimeoutError:
        logger.warning(f"[screener] RSI timeout for {symbol} (>{_RSI_TIMEOUT_S}s) — skipping")
        return None
    except Exception as e:
        logger.warning(f"[screener] RSI compute failed for {symbol}: {e}")
        return None


def _rsi_signal(rsi: Optional[float]) -> str:
    if rsi is None:
        return "NEUTRAL"
    if rsi <= RSI_OVERSOLD:
        return "OVERSOLD"
    if rsi >= RSI_OVERBOUGHT:
        return "OVERBOUGHT"
    return "NEUTRAL"


async def run_screener(
    asset_type: str        = "all",
    sector: Optional[str]  = None,
    min_change: Optional[float] = None,
    max_change: Optional[float] = None,
    min_volume: Optional[float] = None,
    min_market_cap: Optional[float] = None,
    max_market_cap: Optional[float] = None,
    signal: Optional[str]  = None,   # OVERSOLD | OVERBOUGHT | NEUTRAL | None
    sort_by: str           = "change_percent",  # change_percent | volume | market_cap | rsi
    limit: int             = 20,
) -> list[dict]:
    """
    Main screener entry point.  Returns a list of result dicts enriched with
    rsi, signal_label, sector fields.
    """
    # ── Step 1: narrow universe by asset_type and sector ─────────────────────
    candidates = []
    for sym, (sym_sector, is_crypto) in _UNIVERSE.items():
        if asset_type == "stock"  and is_crypto:          continue
        if asset_type == "crypto" and not is_crypto:       continue
        if sector and sym_sector.lower() != sector.lower(): continue
        candidates.append(sym)

    if not candidates:
        return []

    # ── Step 2: batch-fetch quotes ───────────────────────────────────────────
    quotes = await _data_fetcher.get_quotes_batch(candidates[:50])
    quote_map = {q.symbol: q for q in quotes}

    # ── Step 3: apply price / volume / market-cap filters ────────────────────
    filtered = []
    for sym in candidates:
        q = quote_map.get(sym)
        if q is None:
            continue
        cp = q.change_percent
        if min_change is not None and (cp is None or cp < min_change):
            continue
        if max_change is not None and (cp is None or cp > max_change):
            continue
        if min_volume is not None and (q.volume is None or q.volume < min_volume):
            continue
        if min_market_cap is not None and (q.market_cap is None or q.market_cap < min_market_cap):
            continue
        if max_market_cap is not None and (q.market_cap is not None and q.market_cap > max_market_cap):
            continue
        filtered.append(sym)

    if not filtered:
        return []

    # ── Step 4: compute RSI for surviving symbols (parallel) ─────────────────
    rsi_values = await asyncio.gather(
        *[_compute_rsi(sym) for sym in filtered],
        return_exceptions=True,
    )
    rsi_map: dict[str, Optional[float]] = {}
    for sym, rsi in zip(filtered, rsi_values):
        rsi_map[sym] = rsi if not isinstance(rsi, Exception) else None

    # ── Step 5: apply signal filter ──────────────────────────────────────────
    results = []
    for sym in filtered:
        q        = quote_map[sym]
        rsi      = rsi_map.get(sym)
        sig      = _rsi_signal(rsi)
        sym_sec  = _UNIVERSE.get(sym, ("Unknown", False))[0]

        if signal and signal.upper() != sig:
            continue

        results.append({
            "symbol":         sym,
            "sector":         sym_sec,
            "asset_type":     "crypto" if _is_crypto_symbol(sym) else "stock",
            "price":          q.price,
            "change_percent": q.change_percent,
            "change":         q.change,
            "volume":         q.volume,
            "market_cap":     q.market_cap,
            "rsi":            rsi,
            "signal":         sig,
        })

    # ── Step 6: sort ─────────────────────────────────────────────────────────
    def _sort_key(r: dict):
        if sort_by == "volume":
            return r["volume"] or 0
        if sort_by == "market_cap":
            return r["market_cap"] or 0
        if sort_by == "rsi":
            # Oversold first (lowest RSI), then overbought last
            return r["rsi"] if r["rsi"] is not None else 50.0
        # Default: absolute daily change
        return abs(r["change_percent"] or 0)

    reverse = sort_by != "rsi"   # ascending for RSI (show oversold first), desc otherwise
    results.sort(key=_sort_key, reverse=reverse)

    return results[:limit]
