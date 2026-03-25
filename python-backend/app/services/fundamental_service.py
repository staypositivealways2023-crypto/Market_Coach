"""Fundamental Analysis Service — key ratios + TTM financials.

Primary source: Massive vX/reference/financials (requires higher-tier plan).
Fallback:       yfinance (free, works on Starter).
"""

import asyncio
from typing import Optional
from datetime import datetime
import logging

import aiohttp
import yfinance as yf

from app.config import settings
from app.services.massive_service import MassiveService

logger = logging.getLogger(__name__)

BASE_URL = "https://api.polygon.io"

_CRYPTO = {
    "BTC", "ETH", "BNB", "SOL", "ADA", "XRP", "DOGE", "DOT",
    "AVAX", "MATIC", "LINK", "UNI", "LTC", "BCH", "XLM",
}


class FundamentalService:
    def __init__(self):
        self.api_key = settings.MASSIVE_API_KEY
        self._massive = MassiveService()

    @property
    def is_configured(self) -> bool:
        return bool(self.api_key)

    def _is_crypto(self, symbol: str) -> bool:
        return symbol.upper() in _CRYPTO or "-" in symbol

    # ── Public ────────────────────────────────────────────────────────────────

    async def get_fundamentals(self, symbol: str) -> dict:
        sym = symbol.upper()
        if self._is_crypto(sym):
            return await self._crypto_fundamentals(sym)
        return await self._stock_fundamentals(sym)

    # ── Stocks ────────────────────────────────────────────────────────────────

    async def _stock_fundamentals(self, symbol: str) -> dict:
        # Try Massive first (requires Starter+ plan for financials endpoint)
        financials, quote = await asyncio.gather(
            self._fetch_massive_financials(symbol, limit=8),
            self._massive.get_quote(symbol),
            return_exceptions=True,
        )

        if isinstance(financials, Exception):
            financials = []
        if isinstance(quote, Exception):
            quote = None

        current_price = quote.price if quote else 0.0

        if financials:
            return self._build_from_massive(symbol, current_price, financials)

        # Fallback: yfinance
        logger.info(f"Falling back to yfinance fundamentals for {symbol}")
        return await self._yfinance_fundamentals(symbol, current_price)

    async def _fetch_massive_financials(self, symbol: str, limit: int = 8) -> list:
        if not self.is_configured:
            return []
        try:
            url = f"{BASE_URL}/vX/reference/financials"
            params = {
                "ticker": symbol,
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
            return data.get("results", [])
        except Exception as e:
            logger.error(f"Massive financials error {symbol}: {e}")
            return []

    def _build_from_massive(self, symbol: str, current_price: float, financials: list) -> dict:
        """Build fundamentals response from Massive financials data."""
        ttm_quarters = financials[:4]
        ttm_rev    = _sum_field(ttm_quarters, "income_statement", "revenues")
        ttm_ni     = _sum_field(ttm_quarters, "income_statement", "net_income_loss")
        ttm_eps    = _sum_field(ttm_quarters, "income_statement", "diluted_earnings_per_share")
        ttm_opinc  = _sum_field(ttm_quarters, "income_statement", "operating_income_loss")
        ttm_gross  = _sum_field(ttm_quarters, "income_statement", "gross_profit")

        latest = financials[0]
        bs = latest.get("financials", {}).get("balance_sheet", {})
        equity      = _val(bs, "equity")
        cur_assets  = _val(bs, "current_assets")
        cur_liab    = _val(bs, "current_liabilities")
        liabilities = _val(bs, "liabilities")

        # Market cap: Massive financials don't include it, fetch from yfinance
        mkt_cap = None
        try:
            ticker_info = yf.Ticker(symbol).info
            mkt_cap = ticker_info.get("marketCap")
        except Exception:
            pass

        # P/E only meaningful when EPS is positive
        pe  = _safe_div(current_price, ttm_eps) if ttm_eps and ttm_eps > 0 else None
        ps  = _safe_div(mkt_cap, ttm_rev) if mkt_cap and ttm_rev else None
        gm  = _pct(ttm_gross, ttm_rev)
        nm  = _pct(ttm_ni, ttm_rev)
        om  = _pct(ttm_opinc, ttm_rev)
        roe = _pct(ttm_ni, equity)
        de  = _safe_div(liabilities, equity) if liabilities and equity else None
        cr  = _safe_div(cur_assets, cur_liab) if cur_assets and cur_liab else None

        quarterly_eps = []
        for q in reversed(financials[:8]):
            period = q.get("period_of_report_date", "")
            eps_val = _val(
                q.get("financials", {}).get("income_statement", {}),
                "diluted_earnings_per_share"
            ) or _val(
                q.get("financials", {}).get("income_statement", {}),
                "basic_earnings_per_share"
            )
            quarterly_eps.append({
                "period": _quarter_label(period),
                "report_date": period,
                "eps": round(eps_val, 4) if eps_val is not None else None,
                "revenue": _val(q.get("financials", {}).get("income_statement", {}), "revenues"),
            })

        return {
            "symbol": symbol,
            "is_crypto": False,
            "current_price": current_price,
            "market_cap": mkt_cap,
            "ratios": {
                "pe": _r(pe), "ps": _r(ps),
                "gross_margin": _r(gm), "net_margin": _r(nm),
                "operating_margin": _r(om), "roe": _r(roe),
                "debt_equity": _r(de), "current_ratio": _r(cr),
            },
            "ttm": {
                "revenue": ttm_rev, "net_income": ttm_ni,
                "eps": _r(ttm_eps), "operating_income": ttm_opinc,
            },
            "latest_quarter": {
                "date": latest.get("period_of_report_date"),
                "revenue": _val(latest.get("financials", {}).get("income_statement", {}), "revenues"),
                "eps": _r(_val(latest.get("financials", {}).get("income_statement", {}), "diluted_earnings_per_share")),
            },
            "quarterly_eps": quarterly_eps,
            "fetched_at": datetime.utcnow().isoformat(),
        }

    async def _yfinance_fundamentals(self, symbol: str, current_price: float) -> dict:
        """yfinance fallback — uses ticker.info + quarterly financials."""
        def _fetch():
            try:
                ticker = yf.Ticker(symbol)
                info = ticker.info or {}
            except Exception as e:
                logger.error(f"yfinance ticker.info error for {symbol}: {e}")
                return {}, []

            # Quarterly income statement
            quarterly_eps_list = []
            try:
                import pandas as pd
                stmt = getattr(ticker, "quarterly_income_stmt", None)
                if stmt is None or (hasattr(stmt, "empty") and stmt.empty):
                    stmt = getattr(ticker, "quarterly_financials", None)

                if stmt is not None and hasattr(stmt, "empty") and not stmt.empty:
                    eps_row = None
                    rev_row = None
                    for label in ["Diluted EPS", "Basic EPS", "Basic EPS (USD)"]:
                        if label in stmt.index:
                            eps_row = stmt.loc[label]
                            break
                    for label in ["Total Revenue", "Revenue", "Operating Revenue"]:
                        if label in stmt.index:
                            rev_row = stmt.loc[label]
                            break

                    dates = list(stmt.columns[:8])  # newest first
                    for dt in reversed(dates):       # oldest→newest for chart
                        period = dt.strftime("%Y-%m-%d") if hasattr(dt, "strftime") else str(dt)
                        eps_val = None
                        rev_val = None
                        if eps_row is not None and dt in eps_row.index:
                            v = eps_row[dt]
                            if not pd.isna(v):
                                eps_val = float(v)
                        if rev_row is not None and dt in rev_row.index:
                            v = rev_row[dt]
                            if not pd.isna(v):
                                rev_val = float(v)
                        quarterly_eps_list.append({
                            "period": _quarter_label(period),
                            "report_date": period,
                            "eps": round(eps_val, 4) if eps_val is not None else None,
                            "revenue": rev_val,
                        })
            except Exception as e:
                logger.warning(f"yfinance quarterly earnings error for {symbol}: {e}")

            return info, quarterly_eps_list

        loop = asyncio.get_event_loop()
        info, quarterly_eps = await loop.run_in_executor(None, _fetch)

        if not info:
            return _empty_stock(symbol, current_price)

        # Use live price if we didn't get one from Massive quote
        if current_price == 0.0:
            current_price = float(info.get("regularMarketPrice") or info.get("currentPrice") or 0.0)

        mkt_cap    = info.get("marketCap")
        ttm_rev    = info.get("totalRevenue")
        ttm_ni     = info.get("netIncomeToCommon")
        ttm_eps    = info.get("trailingEps")
        gross_p    = info.get("grossProfits")

        # yfinance returns margins/ratios as decimals (0.0 – 1.0), multiply by 100 for %
        gm  = _to_pct(info.get("grossMargins"))
        nm  = _to_pct(info.get("profitMargins"))
        om  = _to_pct(info.get("operatingMargins"))
        roe = _to_pct(info.get("returnOnEquity"))

        # P/E: prefer trailingPE; if zero/missing compute from price ÷ EPS; null if unavailable
        pe = info.get("trailingPE")
        if not pe or pe <= 0:
            trailing_eps = info.get("trailingEps")
            if trailing_eps and trailing_eps > 0 and current_price > 0:
                pe = current_price / trailing_eps
            else:
                pe = None  # never store 0 — null means unavailable

        # P/S from market cap / revenue
        ps  = _safe_div(mkt_cap, ttm_rev) if mkt_cap and ttm_rev else info.get("priceToSalesTrailing12Months")
        de  = info.get("debtToEquity")  # already as ratio
        if de is not None:
            de = de / 100.0  # yfinance returns as e.g. 163 meaning 1.63
        cr  = info.get("currentRatio")

        # Latest quarter date
        lq_date = None
        try:
            mfd = info.get("mostRecentQuarter")
            if mfd:
                lq_date = datetime.utcfromtimestamp(mfd).strftime("%Y-%m-%d")
        except Exception:
            pass

        return {
            "symbol": symbol,
            "is_crypto": False,
            "current_price": current_price,
            "market_cap": mkt_cap,
            "ratios": {
                "pe": _r(pe), "ps": _r(ps),
                "gross_margin": _r(gm), "net_margin": _r(nm),
                "operating_margin": _r(om), "roe": _r(roe),
                "debt_equity": _r(de), "current_ratio": _r(cr),
            },
            "ttm": {
                "revenue": ttm_rev, "net_income": ttm_ni,
                "eps": _r(ttm_eps),
                "gross_profit": gross_p,
            },
            "latest_quarter": {
                "date": lq_date,
                "revenue": ttm_rev,
                "eps": _r(ttm_eps),
            },
            "quarterly_eps": quarterly_eps,
            "fetched_at": datetime.utcnow().isoformat(),
        }

    # ── Crypto ────────────────────────────────────────────────────────────────

    async def _crypto_fundamentals(self, symbol: str) -> dict:
        quote = await self._massive.get_quote(symbol)
        market_cap = getattr(quote, "market_cap", None) if quote else None
        # yfinance fallback for market cap (e.g. BTC-USD)
        if market_cap is None:
            yf_sym = symbol if "-" in symbol else f"{symbol}-USD"
            try:
                info = await asyncio.get_event_loop().run_in_executor(
                    None, lambda: yf.Ticker(yf_sym).info
                )
                market_cap = info.get("marketCap")
            except Exception:
                pass
        return {
            "symbol": symbol,
            "is_crypto": True,
            "current_price": quote.price if quote else 0.0,
            "market_cap": market_cap,
            "ratios": {}, "ttm": {}, "latest_quarter": {},
            "quarterly_eps": [],
            "fetched_at": datetime.utcnow().isoformat(),
        }


# ── Helpers ───────────────────────────────────────────────────────────────────

def _empty_stock(symbol: str, price: float) -> dict:
    return {
        "symbol": symbol, "is_crypto": False,
        "current_price": price, "market_cap": None,
        "ratios": {}, "ttm": {}, "latest_quarter": {}, "quarterly_eps": [],
        "fetched_at": datetime.utcnow().isoformat(),
    }


def _val(obj: dict, key: str) -> Optional[float]:
    field = obj.get(key)
    if not field:
        return None
    v = field.get("value")
    return float(v) if v is not None else None


def _sum_field(quarters: list, statement: str, key: str) -> Optional[float]:
    total = 0.0
    found = False
    for q in quarters:
        v = _val(q.get("financials", {}).get(statement, {}), key)
        if v is not None:
            total += v
            found = True
    return total if found else None


def _safe_div(a, b) -> Optional[float]:
    if a is None or b is None or b == 0:
        return None
    return a / b


def _pct(num, denom) -> Optional[float]:
    result = _safe_div(num, denom)
    return result * 100 if result is not None else None


def _to_pct(v) -> Optional[float]:
    """Convert yfinance decimal ratio (e.g. 0.42) to percentage (42.0).
    Guards against yfinance version drift where the value is already a percentage
    (e.g. returnOnEquity = 133.55 instead of 1.3355 on newer yfinance builds).
    If abs(v) > 5 we assume the provider already sent a percentage and skip multiplication.
    """
    if v is None:
        return None
    fv = float(v)
    if abs(fv) > 5:          # already in percentage form — do not multiply again
        return round(fv, 2)
    return round(fv * 100, 2)


def _r(v) -> Optional[float]:
    return round(v, 2) if v is not None else None


def _quarter_label(date_str: str) -> str:
    try:
        from datetime import date
        d = date.fromisoformat(date_str[:10])
        return f"Q{(d.month - 1) // 3 + 1} {d.year}"
    except Exception:
        return date_str
