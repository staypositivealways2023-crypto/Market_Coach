"""Technical Indicator Service - Calculate indicators using ta library"""

import pandas as pd
import numpy as np
from typing import Optional, List
import logging
from ta.momentum import RSIIndicator
from ta.trend import MACD, SMAIndicator, EMAIndicator
from ta.volatility import BollingerBands

from app.models.indicator import (
    TechnicalIndicators,
    RSIData,
    MACDData,
    BollingerBandsData
)
from app.models.stock import Candle
from app.config import settings

logger = logging.getLogger(__name__)


class TechnicalIndicatorService:
    """Calculate technical indicators from price data"""

    def __init__(self):
        self.rsi_period = settings.RSI_PERIOD
        self.macd_fast = settings.MACD_FAST
        self.macd_slow = settings.MACD_SLOW
        self.macd_signal = settings.MACD_SIGNAL
        self.bb_period = settings.BOLLINGER_PERIOD
        self.bb_std = settings.BOLLINGER_STD

    def calculate_indicators(
        self,
        symbol: str,
        candles: List[Candle],
        current_price: Optional[float] = None
    ) -> Optional[TechnicalIndicators]:
        """Calculate all technical indicators"""

        if not candles or len(candles) < max(self.rsi_period, self.bb_period, self.macd_slow):
            logger.warning(f"Insufficient data for {symbol}: need at least {self.macd_slow} candles")
            return None

        try:
            # Convert to DataFrame
            df = self._candles_to_dataframe(candles)

            if df.empty:
                return None

            # Calculate indicators
            rsi_data = self._calculate_rsi(df)
            macd_data = self._calculate_macd(df)
            bb_data = self._calculate_bollinger_bands(df)

            # Calculate moving averages
            sma_20 = self._calculate_sma(df, 20)
            sma_50 = self._calculate_sma(df, 50)
            sma_200 = self._calculate_sma(df, 200)
            ema_12 = self._calculate_ema(df, 12)
            ema_26 = self._calculate_ema(df, 26)

            # Get current price (last close if not provided)
            price = current_price if current_price else df['close'].iloc[-1]

            # Price vs MA signals
            above_sma_20 = price > sma_20 if sma_20 else None
            above_sma_50 = price > sma_50 if sma_50 else None
            above_sma_200 = price > sma_200 if sma_200 else None

            return TechnicalIndicators(
                symbol=symbol,
                rsi=rsi_data,
                macd=macd_data,
                bollinger_bands=bb_data,
                sma_20=sma_20,
                sma_50=sma_50,
                sma_200=sma_200,
                ema_12=ema_12,
                ema_26=ema_26,
                price=price,
                above_sma_20=above_sma_20,
                above_sma_50=above_sma_50,
                above_sma_200=above_sma_200
            )

        except Exception as e:
            logger.error(f"Error calculating indicators for {symbol}: {e}")
            return None

    def _candles_to_dataframe(self, candles: List[Candle]) -> pd.DataFrame:
        """Convert candles to pandas DataFrame"""
        data = {
            'timestamp': [c.timestamp for c in candles],
            'open': [c.open for c in candles],
            'high': [c.high for c in candles],
            'low': [c.low for c in candles],
            'close': [c.close for c in candles],
            'volume': [c.volume for c in candles]
        }

        df = pd.DataFrame(data)
        df.set_index('timestamp', inplace=True)
        df.sort_index(inplace=True)

        return df

    def _calculate_rsi(self, df: pd.DataFrame) -> Optional[RSIData]:
        """Calculate RSI indicator"""
        try:
            rsi_indicator = RSIIndicator(close=df['close'], window=self.rsi_period)
            rsi_value = rsi_indicator.rsi().iloc[-1]

            # Determine signal
            if rsi_value >= 70:
                signal = "overbought"
            elif rsi_value <= 30:
                signal = "oversold"
            else:
                signal = "neutral"

            return RSIData(
                value=round(float(rsi_value), 2),
                signal=signal
            )
        except Exception as e:
            logger.error(f"RSI calculation error: {e}")
            return None

    def _calculate_macd(self, df: pd.DataFrame) -> Optional[MACDData]:
        """Calculate MACD indicator"""
        try:
            macd_indicator = MACD(
                close=df['close'],
                window_fast=self.macd_fast,
                window_slow=self.macd_slow,
                window_sign=self.macd_signal
            )

            macd = macd_indicator.macd().iloc[-1]
            signal = macd_indicator.macd_signal().iloc[-1]
            histogram = macd_indicator.macd_diff().iloc[-1]

            # Determine trend
            if histogram > 0 and macd > signal:
                trend = "bullish"
            elif histogram < 0 and macd < signal:
                trend = "bearish"
            else:
                trend = "neutral"

            return MACDData(
                macd=round(float(macd), 4),
                signal=round(float(signal), 4),
                histogram=round(float(histogram), 4),
                trend=trend
            )
        except Exception as e:
            logger.error(f"MACD calculation error: {e}")
            return None

    def _calculate_bollinger_bands(self, df: pd.DataFrame) -> Optional[BollingerBandsData]:
        """Calculate Bollinger Bands"""
        try:
            bb_indicator = BollingerBands(
                close=df['close'],
                window=self.bb_period,
                window_dev=self.bb_std
            )

            upper = bb_indicator.bollinger_hband().iloc[-1]
            middle = bb_indicator.bollinger_mavg().iloc[-1]
            lower = bb_indicator.bollinger_lband().iloc[-1]

            # Calculate %B (position within bands)
            current_price = df['close'].iloc[-1]
            percent_b = (current_price - lower) / (upper - lower) if (upper - lower) > 0 else 0.5

            # Calculate bandwidth
            bandwidth = (upper - lower) / middle if middle > 0 else 0

            return BollingerBandsData(
                upper=round(float(upper), 2),
                middle=round(float(middle), 2),
                lower=round(float(lower), 2),
                percent_b=round(float(percent_b), 4),
                bandwidth=round(float(bandwidth), 4)
            )
        except Exception as e:
            logger.error(f"Bollinger Bands calculation error: {e}")
            return None

    def _calculate_sma(self, df: pd.DataFrame, period: int) -> Optional[float]:
        """Calculate Simple Moving Average"""
        try:
            if len(df) < period:
                return None

            sma_indicator = SMAIndicator(close=df['close'], window=period)
            return round(float(sma_indicator.sma_indicator().iloc[-1]), 2)
        except Exception as e:
            logger.error(f"SMA-{period} calculation error: {e}")
            return None

    def _calculate_ema(self, df: pd.DataFrame, period: int) -> Optional[float]:
        """Calculate Exponential Moving Average"""
        try:
            if len(df) < period:
                return None

            ema_indicator = EMAIndicator(close=df['close'], window=period)
            return round(float(ema_indicator.ema_indicator().iloc[-1]), 2)
        except Exception as e:
            logger.error(f"EMA-{period} calculation error: {e}")
            return None
