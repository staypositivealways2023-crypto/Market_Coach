"""Populate all market data (stocks + crypto) in Firestore"""

import os
import sys
sys.path.insert(0, '../')

from google.cloud import firestore
from datetime import datetime, timedelta
import random

# Initialize Firestore
creds_path = os.path.join(os.path.dirname(__file__), '..', 'serviceAccountKey.json')
db = firestore.Client.from_service_account_json(creds_path)

# All market data to populate
STOCKS = {
    'AAPL': {
        'name': 'Apple Inc.',
        'base_price': 187.97,
        'sector': 'Technology',
        'industry': 'Consumer Electronics',
        'volatility': 0.03,  # ±3% daily
    },
    'MSFT': {
        'name': 'Microsoft Corporation',
        'base_price': 415.26,
        'sector': 'Technology',
        'industry': 'Software',
        'volatility': 0.03,
    },
    'GOOGL': {
        'name': 'Alphabet Inc.',
        'base_price': 138.21,
        'sector': 'Technology',
        'industry': 'Internet Services',
        'volatility': 0.04,
    },
    'TSLA': {
        'name': 'Tesla Inc.',
        'base_price': 242.84,
        'sector': 'Automotive',
        'industry': 'Electric Vehicles',
        'volatility': 0.05,  # Tesla is more volatile
    },
    'NVDA': {
        'name': 'NVIDIA Corporation',
        'base_price': 722.48,
        'sector': 'Technology',
        'industry': 'Semiconductors',
        'volatility': 0.04,
    },
    'AMZN': {
        'name': 'Amazon.com Inc.',
        'base_price': 178.12,
        'sector': 'Consumer',
        'industry': 'E-commerce',
        'volatility': 0.03,
    },
    'BHP': {
        'name': 'BHP Group',
        'base_price': 45.84,
        'sector': 'Materials',
        'industry': 'Mining',
        'volatility': 0.03,
    },
}

CRYPTOCURRENCIES = {
    'BTC': {
        'name': 'Bitcoin',
        'base_price': 42148.47,
        'sector': 'Digital Asset',
        'industry': 'Settlement Layer',
        'volatility': 0.08,  # ±8% daily
    },
    'ETH': {
        'name': 'Ethereum',
        'base_price': 2451.72,
        'sector': 'Digital Asset',
        'industry': 'Smart Contract Platform',
        'volatility': 0.08,
    },
    'SOL': {
        'name': 'Solana',
        'base_price': 102.41,
        'sector': 'Digital Asset',
        'industry': 'Smart Contract Platform',
        'volatility': 0.10,  # More volatile altcoin
    },
    'ADA': {
        'name': 'Cardano',
        'base_price': 0.58,
        'sector': 'Digital Asset',
        'industry': 'Smart Contract Platform',
        'volatility': 0.10,
    },
    'XRP': {
        'name': 'Ripple',
        'base_price': 0.52,
        'sector': 'Digital Asset',
        'industry': 'Payment Protocol',
        'volatility': 0.09,
    },
    'XLM': {
        'name': 'Stellar',
        'base_price': 0.11,
        'sector': 'Digital Asset',
        'industry': 'Payment Protocol',
        'volatility': 0.09,
    },
}

