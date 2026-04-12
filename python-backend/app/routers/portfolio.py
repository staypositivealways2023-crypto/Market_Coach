"""Portfolio analysis endpoint — Sharpe, Sortino, correlation, rebalancing, AI insight."""

import math
import logging
from typing import List, Optional
from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel

from app.services.data_fetcher import MarketDataFetcher
from app.services.claude_service import ClaudeService
from app.utils.auth import require_auth
from app.utils.rate_limit import limiter

logger = logging.getLogger(__name__)
router = APIRouter()

_fetcher = MarketDataFetcher()
_claude  = ClaudeService()

_RISK_FREE_DAILY = 0.05 / 252  # 5% annual → daily


# ── Request / Response models ─────────────────────────────────────────────────

class HoldingInput(BaseModel):
    symbol: str
    name: str
    shares: float
    avg_cost: float


class PortfolioAnalyseRequest(BaseModel):
    holdings: List[HoldingInput]


class HoldingResult(BaseModel):
    symbol: str
    name: str
    shares: float
    avg_cost: float
    current_price: Optional[float] = None
    total_cost: float
    current_value: Optional[float] = None
    pnl: Optional[float] = None
    pnl_pct: Optional[float] = None
    allocation_pct: Optional[float] = None


class PortfolioMetrics(BaseModel):
    sharpe_ratio: Optional[float] = None
    sortino_ratio: Optional[float] = None
    portfolio_volatility: Optional[float] = None   # annualised std dev
    portfolio_beta: Optional[float] = None         # vs SPY


class PortfolioAnalyseResponse(BaseModel):
    total_value: float
    total_cost: float
    total_pnl: float
    total_pnl_pct: float
    holdings: List[HoldingResult]
    metrics: PortfolioMetrics
    correlation: dict
    rebalancing: List[str]
    ai_insight: str


# ── Helpers ───────────────────────────────────────────────────────────────────

def _daily_returns(closes: List[float]) -> List[float]:
    if len(closes) < 2:
        return []
    return [(closes[i] - closes[i - 1]) / closes[i - 1] for i in range(1, len(closes))]


def _mean(data: List[float]) -> float:
    return sum(data) / len(data) if data else 0.0


def _std(data: List[float]) -> float:
    if len(data) < 2:
        return 0.0
    m = _mean(data)
    variance = sum((x - m) ** 2 for x in data) / (len(data) - 1)
    return math.sqrt(variance)


def _sharpe(returns: List[float]) -> Optional[float]:
    if not returns:
        return None
    m = _mean(returns) - _RISK_FREE_DAILY
    s = _std(returns)
    return (m / s) * math.sqrt(252) if s > 1e-10 else None


def _sortino(returns: List[float]) -> Optional[float]:
    if not returns:
        return None
    m = _mean(returns) - _RISK_FREE_DAILY
    downside = [r for r in returns if r < _RISK_FREE_DAILY]
    ds = _std(downside)
    return (m / ds) * math.sqrt(252) if ds > 1e-10 else None


def _correlation(a: List[float], b: List[float]) -> Optional[float]:
    n = min(len(a), len(b))
    if n < 5:
        return None
    a, b = a[:n], b[:n]
    ma, mb = _mean(a), _mean(b)
    num = sum((a[i] - ma) * (b[i] - mb) for i in range(n))
    den = math.sqrt(
        sum((x - ma) ** 2 for x in a) * sum((x - mb) ** 2 for x in b)
    )
    return num / den if den > 1e-10 else None


def _portfolio_returns(
    symbol_returns: dict,      # symbol → List[float]
    weights: dict,             # symbol → float (fraction of portfolio)
) -> List[float]:
    if not symbol_returns:
        return []
    min_len = min(len(v) for v in symbol_returns.values() if v)
    if min_len == 0:
        return []
    port = []
    for i in range(min_len):
        day_ret = sum(
            weights.get(s, 0) * rets[i]
            for s, rets in symbol_returns.items()
            if len(rets) > i
        )
        port.append(day_ret)
    return port


# ── Endpoint ──────────────────────────────────────────────────────────────────

