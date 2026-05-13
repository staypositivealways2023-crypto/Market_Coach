"""
Phase 5 — Money Flow & Market Position Service

Money Flow (Chaikin Money Flow — CMF):
  CMF = Σ(MFV, n) / Σ(Volume, n)
  Money Flow Volume = ((close - low) - (high - close)) / (high - low) × volume
  > +0.05  = accumulation (buying pressure)
  < -0.05  = distribution (selling pressure)

Market Position (derived technical signals):
  - Net positioning score: composite of CMF + RSI divergence + volume trend
  - Institutional proxy: smoothed 20-day MFV vs retail 3-day MFV
  - Trend strength: ADX-lite (directional move ratio)
"""

import asyncio
import logging
from dataclasses import dataclass
from typing import Optional, List

import yfinance as yf
import pandas as pd

from app.services.data_fetcher import _YF_SEMAPHORE, _to_yfinance_symbol

logger = logging.getLogger(__name__)


@dataclass
class MoneyFlowResult:
    symbol: str
    cmf_20: Optional[float]        # Chaikin Money Flow, 20-period
    cmf_signal: str                 # "accumulation" | "distribution" | "neutral"
    net_flow_usd: Optional[float]  # net dollar flow (positive = buying)
    institutional_flow: Optional[float]  # smoothed 20d MFV proxy
    retail_flow: Optional[float]         # short-term 3d MFV proxy
    flow_divergence: str            # "institutional_buying_retail_selling" | etc.
    volume_trend: str               # "increasing" | "decreasing" | "flat"
    source: str = "yfinance"


@dataclass
class MarketPositionResult:
    symbol: str
    net_position_score: Optional[float]  # -1.0 (max short) → +1.0 (max long)
    position_label: str                   # "heavily_long"|"long"|"neutral"|"short"|"heavily_short"
    adx_strength: Optional[float]         # 0–100 trend strength proxy
    trend_direction: str                   # "uptrend"|"downtrend"|"sideways"
    smart_money_signal: str               # "accumulating"|"distributing"|"neutral"
    key_price_level: Optional[float]      # VWAP or significant volume node
    source: str = "yfinance"


def _safe_float(val) -> Optional[float]:
    try:
        f = float(val)
        import math
        return None if (math.isnan(f) or math.isinf(f)) else f
    except (TypeError, ValueError):
        return None


def _compute_cmf(df: pd.DataFrame, period: int = 20) -> Optional[float]:
    """Chaikin Money Flow over `period` bars."""
    try:
        hi = df["High"]
        lo = df["Low"]
        cl = df["Close"]
        vol = df["Volume"]

        hl_range = hi - lo
        hl_range = hl_range.replace(0, 1e-9)  # avoid division by zero on flat bars

        mf_multiplier = ((cl - lo) - (hi - cl)) / hl_range
        mf_volume = mf_multiplier * vol

        cmf = mf_volume.tail(period).sum() / vol.tail(period).sum()
        return round(float(cmf), 4)
    except Exception as e:
        logger.debug("[moneyflow] CMF error: %s", e)
        return None


def _cmf_signal(cmf: Optional[float]) -> str:
    if cmf is None:
        return "neutral"
    if cmf > 0.05:
        return "accumulation"
    if cmf < -0.05:
        return "distribution"
    return "neutral"


def _volume_trend(df: pd.DataFrame, short: int = 5, long: int = 20) -> str:
    try:
        short_avg = df["Volume"].tail(short).mean()
        long_avg = df["Volume"].tail(long).mean()
        if short_avg > long_avg * 1.15:
            return "increasing"
        if short_avg < long_avg * 0.85:
            return "decreasing"
        return "flat"
    except Exception:
        return "flat"


def _adx_lite(df: pd.DataFrame, period: int = 14) -> Optional[float]:
    """
    Simplified directional strength — ratio of |directional moves| to total range.
    True ADX needs Wilder smoothing; this proxy is close enough for positioning signals.
    """
    try:
        hi = df["High"]
        lo = df["Low"]
        cl = df["Close"]

        # Directional moves
        up_move = hi.diff()
        dn_move = -lo.diff()

        pos_dm = up_move.where((up_move > dn_move) & (up_move > 0), 0.0)
        neg_dm = dn_move.where((dn_move > up_move) & (dn_move > 0), 0.0)

        true_range = pd.concat(
            [hi - lo, (hi - cl.shift()).abs(), (lo - cl.shift()).abs()], axis=1
        ).max(axis=1)

        atr = true_range.tail(period).mean()
        if atr == 0:
            return None

        pdi = (pos_dm.tail(period).mean() / atr) * 100
        ndi = (neg_dm.tail(period).mean() / atr) * 100

        dx = abs(pdi - ndi) / (pdi + ndi + 1e-9) * 100
        return round(float(dx), 2)
    except Exception as e:
        logger.debug("[moneyflow] ADX-lite error: %s", e)
        return None


