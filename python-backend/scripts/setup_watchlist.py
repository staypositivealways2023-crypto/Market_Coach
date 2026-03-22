"""Setup default watchlist for guest user in Firestore"""

import os
import sys
from datetime import datetime

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from google.cloud import firestore
from google.oauth2 import service_account
from app.config import settings

def setup_watchlist():
    """Create default watchlist for guest user"""

    # Load credentials
    credentials = service_account.Credentials.from_service_account_file(
        settings.FIREBASE_CREDENTIALS_PATH
    )

    # Initialize Firestore
    db = firestore.Client(
        project=settings.FIREBASE_PROJECT_ID,
        credentials=credentials
    )

    # Default symbols
    symbols = ["AAPL", "GOOGL", "MSFT", "AMZN", "TSLA", "NVDA", "META"]

    print(f"Setting up watchlist for guest_user...")
    print(f"Symbols: {symbols}")

    # Add symbols to watchlist
    for i, symbol in enumerate(symbols):
        doc_ref = db.collection('users').document('guest_user').collection('watchlist').document(symbol)
        doc_ref.set({
            'symbol': symbol,
            'added_at': datetime.utcnow(),
            'order': i
        })
        print(f"  [OK] Added {symbol}")

    print(f"\n[SUCCESS] Watchlist created successfully!")
    print(f"Total symbols: {len(symbols)}")

if __name__ == "__main__":
    setup_watchlist()
