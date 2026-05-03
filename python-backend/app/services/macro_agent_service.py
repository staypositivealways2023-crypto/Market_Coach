"""MacroAgent — macro regime classifier and drift/vol multiplier engine.

Reads FRED indicators (fed_funds_rate, yield_curve, inflation_yoy,
unemployment, gdp_growth) and classifies the current macro regime.
Returns regime label, per-indicator signals, a 0-100 risk score, and
drift_adj / vol_adj multipliers for use in Monte Carlo simulations.

Regime table
────────────────────────────────────────────────────────────────────────────
Label                  drift_adj   vol_adj   Typical conditions
────────────────────────────────────────────────────────────────────────────
EXPANSION_EASY          1.20        0.90     GDP ↑, rates low,  curve normal
EXPANSION_TIGHTENING    1.00        1.00     GDP ↑, rates rising, curve flat
LATE_CYCLE              0.80        1.20     Curve inverted, tightening
STAGFLATION             0.70        1.30     Inflation ↑, GDP weak/flat
RECESSION_EASING        0.60        1.40     GDP ↓, rates falling
RECESSION_TIGHTENING    0.40        1.60     GDP ↓, rates still high
────────────────────────────────────────────────────────────────────────────
"""

import logging
from typing import Optional

from app.services.fred_service import FredService, SERIES

logger = logging.getLogger(__name__)

# ── Regime definitions ────────────────────────────────────────────────────────
# Each entry: (label, drift_adj, vol_adj, description)
REGIMES = {
    "EXPANSION_EASY":         (1.20, 0.90, "Growing economy, accommodative policy, normal yield curve."),
    "EXPANSION_TIGHTENING":   (1.00, 1.00, "Growing economy but policy tightening; balanced outlook."),
    "LATE_CYCLE":             (0.80, 1.20, "Inverted yield curve signals late-cycle; elevated risk."),
    "STAGFLATION":            (0.70, 1.30, "High inflation with weak growth; equity headwinds."),
    "RECESSION_EASING":       (0.60, 1.40, "Contraction with easing policy; recovery potential but uncertainty high."),
    "RECESSION_TIGHTENING":   (0.40, 1.60, "Contraction with restrictive policy; maximum macro headwind."),
}

# ── Thresholds ────────────────────────────────────────────────────────────────
RESTRICTIVE_RATE   = 4.0   # fed_funds_rate (%) above this = tight policy
HIGH_INFLATION     = 4.0   # inflation_yoy (%) above this = high inflation
WEAK_UNEMPLOYMENT  = 6.0   # unemployment (%) above this = labour weakness
CONTRACTION_GDP    = 0.0   # gdp_growth (%) below this = contraction
INVERTED_CURVE     = 0.0   # T10Y2Y (%) below this = inverted


class MacroAgentService:
    """Classifies the macro regime and produces Monte Carlo adjustment factors."""

    def __init__(self):
        self._fred = FredService()

    # ── Public API ────────────────────────────────────────────────────────────

    async def assess_regime(self, symbol: str) -> dict:
        """
        Assess the current macro regime.

        Parameters
        ----------
        symbol : str
            Ticker being analysed (used for logging context only —
            the macro regime is market-wide).

        Returns
        -------
        dict with keys:
            symbol, regime, drift_adj, vol_adj, risk_score (0-100),
            signals, description, data_availability,
            interpretation (human-readable summary string)

        On error returns {"symbol": symbol, "error": <message>}.
        """
        try:
            # 1. Fetch FRED overview (cached 1 hr by macro router)
            overview = await self._fred.get_macro_overview()

            # 2. Extract latest values (None if unavailable)
            def _val(key: str) -> Optional[float]:
                entry = overview.get(key)
                if entry and isinstance(entry, dict):
                    return entry.get("value")
                return None

            fed_rate    = _val("fed_funds_rate")
            yield_curve = _val("yield_curve")
            inflation   = _val("inflation_yoy")
            unemployment = _val("unemployment")
            gdp_growth  = _val("gdp_growth")

            # 3. Build boolean signals (None = data unavailable → treated conservatively)
            inverted      = (yield_curve  is not None) and (yield_curve  < INVERTED_CURVE)
            restrictive   = (fed_rate     is not None) and (fed_rate     > RESTRICTIVE_RATE)
            high_inf      = (inflation    is not None) and (inflation    > HIGH_INFLATION)
            weak_labour   = (unemployment is not None) and (unemployment > WEAK_UNEMPLOYMENT)
            contraction   = (gdp_growth   is not None) and (gdp_growth   < CONTRACTION_GDP)

            signals = {
                "yield_curve_inverted":   inverted,
                "policy_restrictive":     restrictive,
                "high_inflation":         high_inf,
                "labour_market_weak":     weak_labour,
                "gdp_contraction":        contraction,
            }

            # 4. Classify regime (precedence order — most severe first)
            if contraction and restrictive:
                regime = "RECESSION_TIGHTENING"
            elif contraction:
                regime = "RECESSION_EASING"
            elif high_inf and not contraction:
                regime = "STAGFLATION"
            elif inverted and restrictive:
                regime = "LATE_CYCLE"
            elif restrictive:
                regime = "EXPANSION_TIGHTENING"
            else:
                regime = "EXPANSION_EASY"

            drift_adj, vol_adj, description = REGIMES[regime]

            # 5. Risk score (0 = benign, 100 = maximum headwind)
            # Each bearish signal contributes points; severity weighted
            score = 0
            if contraction:    score += 30
            if restrictive:    score += 20
            if inverted:       score += 20
            if high_inf:       score += 15
            if weak_labour:    score += 15
            risk_score = min(score, 100)

            # 6. Data availability summary
            data_availability = {
                "fed_funds_rate":  fed_rate    is not None,
                "yield_curve":     yield_curve is not None,
                "inflation_yoy":   inflation   is not None,
                "unemployment":    unemployment is not None,
                "gdp_growth":      gdp_growth  is not None,
            }

            # 7. Human-readable interpretation
            active_signals = [k for k, v in signals.items() if v]
            if active_signals:
                signal_str = ", ".join(s.replace("_", " ") for s in active_signals)
                interpretation = (
                    f"Regime: {regime}. Active bearish signals: {signal_str}. "
                    f"Risk score {risk_score}/100. "
                    f"Monte Carlo drift scaled by {drift_adj:.2f}×, "
                    f"volatility scaled by {vol_adj:.2f}×. {description}"
                )
            else:
                interpretation = (
                    f"Regime: {regime}. No bearish macro signals detected. "
                    f"Risk score {risk_score}/100. "
                    f"Monte Carlo drift scaled by {drift_adj:.2f}×, "
                    f"volatility scaled by {vol_adj:.2f}×. {description}"
                )

            return {
                "symbol":            symbol,
                "regime":            regime,
                "drift_adj":         drift_adj,
                "vol_adj":           vol_adj,
                "risk_score":        risk_score,
                "signals":           signals,
                "description":       description,
                "data_availability": data_availability,
                "raw_values": {
                    "fed_funds_rate":  fed_rate,
                    "yield_curve":     yield_curve,
                    "inflation_yoy":   inflation,
                    "unemployment":    unemployment,
                    "gdp_growth":      gdp_growth,
                },
                "interpretation": interpretation,
            }

        except Exception as e:
            logger.error(
                f"MacroAgentService.assess_regime error for {symbol}: {e}",
                exc_info=True,
            )
            return {"symbol": symbol, "error": str(e)}
