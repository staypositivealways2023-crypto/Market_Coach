"""Test yfinance with user agent fix"""

import yfinance as yf
from datetime import datetime

# Set user agent to avoid being blocked
import requests_cache
session = requests_cache.CachedSession('yfinance.cache')
session.headers['User-agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'

symbol = "AAPL"
print(f"Testing yfinance for {symbol} with user agent...")

try:
    ticker = yf.Ticker(symbol, session=session)
    print(f"\nFetching 1 year of daily data...")
    hist = ticker.history(period="1y", interval="1d")

    print(f"Rows returned: {len(hist)}")

    if not hist.empty:
        print(f"\nFirst 3 rows:")
        print(hist.head(3))

        print(f"\nLast 3 rows:")
        print(hist.tail(3))

        print("\n✅ yfinance is working!")
    else:
        print("❌ No data returned!")

except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()