@router.post("/analyse", response_model=PortfolioAnalyseResponse)
@limiter.limit("5/minute")
async def analyse_portfolio(request: Request, req: PortfolioAnalyseRequest, uid: str = Depends(require_auth)):
    holdings = req.holdings
    if not holdings:
        return PortfolioAnalyseResponse(
            total_value=0, total_cost=0, total_pnl=0, total_pnl_pct=0,
            holdings=[], metrics=PortfolioMetrics(), correlation={},
            rebalancing=[], ai_insight="No holdings provided.",
        )

    symbols = [h.symbol.upper() for h in holdings]

    # 1. Fetch current prices
    quotes = {}
    for sym in symbols:
        try:
            q = await _fetcher.get_quote(sym)
            if q:
                quotes[sym] = float(q.price)
        except Exception as e:
            logger.warning(f"Quote fetch failed for {sym}: {e}")

    # 2. Build holding results
    holding_results: List[HoldingResult] = []
    total_cost = sum(h.shares * h.avg_cost for h in holdings)
    total_value = 0.0

    for h in holdings:
        sym = h.symbol.upper()
        cost = h.shares * h.avg_cost
        price = quotes.get(sym)
        value = h.shares * price if price else cost
        total_value += value
        pnl = (value - cost) if price else None
        pnl_pct = ((pnl / cost) * 100) if pnl is not None and cost > 0 else None
        holding_results.append(HoldingResult(
            symbol=sym, name=h.name, shares=h.shares, avg_cost=h.avg_cost,
            current_price=price, total_cost=cost, current_value=value,
            pnl=pnl, pnl_pct=pnl_pct,
        ))

    # Allocation %
    for r in holding_results:
        r.allocation_pct = (r.current_value / total_value * 100) if total_value > 0 else None

    total_pnl = total_value - total_cost
    total_pnl_pct = (total_pnl / total_cost * 100) if total_cost > 0 else 0

    # 3. Fetch 30-day candles for each symbol
    symbol_returns: dict = {}
    for sym in symbols:
        try:
            candles = await _fetcher.get_candles(sym, interval="1d", limit=31)
            closes = [float(c.close) for c in candles] if candles else []
            symbol_returns[sym] = _daily_returns(closes)
        except Exception as e:
            logger.warning(f"Candle fetch failed for {sym}: {e}")
            symbol_returns[sym] = []

    # 4. Weights by current value
    weights = {
        sym: ((quotes.get(sym, 0) * next((h.shares for h in holdings if h.symbol.upper() == sym), 0)) / total_value)
        for sym in symbols
    } if total_value > 0 else {sym: 1 / len(symbols) for sym in symbols}

    # 5. Portfolio-level returns
    port_returns = _portfolio_returns(symbol_returns, weights)

    # 6. Risk metrics
    sharpe = _sharpe(port_returns)
    sortino = _sortino(port_returns)
    vol = _std(port_returns) * math.sqrt(252) if port_returns else None

    metrics = PortfolioMetrics(
        sharpe_ratio=round(sharpe, 3) if sharpe is not None else None,
        sortino_ratio=round(sortino, 3) if sortino is not None else None,
        portfolio_volatility=round(vol, 4) if vol is not None else None,
    )

    # 7. Correlation matrix (top pairs)
    correlation: dict = {}
    sym_list = list(symbol_returns.keys())
    for i in range(len(sym_list)):
        for j in range(i + 1, len(sym_list)):
            a, b = sym_list[i], sym_list[j]
            c = _correlation(symbol_returns[a], symbol_returns[b])
            if c is not None:
                key = f"{a}/{b}"
                correlation[key] = round(c, 3)

    # 8. Rebalancing suggestions
    rebalancing: List[str] = []
    for r in holding_results:
        if r.allocation_pct and r.allocation_pct > 50:
            rebalancing.append(
                f"{r.symbol} is {r.allocation_pct:.1f}% of your portfolio — consider trimming to reduce concentration risk."
            )
    for key, corr in correlation.items():
        if corr > 0.85:
            rebalancing.append(
                f"{key} are highly correlated ({corr:.2f}) — they may move together, reducing diversification benefit."
            )
    if sharpe is not None and sharpe < 0.5:
        rebalancing.append(
            "Portfolio Sharpe ratio is below 0.5 — consider reviewing underperforming positions or adding uncorrelated assets."
        )
    if not rebalancing:
        rebalancing.append("Portfolio appears reasonably diversified. Continue monitoring concentration and correlation.")

    # 9. Claude AI insight
    ai_insight = ""
    try:
        holdings_summary = ", ".join(
            f"{r.symbol} ({r.allocation_pct:.1f}% alloc, {r.pnl_pct:+.1f}% P&L)"
            if r.allocation_pct is not None and r.pnl_pct is not None
            else r.symbol
            for r in holding_results
        )
        system = (
            "You are a senior portfolio analyst. Analyse portfolios concisely and accurately. "
            "Never say 'as an AI'. Be direct and specific."
        )
        user_prompt = (
            f"Analyse this portfolio in 3-4 sentences.\n"
            f"Holdings: {holdings_summary}\n"
            f"Sharpe: {sharpe}, Sortino: {sortino}, Volatility: {vol}\n"
            f"Correlation pairs: {correlation}\n"
            f"Give a plain-English risk/return assessment and one actionable suggestion."
        )
        result = await _claude.generate_analysis(system, user_prompt)
        ai_insight = result["analysis_text"]
    except Exception as e:
        logger.warning(f"Claude portfolio insight failed: {e}")
        ai_insight = "AI insight unavailable — backend Claude call failed."

    return PortfolioAnalyseResponse(
        total_value=round(total_value, 2),
        total_cost=round(total_cost, 2),
        total_pnl=round(total_pnl, 2),
        total_pnl_pct=round(total_pnl_pct, 2),
        holdings=holding_results,
        metrics=metrics,
        correlation=correlation,
        rebalancing=rebalancing,
        ai_insight=ai_insight,
    )
