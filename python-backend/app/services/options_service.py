"""
Phase 5 — Options Chain Service

Fetches options data via yfinance and computes:
  - Put/Call Ratio (PCR) by volume and open interest
  - Max Pain price (strikes with maximum option writer profit)
  - IV Surface summary (ATM IV, skew, term structure)
  - Key strikes (highest OI calls/puts)

Note: Options data is only available for US equities.
      Crypto symbols return a graceful "not_available" response.
"""

import asyncio
import logging
import math
from dataclasses import dataclass, field
from typing import List, Optional

import yfinance as yf

from app.services.data_fetcher import _YF_SEMAPHORE

logger = logging.getLogger(__name__)


# ── Data classes ──────────────────────────────────────────────────────────────

@dataclass
class OptionStrike:
    strike: float
    call_oi: int
    put_oi: int
    call_volume: int
    put_volume: int
    call_iv: Optional[float]  # implied volatility 0–1
    put_iv: Optional[float]


@dataclass
class OptionsChainResult:
    symbol: str
    expiry: str                           # nearest expiry used
    current_price: Optional[float]
    atm_iv: Optional[float]               # at-the-money IV
    iv_skew: Optional[float]              # put IV - call IV (positive = put premium)
    pcr_volume: Optional[float]           # put vol / call vol
    pcr_oi: Optional[float]               # put OI / call OI
    pcr_signal: str                       # "bearish"|"neutral"|"bullish"
    max_pain: Optional[float]             # strike where option writers profit most
    max_pain_distance_pct: Optional[float]  # % from current price to max pain
    top_call_strikes: List[OptionStrike] = field(default_factory=list)  # top 3 by OI
    top_put_strikes: List[OptionStrike] = field(default_factory=list)   # top 3 by OI
    total_call_oi: int = 0
    total_put_oi: int = 0
    source: str = "yfinance"
    available: bool = True
    note: str = ""


# ── Helpers ───────────────────────────────────────────────────────────────────

def _safe_int(val) -> int:
    try:
        return int(val) if not math.isnan(float(val)) else 0
    except (TypeError, ValueError):
        return 0


def _safe_float(val) -> Optional[float]:
    try:
        f = float(val)
        return None if (math.isnan(f) or math.isinf(f)) else f
    except (TypeError, ValueError):
        return None


def _pcr_signal(pcr: Optional[float]) -> str:
    if pcr is None:
        return "neutral"
    if pcr > 1.2:
        return "bearish"   # heavy put buying
    if pcr < 0.7:
        return "bullish"   # heavy call buying
    return "neutral"


def _compute_max_pain(calls_df, puts_df, strikes: List[float]) -> Optional[float]:
    """
    Max pain = strike that maximises total loss for option buyers
    (= minimises payout for option writers).

    For each candidate strike S:
      loss_to_buyers = Σ_{calls with K < S} (S - K) × call_OI
                     + Σ_{puts with K > S} (K - S) × put_OI
    Max pain = S that minimises this total.
    """
    try:
        min_loss = float("inf")
        max_pain_strike = None

        call_oi = {
            row.strike: _safe_int(row.openInterest)
            for _, row in calls_df.iterrows()
        }
        put_oi = {
            row.strike: _safe_int(row.openInterest)
            for _, row in puts_df.iterrows()
        }

        for s in strikes:
            loss = 0.0
            # Calls in-the-money at strike S
            for k, oi in call_oi.items():
                if s > k:
                    loss += (s - k) * oi
            # Puts in-the-money at strike S
            for k, oi in put_oi.items():
                if s < k:
                    loss += (k - s) * oi

            if loss < min_loss:
                min_loss = loss
                max_pain_strike = s

        return max_pain_strike
    except Exception as e:
        logger.debug("[options] max pain error: %s", e)
        return None


# ── Main fetch ────────────────────────────────────────────────────────────────

