"""Bayesian price-target updater using Normal-Normal conjugate update."""

import numpy as np
import logging
from math import exp, sqrt
from scipy.stats import norm

from app.services.data_fetcher import MarketDataFetcher

logger = logging.getLogger(__name__)


class BayesianService:
    def __init__(self):
        self._fetcher = MarketDataFetcher()

    async def update_price_target(
        self,
        symbol: str,
        analyst_target: float,       # prior mean (analyst's price target)
        analyst_confidence: float,   # prior precision weight (e.g. 1–10 scale)
        horizon_days: int = 30,
    ) -> dict:
        """
        Bayesian price-target update (Normal-Normal conjugate).

        Takes an analyst price target + confidence as the prior, updates it
        with recent return likelihood derived from historical data, and returns
        a posterior expected price with 90% credible interval.

        Returns a dict with all result fields on success, or
        {"symbol": symbol, "error": <message>} on failure.
        """
        try:
            # 1. Fetch 1-yr daily candles (252 trading days)
            candles = await self._fetcher.get_candles(symbol, interval="1d", limit=252)

            if not candles or len(candles) < 2:
                return {
                    "symbol": symbol,
                    "error": (
                        f"Insufficient price history for {symbol} "
                        f"(got {len(candles) if candles else 0} candles)."
                    ),
                }

            closes = np.array([c.close for c in candles], dtype=float)

            # 2. Log-returns → mu_data, sigma_data
            log_returns = np.diff(np.log(closes))
            mu_data: float = float(np.mean(log_returns))
            sigma_data: float = float(np.std(log_returns, ddof=1))

            if sigma_data == 0:
                return {"symbol": symbol, "error": "Zero volatility — cannot compute Bayesian update."}

            current_price: float = float(closes[-1])

            # 3. Data-implied price target over horizon
            data_target: float = current_price * exp(mu_data * horizon_days)

            # 4. Normal-Normal conjugate update
            # Prior:   mean = analyst_target,  precision = analyst_confidence
            # Data:    mean = data_target,      precision = 1 / (sigma_data^2 * horizon_days)
            prior_mean: float = analyst_target
            prior_precision: float = analyst_confidence
            data_precision: float = 1.0 / (sigma_data ** 2 * horizon_days)

            posterior_precision: float = prior_precision + data_precision
            posterior_mean: float = (
                prior_precision * prior_mean + data_precision * data_target
            ) / posterior_precision
            posterior_std: float = sqrt(1.0 / posterior_precision)

            # 5. 90% credible interval  (posterior_mean ± 1.645 * posterior_std)
            half_width = 1.645 * posterior_std
            ci_low = round(posterior_mean - half_width, 2)
            ci_high = round(posterior_mean + half_width, 2)

            # 6. Probability the true price will exceed the analyst target
            prob_above_analyst: float = float(
                1.0 - norm.cdf(analyst_target, loc=posterior_mean, scale=posterior_std)
            )

            # 7. How much of the posterior came from the analyst prior (%)
            prior_weight_pct: float = round(prior_precision / posterior_precision * 100, 1)

            return {
                "symbol": symbol,
                "current_price": round(current_price, 2),
                "horizon_days": horizon_days,
                "analyst_target": round(analyst_target, 2),
                "analyst_confidence": analyst_confidence,
                "data_implied_target": round(data_target, 2),
                "posterior_mean": round(posterior_mean, 2),
                "posterior_std": round(posterior_std, 2),
                "credible_interval_90": [ci_low, ci_high],
                "prob_above_analyst": round(prob_above_analyst, 4),
                "annualised_vol": round(sigma_data * sqrt(252) * 100, 2),
                "prior_weight_pct": prior_weight_pct,
            }

        except Exception as e:
            logger.error(
                f"BayesianService.update_price_target error for {symbol}: {e}",
                exc_info=True,
            )
            return {"symbol": symbol, "error": str(e)}