def populate_asset_data(symbol, info, is_crypto=False):
    """Populate market data and candles for a stock or crypto"""

    asset_type = "Crypto" if is_crypto else "Stock"
    print(f"\n{'─'*60}")
    print(f"{asset_type}: {symbol} - {info['name']}")
    print(f"{'─'*60}")

    base_price = info['base_price']
    volatility = info['volatility']

    # 1. Create/update market_data document
    change_percent = random.uniform(-volatility * 100, volatility * 100)
    current_price = base_price * (1 + change_percent/100)

    decimals = 4 if current_price < 1 else 2

    market_data = {
        'ticker': symbol,
        'name': info['name'],
        'price': round(current_price, decimals),
        'changePercent': round(change_percent, 2),
        'sector': info['sector'],
        'industry': info['industry'],
        'isCrypto': is_crypto,
        'updated_at': datetime.now(),
    }

    db.collection('market_data').document(symbol).set(market_data)
    print(f"✓ Market data: ${current_price:.{decimals}f} ({change_percent:+.2f}%)")

    # 2. Check if candles already exist
    candles_ref = db.collection('market_data').document(symbol).collection('candles')
    existing_candles = list(candles_ref.limit(1).stream())

    if existing_candles:
        print(f"⚠ Candles already exist, skipping candle creation")
        return

    # 3. Create 200 candles
    print(f"Creating 200 candles...", end='', flush=True)

    batch = db.batch()
    price = base_price

    for i in range(200):
        date = datetime.now() - timedelta(days=200 - i)

        daily_change = random.uniform(-volatility, volatility)
        open_price = price * (1 + random.uniform(-volatility/2, volatility/2))
        close_price = open_price * (1 + daily_change)
        high_price = max(open_price, close_price) * (1 + random.uniform(0, volatility/2))
        low_price = min(open_price, close_price) * (1 - random.uniform(0, volatility/2))

        # Volume based on asset type and size
        if is_crypto:
            if symbol == 'BTC':
                volume = random.randint(15000000000, 35000000000)
            elif symbol == 'ETH':
                volume = random.randint(8000000000, 18000000000)
            elif symbol == 'SOL':
                volume = random.randint(500000000, 2000000000)
            elif symbol in ['ADA', 'XRP']:
                volume = random.randint(300000000, 1000000000)
            else:
                volume = random.randint(50000000, 300000000)
        else:
            volume = random.randint(20000000, 100000000)

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

        price = close_price

        if (i + 1) % 100 == 0:
            batch.commit()
            batch = db.batch()

    if 200 % 100 != 0:
        batch.commit()

    print(f" Done!")
    print(f"✓ 200 candles created")

def main():
    print("\n" + "="*60)
    print("POPULATE ALL MARKET DATA")
    print("="*60)
    print("\nThis will populate:")
    print(f"├─ {len(STOCKS)} stocks (AAPL, MSFT, GOOGL, TSLA, NVDA, AMZN, BHP)")
    print(f"└─ {len(CRYPTOCURRENCIES)} cryptos (BTC, ETH, SOL, ADA, XRP, XLM)")
    print(f"\nTotal: {len(STOCKS) + len(CRYPTOCURRENCIES)} assets")
    print()

    stocks_created = 0
    crypto_created = 0

    # Populate stocks
    print("\n" + "="*60)
    print("STOCKS")
    print("="*60)
    for symbol, info in STOCKS.items():
        try:
            populate_asset_data(symbol, info, is_crypto=False)
            stocks_created += 1
        except Exception as e:
            print(f"✗ Error: {e}")

    # Populate cryptocurrencies
    print("\n" + "="*60)
    print("CRYPTOCURRENCIES")
    print("="*60)
    for symbol, info in CRYPTOCURRENCIES.items():
        try:
            populate_asset_data(symbol, info, is_crypto=True)
            crypto_created += 1
        except Exception as e:
            print(f"✗ Error: {e}")

    # Summary
    print("\n" + "="*60)
    print("✓ COMPLETE!")
    print("="*60)
    print(f"\nCreated:")
    print(f"├─ {stocks_created} stocks with market data + candles")
    print(f"└─ {crypto_created} cryptos with market data + candles")
    print(f"\nTotal: {stocks_created + crypto_created} assets")
    print("\n" + "="*60)
    print("READY TO USE")
    print("="*60)
    print("\nYour app now has:")
    print("✓ Popular Stocks section with real data")
    print("✓ Top Cryptocurrencies section with real data")
    print("✓ 200 candles per asset for charting")
    print("✓ Technical indicators will calculate from this data")
    print("\nOpen the app and go to Market tab to see everything!")
    print()

if __name__ == '__main__':
    main()
