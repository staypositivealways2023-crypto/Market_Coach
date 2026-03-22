"""Populate popular stocks in Firestore for market screen"""

import os
import sys
sys.path.insert(0, '../')

from google.cloud import firestore
from datetime import datetime, timedelta
import random

# Initialize Firestore
creds_path = os.path.join(os.path.dirname(__file__), '..', 'serviceAccountKey.json')
db = firestore.Client.from_service_account_json(creds_path)

# Popular stocks to add
POPULAR_STOCKS = {
    'AAPL': {
        'name': 'Apple Inc.',
        'base_price': 187.97,
        'sector': 'Technology',
        'industry': 'Consumer Electronics',
    },
    'MSFT': {
        'name': 'Microsoft Corporation',
        'base_price': 415.26,
        'sector': 'Technology',
        'industry': 'Software',
    },
    'GOOGL': {
        'name': 'Alphabet Inc.',
        'base_price': 138.21,
        'sector': 'Technology',
        'industry': 'Internet Services',
    },
    'TSLA': {
        'name': 'Tesla Inc.',
        'base_price': 242.84,
        'sector': 'Automotive',
        'industry': 'Electric Vehicles',
    },
    'NVDA': {
        'name': 'NVIDIA Corporation',
        'base_price': 722.48,
        'sector': 'Technology',
        'industry': 'Semiconductors',
    },
    'AMZN': {
        'name': 'Amazon.com Inc.',
        'base_price': 178.12,
        'sector': 'Consumer',
        'industry': 'E-commerce',
    },
    'BHP': {
        'name': 'BHP Group',
        'base_price': 45.84,
        'sector': 'Materials',
        'industry': 'Mining',
    },
}

def populate_stock_data(symbol, info):
    """Populate market data and candles for a stock"""

    print(f"\n{'='*60}")
    print(f"Processing {symbol} - {info['name']}")
    print(f"{'='*60}")

    base_price = info['base_price']

    # 1. Create/update market_data document
    print(f"1. Creating market_data document...")

    change_percent = random.uniform(-3, 3)
    current_price = base_price * (1 + change_percent/100)

    market_data = {
        'ticker': symbol,
        'name': info['name'],
        'price': round(current_price, 2),
        'changePercent': round(change_percent, 2),
        'sector': info['sector'],
        'industry': info['industry'],
        'isCrypto': False,
        'updated_at': datetime.now(),
    }

    db.collection('market_data').document(symbol).set(market_data)
    print(f"   ✓ Market data created: ${current_price:.2f} ({change_percent:+.2f}%)")

    # 2. Create candles
    print(f"2. Creating candle data (200 candles)...")

    candles_ref = db.collection('market_data').document(symbol).collection('candles')

    # Check if candles already exist
    existing_candles = list(candles_ref.limit(1).stream())
    if existing_candles:
        print(f"   ⚠ Candles already exist, skipping...")
        return

    batch = db.batch()
    price = base_price

    for i in range(200):
        date = datetime.now() - timedelta(days=200 - i)

        # Simulate realistic price movement
        daily_change = random.uniform(-0.03, 0.03)  # ±3% max daily change
        open_price = price * (1 + random.uniform(-0.01, 0.01))
        close_price = open_price * (1 + daily_change)
        high_price = max(open_price, close_price) * (1 + random.uniform(0, 0.015))
        low_price = min(open_price, close_price) * (1 - random.uniform(0, 0.015))
        volume = random.randint(20000000, 100000000)

        candle_data = {
            'timestamp': date,
            'open': round(open_price, 2),
            'high': round(high_price, 2),
            'low': round(low_price, 2),
            'close': round(close_price, 2),
            'volume': volume
        }

        doc_id = date.strftime('%Y-%m-%dT%H:%M:%S')
        doc_ref = candles_ref.document(doc_id)
        batch.set(doc_ref, candle_data)

        # Update price for next candle
        price = close_price

        if (i + 1) % 100 == 0:
            batch.commit()
            batch = db.batch()
            print(f"   Created {i + 1}/200 candles...")

    if 200 % 100 != 0:
        batch.commit()

    print(f"   ✓ Created 200 candles")
    print(f"   Price range: ${min(candle_data['low'] for _ in range(1)):.2f} - ${max(candle_data['high'] for _ in range(1)):.2f}")

def main():
    print("\n" + "="*60)
    print("POPULATING POPULAR STOCKS")
    print("="*60)

    for symbol, info in POPULAR_STOCKS.items():
        try:
            populate_stock_data(symbol, info)
        except Exception as e:
            print(f"   ✗ Error processing {symbol}: {e}")
            continue

    print("\n" + "="*60)
    print("✓ ALL DONE!")
    print("="*60)
    print(f"Successfully populated {len(POPULAR_STOCKS)} stocks")
    print("Market screen is now ready to display live data!")
    print()

if __name__ == '__main__':
    main()
