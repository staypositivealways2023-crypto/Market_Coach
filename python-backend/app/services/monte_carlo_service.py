"""Monte Carlo price simulation service using Geometric Brownian Motion."""

import numpy as np
import logging
from typing import List

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
        confidence_levels: List[float] = [0.05, 0.25, 0.75, 0.95],
    ) -> dict:
        """
        Run a GBM Monte Carlo simulation for *symbol* over *horizon_days*.

        Returns a dict with:
            symbol, current_price, horizon_days, num_simulations,
            percentiles, expected_price, prob_profit, prob_loss_10pct,
            prob_gain_20pct, annualised_vol, drift_daily
        On any error returns {"symbol": symbol, "error": <message>}.
        """
        try:
            # 1. Fetch 1-year daily candles (252 trading days)
            candles = await self._fetcher.get_candles(symbol, interval="1d", limit=252)

            if not candles or len(candles) < 2:
                return {
                    "symbol": symbol,
                    "error": f"Insufficient price history for {symbol} (got {len(candles)} candles).",
                }

            closes = np.array([c.close for c in candles], dtype=float)

            # 2. Log-returns
            log_returns = np.diff(np.log(closes))

            # 3. Drift (mu) and daily volatility (sigma)
            mu: float = float(np.mean(log_returns))
            sigma: float = float(np.std(log_returns, ddof=1))

            if sigma == 0:
                return {"symbol": symbol, "error": "Zero volatility — cannot simulate."}

            current_price: float = float(closes[-1])

            # 4. GBM paths — shape: (num_simulations, horizon_days)
            np.random.seed(42)
            dt = 1.0  # daily steps
            drift_term = (mu - 0.5 * sigma ** 2) * dt
            diffusion_std = sigma * np.sqrt(dt)

            # Random shocks: (num_simulations, horizon_days)
            Z = np.random.standard_normal((num_simulations, horizon_days))
            # Daily log-price increments
            increments = drift_term + diffusion_std * Z          # (S, H)
            # Cumulative sum across time axis to get log-price paths
            cum_increments = np.cumsum(increments, axis=1)       # (S, H)
            # Price paths
            paths = current_price * np.exp(cum_increments)       # (S, H)

            # 5. Final prices (last step of each path)
            finals = paths[:, -1]                                 # (S,)

            # 6. Build result dict
            percentiles = {
                str(int(cl * 100)): round(float(np.percentile(finals, cl * 100)), 2)
                for cl in confidence_levels
            }

            return {
                "symbol": symbol,
                "current_price": round(current_price, 2),
                "horizon_days": horizon_days,
                "num_simulations": num_simulations,
                "percentiles": percentiles,
                "expected_price": round(float(finals.mean()), 2),
                "prob_profit": round(float((finals > current_price).mean()), 4),
                "prob_loss_10pct": round(float((finals < current_price * 0.90).mean()), 4),
                "prob_gain_20pct": round(float((finals > current_price * 1.20).mean()), 4),
                "annualised_vol": round(float(sigma * np.sqrt(252) * 100), 2),
                "drift_daily": round(float(mu), 6),
            }

        except Exception as e:
            logger.error(f"MonteCarloService.simulate error for {symbol}: {e}", exc_info=True)
            return {"symbol": symbol, "error": str(e)}
