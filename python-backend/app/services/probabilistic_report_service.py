"""Probabilistic Report Service — unified synthesis of Monte Carlo, Bayesian, and MacroAgent."""

import asyncio
import logging
from datetime import datetime, timezone
from math import exp, log

from app.services.monte_carlo_service import MonteCarloService
from app.services.bayesian_service import BayesianService
from app.services.macro_agent_service import MacroAgentService

logger = logging.getLogger(__name__)


class ProbabilisticReportService:
    """
    Runs Monte Carlo, Bayesian price-target update, and MacroAgent regime
    classification concurrently, then synthesises the results into a single
    consolidated probabilistic report.
    """

    def __init__(
        self,
        monte_carlo_service: MonteCarloService,
        bayesian_service: BayesianService,
        macro_agent_service: MacroAgentService,
    ) -> None:
        self._mc = monte_carlo_service
        self._bayes = bayesian_service
        self._macro = macro_agent_service

    async def generate_report(
        self,
        symbol: str,
        analyst_target: float,
        analyst_confidence: float = 5.0,
        horizon_days: int = 30,
        num_simulations: int = 1000,
    ) -> dict:
        """
        Generate a unified probabilistic synthesis report.

        Args:
            symbol:              Ticker symbol (should be upper-cased by caller).
            analyst_target:      Analyst consensus price target.
            analyst_confidence:  Prior strength (σ in dollars); default 5.0.
            horizon_days:        Simulation horizon in calendar days.
            num_simulations:     Number of GBM paths for Monte Carlo.

        Returns:
            Consolidated dict with keys: symbol, horizon_days, generated_at,
            current_price, macro, monte_carlo, macro_adjusted, bayesian,
            overall_conviction, summary.
            On any error returns {"symbol": symbol, "error": "<description>"}.
        """
        try:
            # ── 1. Run all three engines concurrently ──────────────────────────
            mc_result, bayes_result, macro_result = await asyncio.gather(
                self._mc.simulate(symbol, horizon_days, num_simulations),
                self._bayes.update_price_target(
                    symbol, analyst_target, analyst_confidence, horizon_days
                ),
                self._macro.assess_regime(symbol),
            )

            # ── 2. Propagate engine errors immediately ─────────────────────────
            for name, result in (
                ("monte_carlo", mc_result),
                ("bayesian", bayes_result),
                ("macro_agent", macro_result),
            ):
                if "error" in result:
                    return {"symbol": symbol, "error": f"{name}: {result['error']}"}

            mc = mc_result
            bayes = bayes_result
            macro = macro_result

            # ── 3. Apply macro adjustments to Monte Carlo output ───────────────
            drift_adj: float = macro["drift_adj"]
            vol_adj: float = macro["vol_adj"]
            current_price: float = mc["current_price"]

            # Rescale GBM log-return by drift_adj
            raw_log_return = log(mc["expected_price"] / current_price)
            macro_adjusted_expected_price = round(
                current_price * exp(raw_log_return * drift_adj), 2
            )

            macro_adjusted_vol = round(mc["annualised_vol"] * vol_adj, 2)

            # Adjusted tail prices (vol_adj stretches/compresses the tails)
            bear_log_return = log(mc["percentiles"]["5"] / current_price)
            bull_log_return = log(mc["percentiles"]["95"] / current_price)

            bear_price_5pct = round(current_price * exp(bear_log_return * vol_adj), 2)
            bull_price_95pct = round(current_price * exp(bull_log_return * vol_adj), 2)

            # ── 4. Derive overall_conviction score (0–100) ─────────────────────
            conviction = 50

            if bayes["prob_above_analyst"] > 0.5:
                conviction += 15
            if mc["prob_profit"] > 0.6:
                conviction += 10
            if macro["risk_score"] > 60:
                conviction -= 20
            if macro["risk_score"] > 40:
                conviction -= 10
            if bayes["prior_weight_pct"] > 30:
                conviction += 5

            overall_conviction = max(0, min(100, conviction))

            # ── 5. Assemble and return ─────────────────────────────────────────
            regime: str = macro["regime"]
            risk_score: int = macro["risk_score"]
            bayesian_target: float = bayes["posterior_mean"]

            summary = (
                f"{regime} regime (risk {risk_score}/100) with Bayesian target "
                f"${bayesian_target:.2f} and macro-adjusted expected price "
                f"${macro_adjusted_expected_price:.2f} over {horizon_days} days."
            )

            return {
                "symbol": symbol,
                "horizon_days": horizon_days,
                "generated_at": datetime.now(timezone.utc).isoformat(),
                "current_price": current_price,
                "macro": {
                    "regime": regime,
                    "risk_score": risk_score,
                    "drift_adj": drift_adj,
                    "vol_adj": vol_adj,
                    "signals": macro.get("signals", {}),
                },
                "monte_carlo": {
                    "expected_price": mc["expected_price"],
                    "prob_profit": mc["prob_profit"],
                    "percentiles": mc["percentiles"],
                    "annualised_vol": mc["annualised_vol"],
                },
                "macro_adjusted": {
                    "expected_price": macro_adjusted_expected_price,
                    "annualised_vol": macro_adjusted_vol,
                    "bear_price_5pct": bear_price_5pct,
                    "bull_price_95pct": bull_price_95pct,
                },
                "bayesian": {
                    "posterior_mean": bayes["posterior_mean"],
                    "credible_interval_90": bayes["credible_interval_90"],
                    "prob_above_analyst": bayes["prob_above_analyst"],
                    "prior_weight_pct": bayes["prior_weight_pct"],
                    "data_implied_target": bayes["data_implied_target"],
                },
                "overall_conviction": overall_conviction,
                "summary": summary,
            }

        except Exception as exc:  # noqa: BLE001
            logger.exception("ProbabilisticReportService error for %s", symbol)
            return {"symbol": symbol, "error": str(exc)}
