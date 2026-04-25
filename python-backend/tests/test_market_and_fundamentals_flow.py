"""HTTP-flow tests for stock/crypto detail payloads."""

from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.models.stock import Candle, Quote, StockInfo
from app.routers import fundamentals, market
from app.utils.cache import cache_manager


@pytest.fixture(autouse=True)
def clear_cache():
    cache_manager.clear()
    yield
    cache_manager.clear()


@pytest.fixture
def client():
    return TestClient(app)


def _build_candles(symbol: str, count: int, start_price: float = 100.0):
    start = datetime(2026, 1, 1)
    candles = []
    for i in range(count):
        price = start_price + i
        candles.append(
            Candle(
                symbol=symbol,
                timestamp=start + timedelta(days=i),
                open=price - 1,
                high=price + 1,
                low=price - 2,
                close=price,
                volume=1_000_000 + i,
            )
        )
    return candles


def test_market_range_flow_includes_volume_and_market_cap_for_stock(client, monkeypatch):
    quote = Quote(
        symbol="AAPL",
        price=210.0,
        change=1.5,
        change_percent=0.72,
        volume=123_456_789,
        market_cap=3_200_000_000_000.0,
        high=212.0,
        low=207.5,
        open=208.0,
        previous_close=208.5,
    )

    async def fake_get_quote(symbol):
        return quote

    async def fake_get_candles(symbol, interval="1d", limit=365):
        return _build_candles(symbol, 365, start_price=100.0)

    monkeypatch.setattr(market.data_fetcher, "get_quote", fake_get_quote)
    monkeypatch.setattr(market.data_fetcher, "get_candles", fake_get_candles)

    response = client.get("/api/market/range/AAPL")

    assert response.status_code == 200
    data = response.json()
    assert data["symbol"] == "AAPL"
    assert data["current_price"] == 210.0
    assert data["volume"] == 123456789
    assert data["market_cap"] == 3200000000000.0
    assert data["day_high"] == 212.0
    assert data["day_low"] == 207.5
    assert data["year_high"] == 465.0
    assert data["year_low"] == 98.0


def test_market_range_flow_includes_volume_and_market_cap_for_crypto(client, monkeypatch):
    quote = Quote(
        symbol="BTC",
        price=94_500.0,
        change=1_200.0,
        change_percent=1.29,
        volume=42_000,
        market_cap=1_870_000_000_000.0,
        high=95_250.0,
        low=92_800.0,
        open=93_100.0,
        previous_close=93_300.0,
    )

    async def fake_get_quote(symbol):
        return quote

    async def fake_get_crypto_year_range(symbol):
        return {"year_high": 109_000.0, "year_low": 49_500.0}

    monkeypatch.setattr(market.data_fetcher, "get_quote", fake_get_quote)
    monkeypatch.setattr(market, "_get_crypto_year_range", fake_get_crypto_year_range)

    response = client.get("/api/market/range/BTC")

    assert response.status_code == 200
    data = response.json()
    assert data["symbol"] == "BTC"
    assert data["volume"] == 42000
    assert data["market_cap"] == 1870000000000.0
    assert data["day_high"] == 95250.0
    assert data["day_low"] == 92800.0
    assert data["year_high"] == 109000.0
    assert data["year_low"] == 49500.0


@pytest.mark.xfail(reason="Current market range route never falls back to stock-info market cap when quote.market_cap is missing.")
def test_market_range_should_fall_back_to_stock_info_market_cap(client, monkeypatch):
    quote = Quote(
        symbol="AAPL",
        price=210.0,
        change=1.5,
        change_percent=0.72,
        volume=123_456_789,
        market_cap=None,
        high=212.0,
        low=207.5,
        open=208.0,
        previous_close=208.5,
    )

    async def fake_get_quote(symbol):
        return quote

    async def fake_get_candles(symbol, interval="1d", limit=365):
        return _build_candles(symbol, 365, start_price=100.0)

    async def fake_get_stock_info(symbol):
        return StockInfo(symbol=symbol, name="Apple Inc.", market_cap=3_200_000_000_000.0)

    monkeypatch.setattr(market.data_fetcher, "get_quote", fake_get_quote)
    monkeypatch.setattr(market.data_fetcher, "get_candles", fake_get_candles)
    monkeypatch.setattr(market.data_fetcher, "get_stock_info", fake_get_stock_info)

    response = client.get("/api/market/range/AAPL")

    assert response.status_code == 200
    assert response.json()["market_cap"] == 3200000000000.0


@pytest.mark.xfail(reason="Turnover stays blank when quote volume is missing because the route does not fall back to recent candle volume.")
def test_market_range_should_fall_back_to_latest_candle_volume(client, monkeypatch):
    quote = Quote(
        symbol="AAPL",
        price=210.0,
        change=1.5,
        change_percent=0.72,
        volume=None,
        market_cap=3_200_000_000_000.0,
        high=212.0,
        low=207.5,
        open=208.0,
        previous_close=208.5,
    )
    candles = _build_candles("AAPL", 365, start_price=100.0)

    async def fake_get_quote(symbol):
        return quote

    async def fake_get_candles(symbol, interval="1d", limit=365):
        return candles

    monkeypatch.setattr(market.data_fetcher, "get_quote", fake_get_quote)
    monkeypatch.setattr(market.data_fetcher, "get_candles", fake_get_candles)

    response = client.get("/api/market/range/AAPL")

    assert response.status_code == 200
    assert response.json()["volume"] == candles[-1].volume


def test_fundamentals_route_preserves_plausible_high_roe(client, monkeypatch):
    async def fake_get_fundamentals(symbol):
        return {
            "symbol": symbol,
            "is_crypto": False,
            "current_price": 210.0,
            "market_cap": 3_200_000_000_000.0,
            "ratios": {
                "pe": 28.1,
                "ps": 7.9,
                "gross_margin": 46.9,
                "net_margin": 26.9,
                "operating_margin": 32.0,
                "roe": 151.9,
                "debt_equity": 1.63,
                "current_ratio": 0.93,
            },
            "ttm": {"revenue": 416_160_000_000.0, "net_income": 112_010_000_000.0, "eps": 7.46},
            "latest_quarter": {"date": "2025-09-27", "revenue": 101_000_000_000.0, "eps": 1.57},
            "quarterly_eps": [],
        }

    monkeypatch.setattr(fundamentals.fund_svc, "get_fundamentals", fake_get_fundamentals)

    response = client.get("/api/fundamentals/AAPL")

    assert response.status_code == 200
    data = response.json()
    assert data["ratios"]["roe"] == 151.9
    assert data["market_cap"] == 3200000000000.0


def test_fundamentals_route_sanitizes_absurd_roe(client, monkeypatch):
    async def fake_get_fundamentals(symbol):
        return {
            "symbol": symbol,
            "is_crypto": False,
            "current_price": 210.0,
            "market_cap": 3_200_000_000_000.0,
            "ratios": {"roe": 13355.0, "pe": 28.1},
            "ttm": {},
            "latest_quarter": {},
            "quarterly_eps": [],
        }

    monkeypatch.setattr(fundamentals.fund_svc, "get_fundamentals", fake_get_fundamentals)

    response = client.get("/api/fundamentals/AAPL")

    assert response.status_code == 200
    assert response.json()["ratios"]["roe"] is None