def _trend_direction(df: pd.DataFrame) -> str:
    try:
        sma20 = df["Close"].tail(20).mean()
        sma50 = df["Close"].tail(50).mean() if len(df) >= 50 else sma20
        last = float(df["Close"].iloc[-1])
        if last > sma20 > sma50:
            return "uptrend"
        if last < sma20 < sma50:
            return "downtrend"
        return "sideways"
    except Exception:
        return "sideways"


def _vwap(df: pd.DataFrame, period: int = 20) -> Optional[float]:
    """Volume-weighted average price over last `period` bars."""
    try:
        sub = df.tail(period)
        typical = (sub["High"] + sub["Low"] + sub["Close"]) / 3
        vwap = (typical * sub["Volume"]).sum() / sub["Volume"].sum()
        return round(float(vwap), 4)
    except Exception:
        return None


def _fetch_df(symbol: str, period: str = "3mo") -> Optional[pd.DataFrame]:
    try:
        yf_sym = _to_yfinance_symbol(symbol)
        df = yf.download(yf_sym, period=period, progress=False, auto_adjust=True)
        if df is None or len(df) < 21:
            return None
        # yfinance >=0.2.18 returns MultiIndex columns for single-symbol downloads:
        # ('Close', 'AAPL'), ('High', 'AAPL'), … — flatten to bare price-type names.
        if isinstance(df.columns, pd.MultiIndex):
            df.columns = df.columns.get_level_values(0)
        df = df.dropna()
        return df
    except Exception as e:
        logger.warning("[moneyflow] yfinance download %s: %s", symbol, e)
        return None


async def get_money_flow(symbol: str) -> Optional[MoneyFlowResult]:
    """Compute CMF + flow decomposition for a symbol."""

    def _sync():
        df = _fetch_df(symbol)
        if df is None:
            return None

        cmf = _compute_cmf(df, 20)
        signal = _cmf_signal(cmf)
        vol_trend = _volume_trend(df)

        # Net dollar flow: sum of (MFV × price) over last 20 bars
        try:
            hi, lo, cl, vol = df["High"], df["Low"], df["Close"], df["Volume"]
            hl = (hi - lo).replace(0, 1e-9)
            mf_mult = ((cl - lo) - (hi - cl)) / hl
            mf_vol = mf_mult * vol
            net_flow = float((mf_vol * cl).tail(20).sum())
        except Exception:
            net_flow = None

        # Institutional proxy = smoothed 20d vs retail 3d
        inst = _compute_cmf(df, 20)
        retail = _compute_cmf(df, 3)

        if inst is not None and retail is not None:
            if inst > 0.03 and retail < -0.03:
                divergence = "institutional_buying_retail_selling"
            elif inst < -0.03 and retail > 0.03:
                divergence = "institutional_selling_retail_buying"
            elif inst > 0.03 and retail > 0.03:
                divergence = "both_buying"
            elif inst < -0.03 and retail < -0.03:
                divergence = "both_selling"
            else:
                divergence = "mixed"
        else:
            divergence = "unknown"

        return MoneyFlowResult(
            symbol=symbol.upper(),
            cmf_20=cmf,
            cmf_signal=signal,
            net_flow_usd=round(net_flow, 2) if net_flow is not None else None,
            institutional_flow=inst,
            retail_flow=retail,
            flow_divergence=divergence,
            volume_trend=vol_trend,
        )

    async with _YF_SEMAPHORE:
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, _sync)


async def get_market_position(symbol: str) -> Optional[MarketPositionResult]:
    """Compute net positioning score and smart-money signal."""

    def _sync():
        df = _fetch_df(symbol)
        if df is None:
            return None

        cmf = _compute_cmf(df, 20)
        adx = _adx_lite(df)
        trend = _trend_direction(df)
        vol_trend = _volume_trend(df)
        vwap_price = _vwap(df)

        # Net position score: blend CMF + trend alignment
        score = 0.0
        if cmf is not None:
            score += cmf * 2.0  # CMF range ≈ -1 to +1, weight it 2×

        if trend == "uptrend":
            score += 0.3
        elif trend == "downtrend":
            score -= 0.3

        if vol_trend == "increasing" and (cmf or 0) > 0:
            score += 0.2
        elif vol_trend == "increasing" and (cmf or 0) < 0:
            score -= 0.2

        score = max(-1.0, min(1.0, round(score, 4)))

        # Label
        if score >= 0.6:
            label = "heavily_long"
        elif score >= 0.2:
            label = "long"
        elif score <= -0.6:
            label = "heavily_short"
        elif score <= -0.2:
            label = "short"
        else:
            label = "neutral"

        # Smart money signal from CMF
        if cmf is not None and cmf > 0.1:
            smart = "accumulating"
        elif cmf is not None and cmf < -0.1:
            smart = "distributing"
        else:
            smart = "neutral"

        return MarketPositionResult(
            symbol=symbol.upper(),
            net_position_score=score,
            position_label=label,
            adx_strength=adx,
            trend_direction=trend,
            smart_money_signal=smart,
            key_price_level=vwap_price,
        )

    async with _YF_SEMAPHORE:
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, _sync)
