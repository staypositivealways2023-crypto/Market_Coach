"""Quick update script - Updates only current prices and change percentages (no candles)"""

import os
import sys
sys.path.insert(0, '../')

from google.cloud import firestore
from datetime import datetime
import yfinance as yf
import time

# Initialize Firestore
creds_path = os.path.join(os.path.dirname(__file__), '..', 'serviceAccountKey.json')
db = firestore.Client.from_service_account_json(creds_path)

# All symbols to update
STOCKS = ['AAPL', 'MSFT', 'GOOGL', 'TSLA', 'NVDA', 'AMZN', 'BHP']
CRYPTO = {
    'BTC-USD': 'BTC',
    'ETH-USD': 'ETH',
    'SOL-USD': 'SOL',
    'ADA-USD': 'ADA',
    'XRP-USD': 'XRP',
    'XLM-USD': 'XLM',
}

def update_price(symbol, is_crypto=False, yf_symbol=None):
    """Update only price and changePercent for a symbol"""

    yf_sym = yf_symbol if yf_symbol else symbol

    try:
        ticker = yf.Ticker(yf_sym)
        info = ticker.info

        current_price = info.get('currentPrice') or info.get('regularMarketPrice')
        previous_close = info.get('previousClose')

        if not current_price or not previous_close:
            print(f"✗ {symbol}: No price data")
            return False

        change_percent = ((current_price - previous_close) / previous_close) * 100
        decimals = 4 if current_price < 1 else 2

        # Update only price fields
        db.collection('market_data').document(symbol).update({
            'price': round(current_price, decimals),
            'changePercent': round(change_percent, 2),
            'previousClose': round(previous_close, decimals),
            'updated_at': datetime.now(),
        })

        print(f"✓ {symbol}: ${current_price:.{decimals}f} ({change_percent:+.2f}%)")
        return True

    except Exception as e:
        print(f"✗ {symbol}: {e}")
        return False

def main():
    print("\n" + "="*60)
    print("QUICK PRICE UPDATE")
    print("="*60)
    print("\nUpdating current prices and change percentages...")
    print("(This is fast - doesn't update historical candles)")
    print()

    success = 0
    total = len(STOCKS) + len(CRYPTO)

    # Update stocks
    print("Stocks:")
    for symbol in STOCKS:
        if update_price(symbol):
            success += 1
        time.sleep(0.5)

    print()

    # Update crypto
    print("Crypto:")
    for yf_symbol, symbol in CRYPTO.items():
        if update_price(symbol, is_crypto=True, yf_symbol=yf_symbol):
            success += 1
        time.sleep(0.5)

    print("\n" + "="*60)
    print(f"✓ Updated {success}/{total} assets")
    print("="*60)
    print("\n💡 Run this script anytime to refresh prices!")
    print()

if __name__ == '__main__':
    main()
