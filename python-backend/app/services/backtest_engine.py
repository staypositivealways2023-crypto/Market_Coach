"""Portfolio backtest engine using yfinance historical adjusted closes."""

import math
from dataclasses import dataclass
from typing import List

import yfinance as yf


@dataclass
class BacktestHolding:
    symbol: str
    shares: float
    avg_cost: float


def _max_drawdown(values: List[float]) -> float:
    peak = 0.0
    worst = 0.0
    for value in values:
        peak = max(peak, value)
        if peak > 0:
            worst = min(worst, (value - peak) / peak)
    return worst


def _daily_returns(values: List[float]) -> List[float]:
    return [
        (values[i] - values[i - 1]) / values[i - 1]
        for i in range(1, len(values))
        if values[i - 1] > 0
    ]


def _std(values: List[float]) -> float:
    if len(values) < 2:
        return 0.0
    mean = sum(values) / len(values)
    return math.sqrt(sum((v - mean) ** 2 for v in values) / (len(values) - 1))


def _yf_symbol(symbol: str) -> str:
    crypto = {
        "BTC": "BTC-USD",
        "ETH": "ETH-USD",
        "SOL": "SOL-USD",
        "ADA": "ADA-USD",
        "XRP": "XRP-USD",
        "DOGE": "DOGE-USD",
        "BNB": "BNB-USD",
        "AVAX": "AVAX-USD",
        "DOT": "DOT-USD",
    }
    sym = symbol.upper()
    if sym in crypto:
        return crypto[sym]
    return sym.replace(".", "-")


def _history(symbol: str, period: str) -> list[float]:
    ticker = yf.Ticker(_yf_symbol(symbol))
    hist = ticker.history(period=period, interval="1d", auto_adjust=True)
    if hist is None or hist.empty or "Close" not in hist:
        return []
    return [float(v) for v in hist["Close"].dropna().tolist()]


def run_portfolio_backtest(
    holdings: List[BacktestHolding],
    period: str = "1y",
    initial_value: float = 10000.0,
) -> dict:
    valid = [h for h in holdings if h.shares > 0 and h.avg_cost > 0]
    if not valid:
        return {
            "period": period,
            "initial_value": initial_value,
            "final_value": initial_value,
            "total_return_pct": 0.0,
            "annualized_return_pct": 0.0,
            "max_drawdown_pct": 0.0,
            "volatility_pct": 0.0,
            "sharpe_ratio": None,
            "best_day_pct": 0.0,
            "worst_day_pct": 0.0,
            "points": [],
        }

    total_cost = sum(h.shares * h.avg_cost for h in valid)
    weights = {h.symbol.upper(): (h.shares * h.avg_cost) / total_cost for h in valid}
    histories = {sym: _history(sym, period) for sym in weights}
    histories = {sym: closes for sym, closes in histories.items() if len(closes) >= 2}
    if not histories:
        raise ValueError("No historical price data available for portfolio holdings.")

    length = min(len(closes) for closes in histories.values())
    normalized = {}
    for sym, closes in histories.items():
        window = closes[-length:]
        first = window[0]
        normalized[sym] = [price / first for price in window]

    equity_curve = []
    for i in range(length):
        multiplier = sum(weights.get(sym, 0.0) * series[i] for sym, series in normalized.items())
        equity_curve.append(initial_value * multiplier)

    returns = _daily_returns(equity_curve)
    final_value = equity_curve[-1]
    total_return = (final_value - initial_value) / initial_value
    years = max(length / 252, 1 / 252)
    annualized = ((final_value / initial_value) ** (1 / years)) - 1 if final_value > 0 else 0.0
    volatility = _std(returns) * math.sqrt(252) if returns else 0.0
    sharpe = (annualized - 0.05) / volatility if volatility > 1e-10 else None

    return {
        "period": period,
        "initial_value": round(initial_value, 2),
        "final_value": round(final_value, 2),
        "total_return_pct": round(total_return * 100, 2),
        "annualized_return_pct": round(annualized * 100, 2),
        "max_drawdown_pct": round(_max_drawdown(equity_curve) * 100, 2),
        "volatility_pct": round(volatility * 100, 2),
        "sharpe_ratio": round(sharpe, 3) if sharpe is not None else None,
        "best_day_pct": round(max(returns) * 100, 2) if returns else 0.0,
        "worst_day_pct": round(min(returns) * 100, 2) if returns else 0.0,
        "points": [
            {"index": i, "value": round(value, 2)}
            for i, value in enumerate(equity_curve[:: max(1, length // 60)])
        ],
    }
