"""
Phase 5 — Market Data Router (Level 2 + Money Flow + Options)

Endpoints:
  GET /api/market/orderbook/{symbol}       — level 2 order book
  GET /api/market/moneyflow/{symbol}       — Chaikin Money Flow + institutional proxy
  GET /api/market/marketposition/{symbol}  — net positioning score + smart-money signal
  GET /api/market/options/{symbol}         — put/call ratio, max pain, IV surface
"""

import logging
from fastapi import APIRouter, HTTPException, Query
from typing import Optional

from app.services.orderbook_service import get_orderbook, OrderBookResult
from app.services.moneyflow_service import (
    get_money_flow,
    get_market_position,
    MoneyFlowResult,
    MarketPositionResult,
)
from app.services.options_service import get_options_chain, OptionsChainResult
from app.utils.cache import cache_manager

logger = logging.getLogger(__name__)
router = APIRouter()


# ── Serializers ───────────────────────────────────────────────────────────────

def _serialise_orderbook(ob: OrderBookResult) -> dict:
    return {
        "symbol":       ob.symbol,
        "bids":         [{"price": l.price, "quantity": l.quantity, "total": l.total} for l in ob.bids],
        "asks":         [{"price": l.price, "quantity": l.quantity, "total": l.total} for l in ob.asks],
        "spread":       ob.spread,
        "spread_pct":   ob.spread_pct,
        "mid_price":    ob.mid_price,
        "bid_volume":   ob.bid_volume,
        "ask_volume":   ob.ask_volume,
        "imbalance":    ob.imbalance,
        "imbalance_signal": (
            "buy_pressure"  if (ob.imbalance or 0.5) > 0.6 else
            "sell_pressure" if (ob.imbalance or 0.5) < 0.4 else
            "balanced"
        ),
        "source":       ob.source,
    }


def _serialise_moneyflow(mf: MoneyFlowResult) -> dict:
    return {
        "symbol":               mf.symbol,
        "cmf_20":               mf.cmf_20,
        "cmf_signal":           mf.cmf_signal,
        "net_flow_usd":         mf.net_flow_usd,
        "institutional_flow":   mf.institutional_flow,
        "retail_flow":          mf.retail_flow,
        "flow_divergence":      mf.flow_divergence,
        "volume_trend":         mf.volume_trend,
        "source":               mf.source,
    }


def _serialise_position(mp: MarketPositionResult) -> dict:
    return {
        "symbol":               mp.symbol,
        "net_position_score":   mp.net_position_score,
        "position_label":       mp.position_label,
        "adx_strength":         mp.adx_strength,
        "trend_direction":      mp.trend_direction,
        "smart_money_signal":   mp.smart_money_signal,
        "key_price_level":      mp.key_price_level,
        "source":               mp.source,
    }


def _serialise_options(oc: OptionsChainResult) -> dict:
    def _strike(s):
        return {
            "strike":       s.strike,
            "call_oi":      s.call_oi,
            "put_oi":       s.put_oi,
            "call_volume":  s.call_volume,
            "put_volume":   s.put_volume,
            "call_iv":      s.call_iv,
            "put_iv":       s.put_iv,
        }
    return {
        "symbol":                   oc.symbol,
        "expiry":                   oc.expiry,
        "current_price":            oc.current_price,
        "atm_iv":                   oc.atm_iv,
        "iv_skew":                  oc.iv_skew,
        "pcr_volume":               oc.pcr_volume,
        "pcr_oi":                   oc.pcr_oi,
        "pcr_signal":               oc.pcr_signal,
        "max_pain":                 oc.max_pain,
        "max_pain_distance_pct":    oc.max_pain_distance_pct,
        "top_call_strikes":         [_strike(s) for s in oc.top_call_strikes],
        "top_put_strikes":          [_strike(s) for s in oc.top_put_strikes],
        "total_call_oi":            oc.total_call_oi,
        "total_put_oi":             oc.total_put_oi,
        "available":                oc.available,
        "note":                     oc.note,
        "source":                   oc.source,
    }


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("/orderbook/{symbol}")
async def get_orderbook_endpoint(symbol: str):
    """
    Level 2 order book — top 20 bid/ask levels.

    - Crypto : Binance /api/v3/depth (real L2, public, no key needed)
    - Stocks : yfinance best bid/ask (L1 only — true L2 needs Polygon Premium)

    Returns imbalance ratio: >0.6 = buy pressure, <0.4 = sell pressure.
    """
    sym = symbol.upper()
    cache_key = f"orderbook:{sym}"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    ob = await get_orderbook(sym)
    if ob is None:
        raise HTTPException(status_code=404, detail=f"Order book unavailable for {sym}")

    result = _serialise_orderbook(ob)
    cache_manager.set(cache_key, result, ttl=10)  # 10s cache for near-realtime feel
    return result


@router.get("/moneyflow/{symbol}")
async def get_moneyflow_endpoint(symbol: str):
    """
    Chaikin Money Flow (CMF-20) + institutional vs retail flow decomposition.

    CMF > +0.05 = accumulation (buying pressure)
    CMF < -0.05 = distribution (selling pressure)

    Institutional proxy = 20-day smoothed MFV
    Retail proxy        = 3-day MFV
    """
    sym = symbol.upper()
    cache_key = f"moneyflow:{sym}"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    mf = await get_money_flow(sym)
    if mf is None:
        raise HTTPException(status_code=404, detail=f"Money flow data unavailable for {sym}")

    result = _serialise_moneyflow(mf)
    cache_manager.set(cache_key, result, ttl=300)  # 5-min cache (daily candles)
    return result


@router.get("/marketposition/{symbol}")
async def get_marketposition_endpoint(symbol: str):
    """
    Net market positioning score (-1.0 to +1.0) derived from:
      - Chaikin Money Flow (weight: 2×)
      - Price trend (SMA20 vs SMA50 alignment)
      - Volume trend (short vs long average)

    Also returns VWAP as the key institutional price reference level.
    """
    sym = symbol.upper()
    cache_key = f"marketposition:{sym}"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    mp = await get_market_position(sym)
    if mp is None:
        raise HTTPException(status_code=404, detail=f"Market position unavailable for {sym}")

    result = _serialise_position(mp)
    cache_manager.set(cache_key, result, ttl=300)
    return result


@router.get("/options/{symbol}")
async def get_options_endpoint(symbol: str):
    """
    Options chain summary for the nearest expiry.

    Returns:
      - Put/Call ratio (by volume and open interest)
      - Max pain price (strike maximising option-writer profit)
      - ATM implied volatility + skew (put IV minus call IV)
      - Top 3 call/put strikes by open interest

    Note: Only available for US equity options.
          Crypto symbols return available=false.
    """
    sym = symbol.upper()
    cache_key = f"options:{sym}"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    oc = await get_options_chain(sym)
    result = _serialise_options(oc)
    # Cache 15 min — options chains don't move tick-by-tick
    cache_manager.set(cache_key, result, ttl=900)
    return result
