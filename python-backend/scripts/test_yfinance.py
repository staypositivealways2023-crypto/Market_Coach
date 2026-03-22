"""Test yfinance data fetching"""

import yfinance as yf
from datetime import datetime

symbol = "AAPL"
print(f"Testing yfinance for {symbol}...")

try:
    ticker = yf.Ticker(symbol)
    print(f"\nFetching 1 year of daily data...")
    hist = ticker.history(period="1y", interval="1d")

    print(f"Rows returned: {len(hist)}")

    if not hist.empty:
        print(f"\nFirst 5 rows:")
        print(hist.head())

        print(f"\nLast 5 rows:")
        print(hist.tail())

        print(f"\nData types:")
        print(hist.dtypes)
    else:
        print("No data returned!")

except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()
