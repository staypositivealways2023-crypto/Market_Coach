"""Integration-style tests for the indicators API route."""

from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.models.indicator import (
    BollingerBandsData,
    MACDData,
    RSIData,
    TechnicalIndicators,
)
from app.models.stock import Candle, Quote
from app.routers import indicators


@pytest.fixture
def client():
    return TestClient(app)


def _build_candles(count: int):
    start = datetime(2026, 1, 1)
    candles = []

    for i in range(count):
        close = 100 + i
        candles.append(
            Candle(
                symbol="AAPL",
                timestamp=start + timedelta(days=i),
                open=close - 1,
                high=close + 1,
                low=close - 2,
                close=close,
                volume=1000 + i,
            )
        )

    return candles


def test_get_indicators_returns_indicator_payload(client, monkeypatch):
    candles = _build_candles(120)
    captured = {}

    async def fake_get_candles(symbol, interval="1d", limit=100):
        captured["candles_args"] = (symbol, interval, limit)
        return candles

    async def fake_get_quote(symbol):
        captured["quote_arg"] = symbol
        return Quote(
            symbol=symbol,
            price=222.5,
            change=1.5,
            change_percent=0.7,
        )

    def fake_calculate_indicators(symbol, candles, current_price=None):
        captured["indicator_args"] = (symbol, len(candles), current_price)
        return TechnicalIndicators(
            symbol=symbol,
            price=current_price,
            sma_20=210.0,
            sma_50=200.0,
            sma_200=None,
            ema_12=214.0,
            ema_26=208.0,
            above_sma_20=True,
            above_sma_50=True,
            above_sma_200=None,
            rsi=RSIData(value=64.5, signal="neutral"),
            macd=MACDData(macd=1.2, signal=1.0, histogram=0.2, trend="bullish"),
            bollinger_bands=BollingerBandsData(
                upper=230.0,
                middle=220.0,
                lower=210.0,
                percent_b=0.625,
                bandwidth=0.09,
            ),
        )

    monkeypatch.setattr(indicators.data_fetcher, "get_candles", fake_get_candles)
    monkeypatch.setattr(indicators.data_fetcher, "get_quote", fake_get_quote)
    monkeypatch.setattr(indicators.indicator_service, "calculate_indicators", fake_calculate_indicators)

    response = client.get("/api/indicators/aapl?period=120")

    assert response.status_code == 200
    data = response.json()
    assert data["symbol"] == "AAPL"
    assert data["price"] == 222.5
    assert data["rsi"]["signal"] == "neutral"
    assert data["macd"]["trend"] == "bullish"
    assert data["above_sma_20"] is True
    assert captured["candles_args"] == ("AAPL", "1d", 120)
    assert captured["quote_arg"] == "AAPL"
    assert captured["indicator_args"] == ("AAPL", 120, 222.5)


def test_get_indicators_returns_404_when_candles_missing(client, monkeypatch):
    async def fake_get_candles(symbol, interval="1d", limit=100):
        return []

    monkeypatch.setattr(indicators.data_fetcher, "get_candles", fake_get_candles)

    response = client.get("/api/indicators/aapl")

    assert response.status_code == 404
    assert response.json()["detail"] == "Unable to fetch candles for AAPL"


def test_get_indicators_returns_500_when_indicator_calculation_fails(client, monkeypatch):
    async def fake_get_candles(symbol, interval="1d", limit=100):
        return _build_candles(100)

    async def fake_get_quote(symbol):
        return None

    def fake_calculate_indicators(symbol, candles, current_price=None):
        return None

    monkeypatch.setattr(indicators.data_fetcher, "get_candles", fake_get_candles)
    monkeypatch.setattr(indicators.data_fetcher, "get_quote", fake_get_quote)
    monkeypatch.setattr(indicators.indicator_service, "calculate_indicators", fake_calculate_indicators)

    response = client.get("/api/indicators/aapl")

    assert response.status_code == 500
    assert response.json()["detail"] == "Failed to calculate indicators for AAPL"
