"""Fetch REAL market data from Yahoo Finance and populate Firestore"""

import os
import sys
sys.path.insert(0, '../')

from google.cloud import firestore
from datetime import datetime, timedelta
import yfinance as yf
import time

# Initialize Firestore
creds_path = os.path.join(os.path.dirname(__file__), '..', 'serviceAccountKey.json')
db = firestore.Client.from_service_account_json(creds_path)

# Stocks to fetch (Yahoo Finance tickers)
STOCKS = {
    'AAPL': {'name': 'Apple Inc.', 'sector': 'Technology', 'industry': 'Consumer Electronics'},
    'MSFT': {'name': 'Microsoft Corporation', 'sector': 'Technology', 'industry': 'Software'},
    'GOOGL': {'name': 'Alphabet Inc.', 'sector': 'Technology', 'industry': 'Internet Services'},
    'TSLA': {'name': 'Tesla Inc.', 'sector': 'Automotive', 'industry': 'Electric Vehicles'},
    'NVDA': {'name': 'NVIDIA Corporation', 'sector': 'Technology', 'industry': 'Semiconductors'},
    'AMZN': {'name': 'Amazon.com Inc.', 'sector': 'Consumer', 'industry': 'E-commerce'},
    'BHP': {'name': 'BHP Group', 'sector': 'Materials', 'industry': 'Mining'},
}

# Crypto tickers on Yahoo Finance
CRYPTO = {
    'BTC-USD': {'symbol': 'BTC', 'name': 'Bitcoin', 'sector': 'Digital Asset', 'industry': 'Settlement Layer'},
    'ETH-USD': {'symbol': 'ETH', 'name': 'Ethereum', 'sector': 'Digital Asset', 'industry': 'Smart Contract Platform'},
    'SOL-USD': {'symbol': 'SOL', 'name': 'Solana', 'sector': 'Digital Asset', 'industry': 'Smart Contract Platform'},
    'ADA-USD': {'symbol': 'ADA', 'name': 'Cardano', 'sector': 'Digital Asset', 'industry': 'Smart Contract Platform'},
    'XRP-USD': {'symbol': 'XRP', 'name': 'Ripple', 'sector': 'Digital Asset', 'industry': 'Payment Protocol'},
    'XLM-USD': {'symbol': 'XLM', 'name': 'Stellar', 'sector': 'Digital Asset', 'industry': 'Payment Protocol'},
}

def fetch_stock_data(symbol, info):
    """Fetch real stock data from Yahoo Finance"""

    print(f"\n{'='*60}")
    print(f"Fetching REAL data for {symbol} - {info['name']}")
    print(f"{'='*60}")

    try:
        # Create yfinance ticker
        ticker = yf.Ticker(symbol)

        # Get current price and info
        print("1. Fetching current price and info...")
        ticker_info = ticker.info

        # Get current price
        current_price = ticker_info.get('currentPrice') or ticker_info.get('regularMarketPrice')
        previous_close = ticker_info.get('previousClose')

        if not current_price or not previous_close:
            print(f"   ✗ Could not fetch current price")
            return False

        # Calculate real change percentage
        change_percent = ((current_price - previous_close) / previous_close) * 100

        print(f"   ✓ Current Price: ${current_price:.2f}")
        print(f"   ✓ Previous Close: ${previous_close:.2f}")
        print(f"   ✓ Change: {change_percent:+.2f}%")

        # Create market_data document with REAL data
        market_data = {
            'ticker': symbol,
            'name': info['name'],
            'price': round(current_price, 2),
            'changePercent': round(change_percent, 2),
            'sector': info['sector'],
            'industry': info['industry'],
            'isCrypto': False,
            'updated_at': datetime.now(),
            'previousClose': round(previous_close, 2),
        }

        db.collection('market_data').document(symbol).set(market_data)
        print(f"   ✓ Market data saved to Firestore")

        # 2. Fetch historical candle data (last 200 days)
        print("2. Fetching REAL historical candles (200 days)...")

        candles_ref = db.collection('market_data').document(symbol).collection('candles')

        # Download historical data
        hist = ticker.history(period='1y')  # Get 1 year of data

        if hist.empty:
            print(f"   ✗ No historical data available")
            return False

        # Take last 200 days
        hist = hist.tail(200)

        print(f"   ✓ Downloaded {len(hist)} candles")

        # Delete existing candles
        print("   Clearing old candles...")
        existing = candles_ref.stream()
        batch = db.batch()
        count = 0
        for doc in existing:
            batch.delete(doc.reference)
            count += 1
            if count % 100 == 0:
                batch.commit()
                batch = db.batch()
        if count % 100 != 0:
            batch.commit()

        # Upload new REAL candles
        print("   Uploading REAL candles...")
        batch = db.batch()
        uploaded = 0

        for index, row in hist.iterrows():
            candle_data = {
                'timestamp': index.to_pydatetime(),
                'open': round(float(row['Open']), 2),
                'high': round(float(row['High']), 2),
                'low': round(float(row['Low']), 2),
                'close': round(float(row['Close']), 2),
                'volume': int(row['Volume']),
            }

            doc_id = index.strftime('%Y-%m-%dT%H:%M:%S')
            doc_ref = candles_ref.document(doc_id)
            batch.set(doc_ref, candle_data)
            uploaded += 1

            if uploaded % 100 == 0:
                batch.commit()
                batch = db.batch()
                print(f"   Uploaded {uploaded}/{len(hist)} candles...")

        if uploaded % 100 != 0:
            batch.commit()

        print(f"   ✓ Uploaded {uploaded} REAL candles")
        print(f"   ✓ Price range: ${hist['Low'].min():.2f} - ${hist['High'].max():.2f}")

        return True

    except Exception as e:
        print(f"   ✗ Error: {e}")
        return False

