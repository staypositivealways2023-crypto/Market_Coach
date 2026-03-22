"""Check if candle data exists in Firestore"""

import sys
import os
sys.path.insert(0, '../')

from google.cloud import firestore
from app.config import settings

# Initialize Firestore
creds_path = os.path.join(os.path.dirname(__file__), '..', 'serviceAccountKey.json')
print(f"Using credentials: {creds_path}")
db = firestore.Client.from_service_account_json(creds_path)

# Check candles for AAPL
symbol = "AAPL"
candles_ref = db.collection('market_data').document(symbol).collection('candles')
candles = candles_ref.limit(5).order_by('timestamp', direction=firestore.Query.DESCENDING).get()

print(f"\n=== Candles for {symbol} ===")
print(f"Found {len(candles)} candles (showing first 5)")

for candle in candles:
    data = candle.to_dict()
    print(f"\nDocument ID: {candle.id}")
    print(f"Timestamp: {data.get('timestamp')}")
    print(f"Open: {data.get('open')}")
    print(f"High: {data.get('high')}")
    print(f"Low: {data.get('low')}")
    print(f"Close: {data.get('close')}")
    print(f"Volume: {data.get('volume')}")

# Check total count
all_candles = candles_ref.get()
print(f"\n=== Total candles in Firestore: {len(all_candles)} ===")
