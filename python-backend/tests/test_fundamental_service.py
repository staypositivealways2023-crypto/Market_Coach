"""Regression tests for fundamental data normalization."""

from datetime import datetime, timezone

import pandas as pd
import pytest

from app.services import fundamental_service
from app.services.fundamental_service import FundamentalService, _to_pct


def test_to_pct_converts_decimal_ratio_to_percentage():
    assert _to_pct(0.421) == 42.1


def test_to_pct_preserves_already_percentage_values():
    assert _to_pct(133.55) == 133.55


@pytest.mark.asyncio
async def test_yfinance_fundamentals_preserves_large_roe_percent(monkeypatch):
    quarterly_stmt = pd.DataFrame(
        {
            pd.Timestamp("2025-09-27"): [1.57, 101_000_000_000.0],
            pd.Timestamp("2025-06-28"): [1.43, 96_000_000_000.0],
        },
        index=["Diluted EPS", "Total Revenue"],
    )

    class FakeTicker:
        info = {
            "regularMarketPrice": 210.0,
            "marketCap": 3_200_000_000_000.0,
            "totalRevenue": 416_160_000_000.0,
            "netIncomeToCommon": 112_010_000_000.0,
            "trailingEps": 7.46,
            "grossProfits": 195_201_000_000.0,
            "grossMargins": 0.469,
            "profitMargins": 0.269,
            "operatingMargins": 0.320,
            "returnOnEquity": 133.55,
            "debtToEquity": 163.0,
            "currentRatio": 0.93,
            "mostRecentQuarter": int(datetime(2025, 9, 27, tzinfo=timezone.utc).timestamp()),
        }
        quarterly_income_stmt = quarterly_stmt

    monkeypatch.setattr(fundamental_service.yf, "Ticker", lambda symbol: FakeTicker())

    service = FundamentalService()
    data = await service._yfinance_fundamentals("AAPL", current_price=0.0)

    assert data["symbol"] == "AAPL"
    assert data["current_price"] == 210.0
    assert data["market_cap"] == 3_200_000_000_000.0
    assert data["ratios"]["roe"] == 133.55
    assert data["ratios"]["gross_margin"] == 46.9
    assert data["ratios"]["net_margin"] == 26.9
    assert data["ratios"]["operating_margin"] == 32.0
    assert data["ratios"]["debt_equity"] == 1.63
    assert data["latest_quarter"]["date"] == "2025-09-27"
    assert len(data["quarterly_eps"]) == 2


@pytest.mark.asyncio
async def test_yfinance_fundamentals_converts_decimal_roe(monkeypatch):
    class FakeTicker:
        info = {
            "regularMarketPrice": 100.0,
            "marketCap": 500_000_000_000.0,
            "totalRevenue": 100_000_000_000.0,
            "trailingEps": 5.0,
            "grossMargins": 0.40,
            "profitMargins": 0.20,
            "operatingMargins": 0.25,
            "returnOnEquity": 0.421,
            "debtToEquity": 80.0,
            "currentRatio": 1.2,
        }
        quarterly_income_stmt = pd.DataFrame()

    monkeypatch.setattr(fundamental_service.yf, "Ticker", lambda symbol: FakeTicker())

    service = FundamentalService()
    data = await service._yfinance_fundamentals("MSFT", current_price=0.0)

    assert data["ratios"]["roe"] == 42.1
    assert data["ratios"]["debt_equity"] == 0.8


@pytest.mark.asyncio
async def test_crypto_fundamentals_include_market_cap(monkeypatch):
    class QuoteStub:
        price = 94_000.0
        market_cap = 1_850_000_000_000.0

    async def fake_get_quote(symbol):
        return QuoteStub()

    service = FundamentalService()
    monkeypatch.setattr(service._massive, "get_quote", fake_get_quote)

    data = await service._crypto_fundamentals("BTC")

    assert data["symbol"] == "BTC"
    assert data["is_crypto"] is True
    assert data["current_price"] == 94_000.0
    assert data["market_cap"] == 1_850_000_000_000.0
    assert data["ratios"] == {}