def fetch_crypto_data(yf_symbol, info):
    """Fetch real crypto data from Yahoo Finance"""

    symbol = info['symbol']

    print(f"\n{'='*60}")
    print(f"Fetching REAL data for {symbol} - {info['name']}")
    print(f"{'='*60}")

    try:
        # Create yfinance ticker
        ticker = yf.Ticker(yf_symbol)

        # Get current price and info
        print("1. Fetching current price and info...")
        ticker_info = ticker.info

        # Get current price
        current_price = ticker_info.get('regularMarketPrice') or ticker_info.get('currentPrice')
        previous_close = ticker_info.get('previousClose')

        if not current_price or not previous_close:
            print(f"   ✗ Could not fetch current price")
            return False

        # Calculate real change percentage
        change_percent = ((current_price - previous_close) / previous_close) * 100

        decimals = 4 if current_price < 1 else 2

        print(f"   ✓ Current Price: ${current_price:.{decimals}f}")
        print(f"   ✓ Previous Close: ${previous_close:.{decimals}f}")
        print(f"   ✓ Change: {change_percent:+.2f}%")

        # Create market_data document with REAL data
        market_data = {
            'ticker': symbol,
            'name': info['name'],
            'price': round(current_price, decimals),
            'changePercent': round(change_percent, 2),
            'sector': info['sector'],
            'industry': info['industry'],
            'isCrypto': True,
            'updated_at': datetime.now(),
            'previousClose': round(previous_close, decimals),
        }

        db.collection('market_data').document(symbol).set(market_data)
        print(f"   ✓ Market data saved to Firestore")

        # 2. Fetch historical candle data (last 200 days)
        print("2. Fetching REAL historical candles (200 days)...")

        candles_ref = db.collection('market_data').document(symbol).collection('candles')

        # Download historical data
        hist = ticker.history(period='1y')  # Get 1 year of data

        if hist.empty:
            print(f"   ✗ No historical data available")
            return False

        # Take last 200 days
        hist = hist.tail(200)

        print(f"   ✓ Downloaded {len(hist)} candles")

        # Delete existing candles
        print("   Clearing old candles...")
        existing = candles_ref.stream()
        batch = db.batch()
        count = 0
        for doc in existing:
            batch.delete(doc.reference)
            count += 1
            if count % 100 == 0:
                batch.commit()
                batch = db.batch()
        if count % 100 != 0:
            batch.commit()

        # Upload new REAL candles
        print("   Uploading REAL candles...")
        batch = db.batch()
        uploaded = 0

        for index, row in hist.iterrows():
            candle_data = {
                'timestamp': index.to_pydatetime(),
                'open': round(float(row['Open']), decimals),
                'high': round(float(row['High']), decimals),
                'low': round(float(row['Low']), decimals),
                'close': round(float(row['Close']), decimals),
                'volume': int(row['Volume']),
            }

            doc_id = index.strftime('%Y-%m-%dT%H:%M:%S')
            doc_ref = candles_ref.document(doc_id)
            batch.set(doc_ref, candle_data)
            uploaded += 1

            if uploaded % 100 == 0:
                batch.commit()
                batch = db.batch()
                print(f"   Uploaded {uploaded}/{len(hist)} candles...")

        if uploaded % 100 != 0:
            batch.commit()

        print(f"   ✓ Uploaded {uploaded} REAL candles")
        print(f"   ✓ Price range: ${hist['Low'].min():.{decimals}f} - ${hist['High'].max():.{decimals}f}")

        return True

    except Exception as e:
        print(f"   ✗ Error: {e}")
        return False

def main():
    print("\n" + "="*60)
    print("FETCH REAL MARKET DATA")
    print("="*60)
    print("\nThis script fetches REAL data from Yahoo Finance:")
    print("✓ Real current prices")
    print("✓ Accurate percentage changes")
    print("✓ Real historical candles (last 200 days)")
    print("✓ Actual trading volumes")
    print("\nNOTE: This may take 2-3 minutes due to API rate limits")
    print()

    stocks_success = 0
    crypto_success = 0

    # Fetch stocks
    print("\n" + "="*60)
    print("FETCHING STOCKS")
    print("="*60)
    for symbol, info in STOCKS.items():
        if fetch_stock_data(symbol, info):
            stocks_success += 1
        time.sleep(1)  # Rate limiting

    # Fetch crypto
    print("\n" + "="*60)
    print("FETCHING CRYPTOCURRENCIES")
    print("="*60)
    for yf_symbol, info in CRYPTO.items():
        if fetch_crypto_data(yf_symbol, info):
            crypto_success += 1
        time.sleep(1)  # Rate limiting

    # Summary
    print("\n" + "="*60)
    print("✓ COMPLETE!")
    print("="*60)
    print(f"\nSuccessfully fetched:")
    print(f"├─ {stocks_success}/{len(STOCKS)} stocks")
    print(f"└─ {crypto_success}/{len(CRYPTO)} cryptocurrencies")
    print(f"\nTotal: {stocks_success + crypto_success}/{len(STOCKS) + len(CRYPTO)} assets")
    print("\n" + "="*60)
    print("REAL DATA IN FIRESTORE")
    print("="*60)
    print("\nYour app now has:")
    print("✓ REAL current prices from Yahoo Finance")
    print("✓ ACCURATE percentage changes (calculated from real data)")
    print("✓ REAL historical candles (up to 200 days)")
    print("✓ ACTUAL trading volumes")
    print("\nOpen your app and see REAL market data!")
    print("\n💡 TIP: Run this script daily to keep data fresh")
    print()

if __name__ == '__main__':
    main()
