"""Earnings Service — historical EPS + upcoming earnings dates"""

import aiohttp
import yfinance as yf
from typing import Optional, List
from datetime import datetime, date
import logging

from app.config import settings

logger = logging.getLogger(__name__)

BASE_URL = "https://api.polygon.io"


class EarningsResult:
    def __init__(
        self,
        period: str,           # e.g. "Q4 2025"
        report_date: str,      # ISO date string
        eps_actual: Optional[float],
        eps_estimate: Optional[float],
        eps_surprise: Optional[float],   # actual - estimate
        eps_surprise_pct: Optional[float],
        revenue_actual: Optional[float],
        revenue_estimate: Optional[float],
        net_income: Optional[float],
    ):
        self.period = period
        self.report_date = report_date
        self.eps_actual = eps_actual
        self.eps_estimate = eps_estimate
        self.eps_surprise = eps_surprise
        self.eps_surprise_pct = eps_surprise_pct
        self.revenue_actual = revenue_actual
        self.revenue_estimate = revenue_estimate
        self.net_income = net_income

    def to_dict(self):
        return self.__dict__


class UpcomingEarnings:
    def __init__(
        self,
        symbol: str,
        earnings_date: Optional[str],
        eps_estimate: Optional[float],
        revenue_estimate: Optional[float],
    ):
        self.symbol = symbol
        self.earnings_date = earnings_date
        self.eps_estimate = eps_estimate
        self.revenue_estimate = revenue_estimate

    def to_dict(self):
        return self.__dict__


class EarningsService:

    def __init__(self):
        self.api_key = settings.MASSIVE_API_KEY

    @property
    def is_configured(self) -> bool:
        return bool(self.api_key)

    async def get_historical_earnings(
        self, symbol: str, limit: int = 8
    ) -> List[EarningsResult]:
        """Quarterly EPS history from Massive financials API"""
        if not self.is_configured:
            return []

        try:
            url = f"{BASE_URL}/vX/reference/financials"
            params = {
                "ticker": symbol.upper(),
                "timeframe": "quarterly",
                "limit": limit,
                "sort": "period_of_report_date",
                "order": "desc",
                "apiKey": self.api_key,
            }

            async with aiohttp.ClientSession() as session:
                async with session.get(url, params=params) as resp:
                    if resp.status != 200:
                        logger.warning(f"Massive financials {symbol}: HTTP {resp.status}")
                        return []
                    data = await resp.json()

            results = []
            for item in data.get("results", []):
                report_date = item.get("period_of_report_date", "")
                financials = item.get("financials", {})
                income = financials.get("income_statement", {})

                eps = _extract(income, "diluted_earnings_per_share") or \
                      _extract(income, "basic_earnings_per_share")
                revenue = _extract(income, "revenues")
                net_income = _extract(income, "net_income_loss")

                # Derive quarter label from report date
                period = _quarter_label(report_date)

                results.append(EarningsResult(
                    period=period,
                    report_date=report_date,
                    eps_actual=eps,
                    eps_estimate=None,       # Massive free tier doesn't include estimates
                    eps_surprise=None,
                    eps_surprise_pct=None,
                    revenue_actual=revenue,
                    revenue_estimate=None,
                    net_income=net_income,
                ))

            logger.info(f"Fetched {len(results)} earnings quarters for {symbol}")
            return results

        except Exception as e:
            logger.error(f"Earnings history error for {symbol}: {e}")
            return []

    async def get_upcoming_earnings(self, symbol: str) -> UpcomingEarnings:
        """Next earnings date + estimates via yfinance"""
        result = UpcomingEarnings(
            symbol=symbol.upper(),
            earnings_date=None,
            eps_estimate=None,
            revenue_estimate=None,
        )

        try:
            ticker = yf.Ticker(symbol)

            # yfinance calendar returns a DataFrame or dict
            calendar = ticker.calendar
            if calendar is not None and not _is_empty(calendar):
                if hasattr(calendar, 'get'):
                    # dict format
                    earnings_date = calendar.get("Earnings Date")
                    if earnings_date:
                        if hasattr(earnings_date, '__iter__') and not isinstance(earnings_date, str):
                            earnings_date = list(earnings_date)[0]
                        result.earnings_date = str(earnings_date)[:10]
                    result.eps_estimate = calendar.get("EPS Estimate")
                    result.revenue_estimate = calendar.get("Revenue Estimate")
                else:
                    # DataFrame format — transpose to get values
                    cal_dict = calendar.to_dict()
                    for col, values in cal_dict.items():
                        v = list(values.values())[0] if values else None
                        if "Earnings Date" in col and v:
                            result.earnings_date = str(v)[:10]
                        elif "EPS Estimate" in col:
                            result.eps_estimate = v
                        elif "Revenue Estimate" in col:
                            result.revenue_estimate = v

        except Exception as e:
            logger.warning(f"Upcoming earnings error for {symbol}: {e}")

        return result

    async def get_earnings_summary(self, symbol: str, history_limit: int = 8) -> dict:
        """Combined: upcoming date + historical EPS — used by the endpoint"""
        import asyncio

        upcoming, history = await asyncio.gather(
            self.get_upcoming_earnings(symbol),
            self.get_historical_earnings(symbol, limit=history_limit),
        )

        return {
            "symbol": symbol.upper(),
            "upcoming": upcoming.to_dict(),
            "history": [e.to_dict() for e in history],
            "fetched_at": datetime.utcnow().isoformat(),
        }


# ── Helpers ───────────────────────────────────────────────────────────────────

def _extract(income: dict, key: str) -> Optional[float]:
    """Safely extract a numeric value from Massive financials income dict"""
    field = income.get(key)
    if not field:
        return None
    val = field.get("value")
    return float(val) if val is not None else None


def _quarter_label(report_date: str) -> str:
    """Convert '2025-09-30' → 'Q4 2025'"""
    try:
        d = date.fromisoformat(report_date)
        q = (d.month - 1) // 3 + 1
        return f"Q{q} {d.year}"
    except Exception:
        return report_date


def _is_empty(obj) -> bool:
    try:
        if hasattr(obj, "empty"):
            return obj.empty
        return not obj
    except Exception:
        return True
