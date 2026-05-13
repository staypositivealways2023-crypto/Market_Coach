"""Monte Carlo price simulation service using Geometric Brownian Motion."""

import numpy as np
import logging
from typing import List
from scipy.stats import kurtosis as scipy_kurtosis

from app.services.data_fetcher import MarketDataFetcher

logger = logging.getLogger(__name__)


class MonteCarloService:
    def __init__(self):
        self._fetcher = MarketDataFetcher()

    async def simulate(
        self,
        symbol: str,
        horizon_days: int = 30,
        num_simulations: int = 1000,
        confidence_levels: List[float] = [0.10, 0.25, 0.50, 0.75, 0.90],
    ) -> dict:
        """
        Run a GBM Monte Carlo simulation for *symbol* over *horizon_days*.

        Returns a dict with:
            symbol, current_price, horizon_days, num_simulations,
            percentiles (p10/p25/p50/p75/p90), expected_price, prob_profit,
            prob_loss_10pct, prob_gain_20pct, annualised_vol, drift_daily,
            var_95, cvar_95, black_swan_prone, excess_kurtosis.
        On any error returns {"symbol": symbol, "error": <message>}.
        """
        try:
            # 1. Fetch 1-year daily candles (252 trading days)
            candles = await self._fetcher.get_candles(symbol, interval="1d", limit=252)

            if not candles or len(candles) < 2:
                return {
                    "symbol": symbol,
                    "error": (
                        "Insufficient price history for " + symbol +
                        " (got " + str(len(candles)) + " candles)."
                    ),
                }

            closes = np.array([c.close for c in candles], dtype=float)

            # 2. Log-returns
            log_returns = np.diff(np.log(closes))

            # 3. Drift (mu) and daily volatility (sigma)
            mu: float = float(np.mean(log_returns))
            sigma: float = float(np.std(log_returns, ddof=1))

            if sigma == 0:
                return {"symbol": symbol, "error": "Zero volatility -- cannot simulate."}

            current_price: float = float(closes[-1])

            # 4. GBM paths  shape: (num_simulations, horizon_days)
            np.random.seed(42)
            dt = 1.0
            drift_term = (mu - 0.5 * sigma ** 2) * dt
            diffusion_std = sigma * np.sqrt(dt)

            Z = np.random.standard_normal((num_simulations, horizon_days))
            increments = drift_term + diffusion_std * Z
            cum_increments = np.cumsum(increments, axis=1)
            paths = current_price * np.exp(cum_increments)

            # 5. Final prices (last step of each path)
            finals = paths[:, -1]

            # 6. Percentile fan: p10 / p25 / p50 / p75 / p90
            percentiles = {
                str(int(cl * 100)): round(float(np.percentile(finals, cl * 100)), 2)
                for cl in confidence_levels
            }

            # 7. VaR 95 and CVaR 95 (loss as positive percentage)
            sorted_finals = np.sort(finals)
            var_95_price = float(np.percentile(finals, 5))
            tail_prices = sorted_finals[sorted_finals <= var_95_price]
            cvar_95_price = float(tail_prices.mean()) if len(tail_prices) > 0 else var_95_price
            var_95 = round((current_price - var_95_price) / current_price * 100, 2)
            cvar_95 = round((current_price - cvar_95_price) / current_price * 100, 2)

            # 8. Black swan flag: excess kurtosis > 3 in log-returns (Fisher: normal=0)
            excess_kurt = float(scipy_kurtosis(log_returns, fisher=True))
            black_swan_prone = bool(excess_kurt > 3.0)

            return {
                "symbol":           symbol,
                "current_price":    round(current_price, 2),
                "horizon_days":     horizon_days,
                "num_simulations":  num_simulations,
                "percentiles":      percentiles,
                "expected_price":   round(float(finals.mean()), 2),
                "prob_profit":      round(float((finals > current_price).mean()), 4),
                "prob_loss_10pct":  round(float((finals < current_price * 0.90).mean()), 4),
                "prob_gain_20pct":  round(float((finals > current_price * 1.20).mean()), 4),
                "annualised_vol":   round(float(sigma * np.sqrt(252) * 100), 2),
                "drift_daily":      round(float(mu), 6),
                "var_95":           var_95,
                "cvar_95":          cvar_95,
                "black_swan_prone": black_swan_prone,
                "excess_kurtosis":  round(excess_kurt, 3),
            }

        except Exception as e:
            logger.error(
                "MonteCarloService.simulate error for %s: %s", symbol, e, exc_info=True
            )
            return {"symbol": symbol, "error": str(e)}
