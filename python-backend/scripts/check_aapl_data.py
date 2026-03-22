"""Check AAPL candle data for issues"""

import os
import sys
sys.path.insert(0, '../')

from google.cloud import firestore

# Initialize Firestore
creds_path = os.path.join(os.path.dirname(__file__), '..', 'serviceAccountKey.json')
db = firestore.Client.from_service_account_json(creds_path)

# Check AAPL candles
symbol = "AAPL"
candles_ref = db.collection('market_data').document(symbol).collection('candles')
candles = candles_ref.order_by('timestamp').limit(10).get()

print(f"\n=== First 10 AAPL Candles ===")
for candle in candles:
    data = candle.to_dict()
    print(f"\nTimestamp: {data.get('timestamp')}")
    print(f"  Open: {data.get('open')}")
    print(f"  High: {data.get('high')}")
    print(f"  Low: {data.get('low')}")
    print(f"  Close: {data.get('close')}")
    print(f"  Volume: {data.get('volume')}")

# Check if timestamps are in order
all_candles = candles_ref.order_by('timestamp').get()
print(f"\n=== Total AAPL candles: {len(all_candles)} ===")

# Check for duplicate timestamps
timestamps = [c.to_dict()['timestamp'] for c in all_candles]
if len(timestamps) != len(set(str(t) for t in timestamps)):
    print("WARNING: Duplicate timestamps found!")
else:
    print("OK: No duplicate timestamps")

# Check for gaps in data
print(f"\nFirst timestamp: {timestamps[0]}")
print(f"Last timestamp: {timestamps[-1]}")
