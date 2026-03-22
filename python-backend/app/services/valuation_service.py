"""Valuation Service - DCF and comparative valuation"""

import yfinance as yf
from typing import Optional
import logging

from app.models.valuation import DCFValuation, ValuationMetrics
from app.config import settings

logger = logging.getLogger(__name__)


class ValuationService:
    """Calculate intrinsic value and valuation metrics"""

    def __init__(self):
        self.risk_free_rate = settings.RISK_FREE_RATE
        self.market_risk_premium = settings.MARKET_RISK_PREMIUM

    async def calculate_dcf(self, symbol: str) -> Optional[DCFValuation]:
        """Calculate DCF valuation"""

        try:
            ticker = yf.Ticker(symbol)
            info = ticker.info

            # Get required data
            fcf = info.get('freeCashflow')
            shares = info.get('sharesOutstanding')
            current_price = info.get('regularMarketPrice')
            beta = info.get('beta', 1.0)

            if not fcf or not shares or not current_price:
                logger.warning(f"Insufficient data for DCF on {symbol}")
                return None

            # Calculate WACC
            wacc = self._calculate_wacc(beta, info)

            # Estimate growth rates
            growth_rate = self._estimate_growth_rate(info)
            terminal_growth = 0.03  # 3% terminal growth

            # Calculate intrinsic value
            intrinsic_value = self._dcf_calculation(
                fcf=fcf,
                growth_rate=growth_rate,
                terminal_growth=terminal_growth,
                wacc=wacc,
                shares_outstanding=shares
            )

            # Calculate upside
            upside_percent = ((intrinsic_value - current_price) / current_price) * 100

            # Determine signal
            if upside_percent > 20:
                signal = "undervalued"
                confidence = "high"
            elif upside_percent > 10:
                signal = "undervalued"
                confidence = "medium"
            elif upside_percent < -20:
                signal = "overvalued"
                confidence = "high"
            elif upside_percent < -10:
                signal = "overvalued"
                confidence = "medium"
            else:
                signal = "fair"
                confidence = "medium"

            return DCFValuation(
                symbol=symbol,
                intrinsic_value=round(intrinsic_value, 2),
                current_price=round(current_price, 2),
                upside_percent=round(upside_percent, 2),
                fcf=fcf,
                growth_rate=growth_rate,
                terminal_growth=terminal_growth,
                wacc=wacc,
                shares_outstanding=shares,
                signal=signal,
                confidence=confidence
            )

        except Exception as e:
            logger.error(f"DCF calculation error for {symbol}: {e}")
            return None

    async def calculate_metrics(self, symbol: str) -> Optional[ValuationMetrics]:
        """Calculate comparative valuation metrics"""

        try:
            ticker = yf.Ticker(symbol)
            info = ticker.info

            # Extract metrics
            pe_ratio = info.get('trailingPE')
            pb_ratio = info.get('priceToBook')
            ps_ratio = info.get('priceToSalesTrailing12Months')
            peg_ratio = info.get('pegRatio')

            roe = info.get('returnOnEquity')
            roa = info.get('returnOnAssets')
            profit_margin = info.get('profitMargins')
            operating_margin = info.get('operatingMargins')

            debt_to_equity = info.get('debtToEquity')
            current_ratio = info.get('currentRatio')
            quick_ratio = info.get('quickRatio')

            revenue_growth = info.get('revenueGrowth')
            earnings_growth = info.get('earningsGrowth')

            dividend_yield = info.get('dividendYield')
            payout_ratio = info.get('payoutRatio')

            # Calculate value score
            value_score = self._calculate_value_score(
                pe_ratio=pe_ratio,
                pb_ratio=pb_ratio,
                peg_ratio=peg_ratio,
                roe=roe,
                debt_to_equity=debt_to_equity
            )

            # Assign grade
            grade = self._assign_grade(value_score)

            return ValuationMetrics(
                symbol=symbol,
                pe_ratio=round(pe_ratio, 2) if pe_ratio else None,
                pb_ratio=round(pb_ratio, 2) if pb_ratio else None,
                ps_ratio=round(ps_ratio, 2) if ps_ratio else None,
                peg_ratio=round(peg_ratio, 2) if peg_ratio else None,
                roe=round(roe, 4) if roe else None,
                roa=round(roa, 4) if roa else None,
                profit_margin=round(profit_margin, 4) if profit_margin else None,
                operating_margin=round(operating_margin, 4) if operating_margin else None,
                debt_to_equity=round(debt_to_equity, 2) if debt_to_equity else None,
                current_ratio=round(current_ratio, 2) if current_ratio else None,
                quick_ratio=round(quick_ratio, 2) if quick_ratio else None,
                revenue_growth=round(revenue_growth, 4) if revenue_growth else None,
                earnings_growth=round(earnings_growth, 4) if earnings_growth else None,
                dividend_yield=round(dividend_yield, 4) if dividend_yield else None,
                payout_ratio=round(payout_ratio, 4) if payout_ratio else None,
                value_score=value_score,
                grade=grade
            )

        except Exception as e:
            logger.error(f"Metrics calculation error for {symbol}: {e}")
            return None

    def _calculate_wacc(self, beta: float, info: dict) -> float:
        """Calculate Weighted Average Cost of Capital"""

        # Cost of equity using CAPM
        cost_of_equity = self.risk_free_rate + beta * self.market_risk_premium

        # For simplicity, use cost of equity as WACC
        # In production, you'd include cost of debt and capital structure
        return round(cost_of_equity, 4)

    def _estimate_growth_rate(self, info: dict) -> float:
        """Estimate growth rate from historical data"""

        # Try to get actual growth rate
        revenue_growth = info.get('revenueGrowth')
        earnings_growth = info.get('earningsGrowth')

        if revenue_growth and earnings_growth:
            # Average of revenue and earnings growth
            growth = (revenue_growth + earnings_growth) / 2
        elif revenue_growth:
            growth = revenue_growth
        elif earnings_growth:
            growth = earnings_growth
        else:
            # Default to conservative 5%
            growth = 0.05

        # Cap growth at 30% for safety
        return min(max(growth, 0.03), 0.30)

    def _dcf_calculation(
        self,
        fcf: float,
        growth_rate: float,
        terminal_growth: float,
        wacc: float,
        shares_outstanding: float,
        projection_years: int = 5
    ) -> float:
        """Perform DCF calculation"""

        # Project cash flows
        projected_fcf = []
        for year in range(1, projection_years + 1):
            projected_fcf.append(fcf * ((1 + growth_rate) ** year))

        # Calculate terminal value
        terminal_fcf = projected_fcf[-1] * (1 + terminal_growth)
        terminal_value = terminal_fcf / (wacc - terminal_growth)

        # Discount cash flows
        pv_cash_flows = sum([
            cf / ((1 + wacc) ** (i + 1))
            for i, cf in enumerate(projected_fcf)
        ])

        # Discount terminal value
        pv_terminal_value = terminal_value / ((1 + wacc) ** projection_years)

        # Enterprise value
        enterprise_value = pv_cash_flows + pv_terminal_value

        # Equity value per share
        intrinsic_value = enterprise_value / shares_outstanding

        return intrinsic_value

    def _calculate_value_score(
        self,
        pe_ratio: Optional[float],
        pb_ratio: Optional[float],
        peg_ratio: Optional[float],
        roe: Optional[float],
        debt_to_equity: Optional[float]
    ) -> Optional[float]:
        """Calculate overall value score (0-100)"""

        score = 0
        weights = 0

        # P/E score (lower is better, but not negative)
        if pe_ratio and pe_ratio > 0:
            if pe_ratio < 15:
                score += 25
            elif pe_ratio < 25:
                score += 15
            elif pe_ratio < 35:
                score += 5
            weights += 25

        # P/B score (lower is better)
        if pb_ratio and pb_ratio > 0:
            if pb_ratio < 1:
                score += 20
            elif pb_ratio < 3:
                score += 15
            elif pb_ratio < 5:
                score += 10
            elif pb_ratio < 10:
                score += 5
            weights += 20

        # PEG score (below 1 is good)
        if peg_ratio and peg_ratio > 0:
            if peg_ratio < 1:
                score += 20
            elif peg_ratio < 2:
                score += 10
            weights += 20

        # ROE score (higher is better)
        if roe:
            if roe > 0.20:
                score += 20
            elif roe > 0.15:
                score += 15
            elif roe > 0.10:
                score += 10
            elif roe > 0.05:
                score += 5
            weights += 20

        # Debt score (lower is better)
        if debt_to_equity is not None:
            if debt_to_equity < 0.5:
                score += 15
            elif debt_to_equity < 1.0:
                score += 10
            elif debt_to_equity < 2.0:
                score += 5
            weights += 15

        if weights == 0:
            return None

        # Normalize to 0-100
        normalized_score = (score / weights) * 100
        return round(normalized_score, 2)

    def _assign_grade(self, value_score: Optional[float]) -> Optional[str]:
        """Assign letter grade based on value score"""

        if value_score is None:
            return None

        if value_score >= 80:
            return "A"
        elif value_score >= 70:
            return "B"
        elif value_score >= 60:
            return "C"
        elif value_score >= 50:
            return "D"
        else:
            return "F"
