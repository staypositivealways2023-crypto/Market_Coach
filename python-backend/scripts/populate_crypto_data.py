"""Populate cryptocurrency data in Firestore for market screen"""

import os
import sys
sys.path.insert(0, '../')

from google.cloud import firestore
from datetime import datetime, timedelta
import random

# Initialize Firestore
creds_path = os.path.join(os.path.dirname(__file__), '..', 'serviceAccountKey.json')
db = firestore.Client.from_service_account_json(creds_path)

# Cryptocurrencies to add
CRYPTOCURRENCIES = {
    'BTC': {
        'name': 'Bitcoin',
        'base_price': 42148.47,
        'sector': 'Digital Asset',
        'industry': 'Settlement Layer',
    },
    'ETH': {
        'name': 'Ethereum',
        'base_price': 2451.72,
        'sector': 'Digital Asset',
        'industry': 'Smart Contract Platform',
    },
    'SOL': {
        'name': 'Solana',
        'base_price': 102.41,
        'sector': 'Digital Asset',
        'industry': 'Smart Contract Platform',
    },
    'ADA': {
        'name': 'Cardano',
        'base_price': 0.58,
        'sector': 'Digital Asset',
        'industry': 'Smart Contract Platform',
    },
    'XRP': {
        'name': 'Ripple',
        'base_price': 0.52,
        'sector': 'Digital Asset',
        'industry': 'Payment Protocol',
    },
    'XLM': {
        'name': 'Stellar',
        'base_price': 0.11,
        'sector': 'Digital Asset',
        'industry': 'Payment Protocol',
    },
}

def populate_crypto_data(symbol, info):
    """Populate market data and candles for a cryptocurrency"""

    print(f"\n{'='*60}")
    print(f"Processing {symbol} - {info['name']}")
    print(f"{'='*60}")

    base_price = info['base_price']

    # 1. Create/update market_data document
    print(f"1. Creating market_data document...")

    # Crypto is more volatile - larger change percentage
    change_percent = random.uniform(-8, 8)
    current_price = base_price * (1 + change_percent/100)

    market_data = {
        'ticker': symbol,
        'name': info['name'],
        'price': round(current_price, 4 if current_price < 1 else 2),
        'changePercent': round(change_percent, 2),
        'sector': info['sector'],
        'industry': info['industry'],
        'isCrypto': True,
        'updated_at': datetime.now(),
    }

    db.collection('market_data').document(symbol).set(market_data)
    print(f"   ✓ Market data created: ${current_price:.4f if current_price < 1 else current_price:.2f} ({change_percent:+.2f}%)")

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

        # Crypto has higher volatility - ±8% max daily change
        daily_change = random.uniform(-0.08, 0.08)
        open_price = price * (1 + random.uniform(-0.02, 0.02))
        close_price = open_price * (1 + daily_change)
        high_price = max(open_price, close_price) * (1 + random.uniform(0, 0.03))
        low_price = min(open_price, close_price) * (1 - random.uniform(0, 0.03))

        # Volume varies based on crypto size
        if symbol == 'BTC':
            volume = random.randint(15000000000, 35000000000)  # $15B-$35B daily volume
        elif symbol == 'ETH':
            volume = random.randint(8000000000, 18000000000)   # $8B-$18B
        elif symbol == 'SOL':
            volume = random.randint(500000000, 2000000000)     # $500M-$2B
        elif symbol in ['ADA', 'XRP']:
            volume = random.randint(300000000, 1000000000)     # $300M-$1B
        else:  # XLM
            volume = random.randint(50000000, 300000000)       # $50M-$300M

        # Format prices appropriately
        decimals = 4 if base_price < 1 else 2

        candle_data = {
            'timestamp': date,
            'open': round(open_price, decimals),
            'high': round(high_price, decimals),
            'low': round(low_price, decimals),
            'close': round(close_price, decimals),
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

    # Calculate price range
    final_decimals = 4 if price < 1 else 2
    print(f"   Price range: ${base_price:.{final_decimals}f} → ${price:.{final_decimals}f}")

def main():
    print("\n" + "="*60)
    print("POPULATING CRYPTOCURRENCY DATA")
    print("="*60)
    print("\nThis script will add 6 cryptocurrencies to Firestore:")
    print("- BTC (Bitcoin)")
    print("- ETH (Ethereum)")
    print("- SOL (Solana)")
    print("- ADA (Cardano)")
    print("- XRP (Ripple)")
    print("- XLM (Stellar)")
    print("\nEach crypto will get:")
    print("- Market data document")
    print("- 200 candles with realistic price movement")
    print("- Higher volatility than stocks (crypto behavior)")
    print()

    for symbol, info in CRYPTOCURRENCIES.items():
        try:
            populate_crypto_data(symbol, info)
        except Exception as e:
            print(f"   ✗ Error processing {symbol}: {e}")
            continue

    print("\n" + "="*60)
    print("✓ ALL DONE!")
    print("="*60)
    print(f"\nSuccessfully populated {len(CRYPTOCURRENCIES)} cryptocurrencies")
    print("\nWhat's been created:")
    print("├─ Market data for each crypto")
    print("├─ 200 candles per crypto")
    print("├─ Realistic price movements")
    print("└─ Higher volatility (crypto behavior)")
    print("\nYou can now:")
    print("1. Open Market tab in the app")
    print("2. See Top Cryptocurrencies section")
    print("3. Tap any crypto to view detailed charts")
    print("4. Bookmark cryptos you're interested in")
    print()

if __name__ == '__main__':
    main()
