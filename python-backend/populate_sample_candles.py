"""Populate sample candle data directly to Firestore"""

import os
from dotenv import load_dotenv
load_dotenv()

from google.cloud import firestore
from datetime import datetime, timedelta
import random

# Initialize Firestore
creds_path = "./serviceAccountKey.json"
db = firestore.Client.from_service_account_json(creds_path)

symbols = ["AAPL", "GOOGL", "MSFT", "AMZN", "TSLA", "NVDA", "META"]

print("Populating sample candle data for demonstration...")

for symbol in symbols:
    print(f"\nPopulating {symbol}...")

    # Generate 200 days of sample data
    base_price = random.uniform(100, 300)
    candles = []

    for i in range(200):
        date = datetime.now() - timedelta(days=200-i)

        # Simulate realistic OHLCV data
        open_price = base_price + random.uniform(-5, 5)
        close_price = open_price + random.uniform(-10, 10)
        high_price = max(open_price, close_price) + random.uniform(0, 5)
        low_price = min(open_price, close_price) - random.uniform(0, 5)
        volume = random.randint(10000000, 100000000)

        candle_data = {
            'timestamp': date,
            'open': round(open_price, 2),
            'high': round(high_price, 2),
            'low': round(low_price, 2),
            'close': round(close_price, 2),
            'volume': volume
        }

        # Use ISO format timestamp as document ID
        doc_id = date.strftime('%Y-%m-%dT%H:%M:%S')
        doc_ref = (
            db.collection('market_data')
            .document(symbol)
            .collection('candles')
            .document(doc_id)
        )

        doc_ref.set(candle_data)

        # Update base price for next iteration (trending)
        base_price = close_price

    print(f"  [OK] Wrote 200 candles for {symbol}")

print("\n[DONE] Sample candle data populated for all symbols.")
