"""Unit tests for the technical indicator service."""

from datetime import datetime, timedelta

from app.models.stock import Candle
from app.services.indicator_service import TechnicalIndicatorService


def _build_candles(count: int, start_price: float = 100.0, step: float = 0.8):
    start = datetime(2026, 1, 1)
    candles = []

    for i in range(count):
        close = start_price + (i * step)
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


def test_candles_to_dataframe_sorts_by_timestamp():
    service = TechnicalIndicatorService()
    candles = list(reversed(_build_candles(3)))

    df = service._candles_to_dataframe(candles)

    assert list(df.columns) == ["open", "high", "low", "close", "volume"]
    assert list(df["close"]) == [100.0, 100.8, 101.6]
    assert list(df.index) == sorted(df.index)


def test_calculate_indicators_returns_none_for_insufficient_candles():
    service = TechnicalIndicatorService()

    result = service.calculate_indicators("AAPL", _build_candles(10))

    assert result is None


def test_calculate_indicators_computes_expected_values_for_uptrend():
    service = TechnicalIndicatorService()
    candles = _build_candles(250)

    result = service.calculate_indicators("AAPL", candles)

    assert result is not None
    assert result.symbol == "AAPL"
    assert result.price == candles[-1].close
    assert result.rsi is not None
    assert result.rsi.signal == "overbought"
    assert result.rsi.value == 100.0
    assert result.macd is not None
    assert result.macd.trend == "bullish"
    assert result.bollinger_bands is not None
    assert result.bollinger_bands.lower < result.bollinger_bands.middle < result.bollinger_bands.upper
    assert 0 <= result.bollinger_bands.percent_b <= 1
    assert result.sma_20 is not None
    assert result.sma_50 is not None
    assert result.sma_200 is not None
    assert result.ema_12 is not None
    assert result.ema_26 is not None
    assert result.above_sma_20 is True
    assert result.above_sma_50 is True
    assert result.above_sma_200 is True


def test_calculate_indicators_uses_current_price_override_for_ma_signals():
    service = TechnicalIndicatorService()
    candles = _build_candles(50)

    result = service.calculate_indicators("AAPL", candles, current_price=50.0)

    assert result is not None
    assert result.price == 50.0
    assert result.sma_20 is not None
    assert result.sma_50 is not None
    assert result.sma_200 is None
    assert result.above_sma_20 is False
    assert result.above_sma_50 is False
    assert result.above_sma_200 is None
