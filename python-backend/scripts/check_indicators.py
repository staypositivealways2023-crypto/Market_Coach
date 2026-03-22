"""Check if indicator data exists in Firestore"""

import os
import sys
sys.path.insert(0, '../')

from google.cloud import firestore

# Initialize Firestore
creds_path = os.path.join(os.path.dirname(__file__), '..', 'serviceAccountKey.json')
db = firestore.Client.from_service_account_json(creds_path)

# Check indicators for AAPL
symbol = "AAPL"
doc_ref = db.collection('indicators').document(symbol)
doc = doc_ref.get()

print(f"\n=== Indicators for {symbol} ===")
if doc.exists:
    data = doc.to_dict()
    print(f"Found indicator data!")
    print(f"\nAvailable fields:")
    for key, value in data.items():
        if value is not None:
            print(f"  {key}: {value}")
else:
    print("No indicator data found!")
    print("\nChecking all indicators collection...")
    all_docs = db.collection('indicators').limit(5).get()
    print(f"Total documents in indicators: {len(list(all_docs))}")