def _fetch_options_sync(symbol: str) -> OptionsChainResult:
    """Synchronous fetch — called via run_in_executor."""
    ticker = yf.Ticker(symbol.upper())

    # Current price
    current_price = None
    try:
        fi = ticker.fast_info
        current_price = _safe_float(getattr(fi, "last_price", None))
    except Exception:
        pass

    # Get expiry dates
    try:
        expiries = ticker.options
    except Exception:
        expiries = []

    if not expiries:
        return OptionsChainResult(
            symbol=symbol.upper(),
            expiry="",
            current_price=current_price,
            atm_iv=None,
            iv_skew=None,
            pcr_volume=None,
            pcr_oi=None,
            pcr_signal="neutral",
            max_pain=None,
            max_pain_distance_pct=None,
            available=False,
            note="No options data available for this symbol.",
        )

    # Use nearest expiry
    nearest_expiry = expiries[0]
    try:
        chain = ticker.option_chain(nearest_expiry)
        calls = chain.calls
        puts = chain.puts
    except Exception as e:
        logger.warning("[options] chain fetch %s: %s", symbol, e)
        return OptionsChainResult(
            symbol=symbol.upper(),
            expiry=nearest_expiry,
            current_price=current_price,
            atm_iv=None,
            iv_skew=None,
            pcr_volume=None,
            pcr_oi=None,
            pcr_signal="neutral",
            max_pain=None,
            max_pain_distance_pct=None,
            available=False,
            note=f"Chain fetch failed: {e}",
        )

    # Put/Call ratios
    total_call_vol = int(calls["volume"].fillna(0).sum())
    total_put_vol  = int(puts["volume"].fillna(0).sum())
    total_call_oi  = int(calls["openInterest"].fillna(0).sum())
    total_put_oi   = int(puts["openInterest"].fillna(0).sum())

    pcr_vol = round(total_put_vol / total_call_vol, 4) if total_call_vol > 0 else None
    pcr_oi  = round(total_put_oi / total_call_oi, 4) if total_call_oi > 0 else None

    # Max pain
    all_strikes = sorted(
        set(calls["strike"].tolist()) | set(puts["strike"].tolist())
    )
    max_pain = _compute_max_pain(calls, puts, all_strikes)
    max_pain_pct = None
    if max_pain and current_price and current_price > 0:
        max_pain_pct = round((max_pain - current_price) / current_price * 100, 2)

    # ATM IV — find call/put closest to current price
    atm_call_iv = None
    atm_put_iv = None
    if current_price:
        try:
            calls_sorted = calls.copy()
            calls_sorted["dist"] = (calls_sorted["strike"] - current_price).abs()
            atm_call_row = calls_sorted.nsmallest(1, "dist").iloc[0]
            atm_call_iv = _safe_float(atm_call_row.get("impliedVolatility"))

            puts_sorted = puts.copy()
            puts_sorted["dist"] = (puts_sorted["strike"] - current_price).abs()
            atm_put_row = puts_sorted.nsmallest(1, "dist").iloc[0]
            atm_put_iv = _safe_float(atm_put_row.get("impliedVolatility"))
        except Exception:
            pass

    atm_iv = None
    if atm_call_iv is not None and atm_put_iv is not None:
        atm_iv = round((atm_call_iv + atm_put_iv) / 2, 4)
    elif atm_call_iv is not None:
        atm_iv = round(atm_call_iv, 4)

    iv_skew = None
    if atm_put_iv is not None and atm_call_iv is not None:
        iv_skew = round(atm_put_iv - atm_call_iv, 4)

    # Top strikes by open interest
    def _top_strikes(df, n=3) -> List[OptionStrike]:
        result = []
        try:
            top = df.nlargest(n, "openInterest")
            # Merge call + put data at each strike
            for _, row in top.iterrows():
                strike = float(row["strike"])
                c_row = calls[calls["strike"] == strike]
                p_row = puts[puts["strike"] == strike]
                result.append(OptionStrike(
                    strike=strike,
                    call_oi=_safe_int(c_row["openInterest"].values[0]) if len(c_row) else 0,
                    put_oi=_safe_int(p_row["openInterest"].values[0]) if len(p_row) else 0,
                    call_volume=_safe_int(c_row["volume"].values[0]) if len(c_row) else 0,
                    put_volume=_safe_int(p_row["volume"].values[0]) if len(p_row) else 0,
                    call_iv=_safe_float(c_row["impliedVolatility"].values[0]) if len(c_row) else None,
                    put_iv=_safe_float(p_row["impliedVolatility"].values[0]) if len(p_row) else None,
                ))
        except Exception as e:
            logger.debug("[options] top strikes error: %s", e)
        return result

    top_calls = _top_strikes(calls)
    top_puts  = _top_strikes(puts)

    return OptionsChainResult(
        symbol=symbol.upper(),
        expiry=nearest_expiry,
        current_price=current_price,
        atm_iv=atm_iv,
        iv_skew=iv_skew,
        pcr_volume=pcr_vol,
        pcr_oi=pcr_oi,
        pcr_signal=_pcr_signal(pcr_vol),
        max_pain=max_pain,
        max_pain_distance_pct=max_pain_pct,
        top_call_strikes=top_calls,
        top_put_strikes=top_puts,
        total_call_oi=total_call_oi,
        total_put_oi=total_put_oi,
        available=True,
    )


async def get_options_chain(symbol: str) -> OptionsChainResult:
    """Async wrapper — runs yfinance sync call in thread pool."""
    async with _YF_SEMAPHORE:
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, _fetch_options_sync, symbol)
