"""Analysis Aggregator - Combine market data from multiple services"""

from typing import Optional, Dict, Any
import logging

from app.services.data_fetcher import MarketDataFetcher
from app.services.indicator_service import TechnicalIndicatorService
from app.services.valuation_service import ValuationService

logger = logging.getLogger(__name__)


class AnalysisAggregator:
    """Aggregates market data from various services for AI analysis"""

    def __init__(self):
        self.data_fetcher = MarketDataFetcher()
        self.indicator_service = TechnicalIndicatorService()
        self.valuation_service = ValuationService()

    async def aggregate_market_data(self, symbol: str) -> Optional[Dict[str, Any]]:
        """
        Aggregate all market data for a symbol

        Args:
            symbol: Stock ticker symbol (e.g., 'AAPL', 'BTC-USD')

        Returns:
            Dict containing:
                - quote: Current price and stats
                - technical: Technical indicators
                - valuation: DCF and metrics
                - info: Company information

        Returns None if critical data unavailable
        """

        logger.info(f"Aggregating market data for {symbol}")

        context = {
            "symbol": symbol,
            "quote": None,
            "technical": None,
            "valuation_dcf": None,
            "valuation_metrics": None,
            "info": None
        }

        try:
            # 1. Get current quote (REQUIRED)
            quote = await self.data_fetcher.get_quote(symbol)
            if not quote:
                logger.warning(f"Could not fetch quote for {symbol}")
                return None

            context["quote"] = {
                "price": quote.price,
                "change": quote.change,
                "change_percent": quote.change_percent,
                "high": quote.high,
                "low": quote.low,
                "open": quote.open,
                "previous_close": quote.previous_close,
                "volume": quote.volume,
                "market_cap": quote.market_cap,
                "pe_ratio": quote.pe_ratio
            }

            # 2. Get historical candles for technical analysis
            candles = await self.data_fetcher.get_candles(symbol, interval="1d", limit=200)

            if candles and len(candles) >= 50:
                # Calculate technical indicators
                indicators = self.indicator_service.calculate_indicators(
                    symbol=symbol,
                    candles=candles,
                    current_price=quote.price
                )

                if indicators:
                    context["technical"] = {
                        "rsi": {
                            "value": indicators.rsi.value if indicators.rsi else None,
                            "signal": indicators.rsi.signal if indicators.rsi else None
                        } if indicators.rsi else None,
                        "macd": {
                            "macd": indicators.macd.macd if indicators.macd else None,
                            "signal": indicators.macd.signal if indicators.macd else None,
                            "histogram": indicators.macd.histogram if indicators.macd else None,
                            "trend": indicators.macd.trend if indicators.macd else None
                        } if indicators.macd else None,
                        "bollinger_bands": {
                            "upper": indicators.bollinger_bands.upper if indicators.bollinger_bands else None,
                            "middle": indicators.bollinger_bands.middle if indicators.bollinger_bands else None,
                            "lower": indicators.bollinger_bands.lower if indicators.bollinger_bands else None,
                            "percent_b": indicators.bollinger_bands.percent_b if indicators.bollinger_bands else None
                        } if indicators.bollinger_bands else None,
                        "moving_averages": {
                            "sma_20": indicators.sma_20,
                            "sma_50": indicators.sma_50,
                            "sma_200": indicators.sma_200,
                            "above_sma_20": indicators.above_sma_20,
                            "above_sma_50": indicators.above_sma_50,
                            "above_sma_200": indicators.above_sma_200
                        }
                    }
            else:
                logger.warning(f"Insufficient candle data for {symbol} - skipping technical indicators")

            # 3. Get valuation data (optional - may not be available for crypto)
            try:
                dcf_valuation = await self.valuation_service.calculate_dcf(symbol)
                if dcf_valuation:
                    context["valuation_dcf"] = {
                        "intrinsic_value": dcf_valuation.intrinsic_value,
                        "current_price": dcf_valuation.current_price,
                        "upside_percent": dcf_valuation.upside_percent,
                        "signal": dcf_valuation.signal,
                        "confidence": dcf_valuation.confidence,
                        "growth_rate": dcf_valuation.growth_rate,
                        "wacc": dcf_valuation.wacc
                    }

                metrics = await self.valuation_service.calculate_metrics(symbol)
                if metrics:
                    context["valuation_metrics"] = {
                        "pe_ratio": metrics.pe_ratio,
                        "pb_ratio": metrics.pb_ratio,
                        "peg_ratio": metrics.peg_ratio,
                        "roe": metrics.roe,
                        "roa": metrics.roa,
                        "profit_margin": metrics.profit_margin,
                        "debt_to_equity": metrics.debt_to_equity,
                        "revenue_growth": metrics.revenue_growth,
                        "earnings_growth": metrics.earnings_growth,
                        "value_score": metrics.value_score,
                        "grade": metrics.grade
                    }

            except Exception as e:
                logger.info(f"Valuation data not available for {symbol}: {e}")
                # Not critical - crypto doesn't have fundamentals

            # 4. Get company/asset info
            try:
                info = await self.data_fetcher.get_stock_info(symbol)
                if info:
                    context["info"] = {
                        "name": info.name,
                        "sector": info.sector,
                        "industry": info.industry,
                        "description": info.description[:200] if info.description else None  # Truncate for prompt
                    }
            except Exception as e:
                logger.info(f"Company info not available for {symbol}: {e}")

            logger.info(f"Successfully aggregated data for {symbol}")
            return context

        except Exception as e:
            logger.error(f"Error aggregating data for {symbol}: {e}")
            return None
