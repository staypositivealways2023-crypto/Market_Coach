"""Calculate and populate technical indicators to Firestore"""

import os
from dotenv import load_dotenv
load_dotenv()

from google.cloud import firestore
from datetime import datetime
import sys
sys.path.insert(0, './')

from app.services.indicator_service import TechnicalIndicatorService
from app.models.stock import Candle

# Initialize Firestore
creds_path = "./serviceAccountKey.json"
db = firestore.Client.from_service_account_json(creds_path)

symbols = ["AAPL", "GOOGL", "MSFT", "AMZN", "TSLA", "NVDA", "META"]
indicator_service = TechnicalIndicatorService()

print("Calculating and populating technical indicators...\n")

for symbol in symbols:
    print(f"Processing {symbol}...")

    # Fetch candles from Firestore
    candles_ref = db.collection('market_data').document(symbol).collection('candles')
    candle_docs = candles_ref.order_by('timestamp').limit(200).get()

    if not candle_docs:
        print(f"  [SKIP] No candles found for {symbol}")
        continue

    # Convert to Candle objects
    candles = []
    for doc in candle_docs:
        data = doc.to_dict()
        candles.append(Candle(
            symbol=symbol,
            timestamp=data['timestamp'],
            open=data['open'],
            high=data['high'],
            low=data['low'],
            close=data['close'],
            volume=data['volume']
        ))

    print(f"  Found {len(candles)} candles")

    # Get current price (last close)
    current_price = candles[-1].close if candles else 0

    # Calculate indicators
    indicators = indicator_service.calculate_indicators(
        symbol=symbol,
        candles=candles,
        current_price=current_price
    )

    if indicators:
        # Write to Firestore
        doc_ref = db.collection('indicators').document(symbol)
        data = indicators.model_dump()
        data['updated_at'] = firestore.SERVER_TIMESTAMP
        doc_ref.set(data, merge=True)

        print(f"  [OK] Indicators calculated and written")
        print(f"    RSI: {indicators.rsi.value if indicators.rsi else 'N/A'}")
        print(f"    MACD: {indicators.macd.macd if indicators.macd else 'N/A'}")
    else:
        print(f"  [FAIL] Could not calculate indicators")

print("\n[DONE] Technical indicators populated!")
