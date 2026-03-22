"""Firestore Writer Service - Write market data to Firestore"""

from google.cloud import firestore
from google.oauth2 import service_account
from typing import Optional, Dict, Any
import logging
import json
import base64
from datetime import datetime

from app.models.stock import Quote, Candle, StockInfo
from app.models.indicator import TechnicalIndicators
from app.models.valuation import DCFValuation, ValuationMetrics
from app.config import settings

logger = logging.getLogger(__name__)


class FirestoreWriter:
    """Write market data to Firestore"""

    def __init__(self):
        self.db: Optional[firestore.Client] = None
        self._initialize_firestore()

    def _initialize_firestore(self):
        """Initialize Firestore client.
        Priority: FIREBASE_CREDENTIALS_JSON (base64, for Railway) > FIREBASE_CREDENTIALS_PATH (local file)
        """
        try:
            if settings.FIREBASE_CREDENTIALS_JSON:
                # Production / Railway: decode base64 env var
                creds_dict = json.loads(base64.b64decode(settings.FIREBASE_CREDENTIALS_JSON))
                credentials = service_account.Credentials.from_service_account_info(creds_dict)
                self.db = firestore.Client(
                    project=settings.FIREBASE_PROJECT_ID,
                    credentials=credentials,
                )
            elif settings.FIREBASE_CREDENTIALS_PATH:
                # Local dev: use file path
                self.db = firestore.Client.from_service_account_json(
                    settings.FIREBASE_CREDENTIALS_PATH
                )
            else:
                # Fallback: application default credentials
                self.db = firestore.Client(project=settings.FIREBASE_PROJECT_ID)

            logger.info("Firestore client initialized")
        except Exception as e:
            logger.error(f"Failed to initialize Firestore: {e}")
            self.db = None

    async def write_quote(self, quote: Quote) -> bool:
        """Write quote to market_data collection"""

        if not self.db:
            logger.error("Firestore not initialized")
            return False

        try:
            doc_ref = self.db.collection('market_data').document(quote.symbol)

            data = quote.model_dump()
            data['updated_at'] = firestore.SERVER_TIMESTAMP

            doc_ref.set(data, merge=True)

            logger.info(f"Quote written for {quote.symbol}")
            return True

        except Exception as e:
            logger.error(f"Failed to write quote for {quote.symbol}: {e}")
            return False

    async def write_candles(self, symbol: str, candles: list[Candle]) -> bool:
        """Write candles to market_data/{symbol}/candles subcollection"""

        if not self.db:
            logger.error("Firestore not initialized")
            return False

        try:
            batch = self.db.batch()

            for candle in candles:
                # Use timestamp as document ID
                doc_id = candle.timestamp.isoformat()
                doc_ref = (
                    self.db.collection('market_data')
                    .document(symbol)
                    .collection('candles')
                    .document(doc_id)
                )

                batch.set(doc_ref, candle.model_dump(), merge=True)

            batch.commit()

            logger.info(f"Wrote {len(candles)} candles for {symbol}")
            return True

        except Exception as e:
            logger.error(f"Failed to write candles for {symbol}: {e}")
            return False

    async def write_indicators(self, indicators: TechnicalIndicators) -> bool:
        """Write technical indicators to indicators collection"""

        if not self.db:
            logger.error("Firestore not initialized")
            return False

        try:
            doc_ref = self.db.collection('indicators').document(indicators.symbol)

            data = indicators.model_dump()
            data['updated_at'] = firestore.SERVER_TIMESTAMP

            doc_ref.set(data, merge=True)

            logger.info(f"Indicators written for {indicators.symbol}")
            return True

        except Exception as e:
            logger.error(f"Failed to write indicators for {indicators.symbol}: {e}")
            return False

    async def write_stock_info(self, info: StockInfo) -> bool:
        """Write stock info to market_data collection"""

        if not self.db:
            logger.error("Firestore not initialized")
            return False

        try:
            doc_ref = self.db.collection('market_data').document(info.symbol)

            data = info.model_dump()
            data['updated_at'] = firestore.SERVER_TIMESTAMP

            doc_ref.set(data, merge=True)

            logger.info(f"Stock info written for {info.symbol}")
            return True

        except Exception as e:
            logger.error(f"Failed to write stock info for {info.symbol}: {e}")
            return False

    async def write_dcf_valuation(self, dcf: DCFValuation) -> bool:
        """Write DCF valuation to valuations collection"""

        if not self.db:
            logger.error("Firestore not initialized")
            return False

        try:
            doc_ref = (
                self.db.collection('valuations')
                .document(dcf.symbol)
                .collection('dcf')
                .document(datetime.utcnow().strftime('%Y-%m-%d'))
            )

            data = dcf.model_dump()
            data['created_at'] = firestore.SERVER_TIMESTAMP

            doc_ref.set(data)

            logger.info(f"DCF valuation written for {dcf.symbol}")
            return True

        except Exception as e:
            logger.error(f"Failed to write DCF for {dcf.symbol}: {e}")
            return False

    async def write_valuation_metrics(self, metrics: ValuationMetrics) -> bool:
        """Write valuation metrics to valuations collection"""

        if not self.db:
            logger.error("Firestore not initialized")
            return False

        try:
            doc_ref = self.db.collection('valuations').document(metrics.symbol)

            data = metrics.model_dump()
            data['updated_at'] = firestore.SERVER_TIMESTAMP

            doc_ref.set(data, merge=True)

            logger.info(f"Valuation metrics written for {metrics.symbol}")
            return True

        except Exception as e:
            logger.error(f"Failed to write metrics for {metrics.symbol}: {e}")
            return False

    async def get_watchlist(self) -> list[str]:
        """Get watchlist from Firestore or return default"""

        if not self.db:
            logger.warning("Firestore not initialized, using default watchlist")
            return settings.DEFAULT_WATCHLIST

        try:
            doc_ref = self.db.collection('config').document('watchlist')
            doc = doc_ref.get()

            if doc.exists:
                data = doc.to_dict()
                return data.get('symbols', settings.DEFAULT_WATCHLIST)
            else:
                return settings.DEFAULT_WATCHLIST

        except Exception as e:
            logger.error(f"Failed to get watchlist: {e}")
            return settings.DEFAULT_WATCHLIST
