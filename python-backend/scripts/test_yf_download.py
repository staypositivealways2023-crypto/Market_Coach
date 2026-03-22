"""Test yfinance download function"""

import yfinance as yf
from datetime import datetime, timedelta

symbol = "AAPL"
print(f"Testing yf.download for {symbol}...")

try:
    # Try using download instead of Ticker
    end_date = datetime.now()
    start_date = end_date - timedelta(days=365)

    print(f"\nDownloading data from {start_date.date()} to {end_date.date()}...")
    data = yf.download(symbol, start=start_date, end=end_date, progress=False)

    print(f"Rows returned: {len(data)}")

    if not data.empty:
        print(f"\nFirst 3 rows:")
        print(data.head(3))

        print(f"\nLast 3 rows:")
        print(data.tail(3))

        print("\n✅ yfinance download is working!")
    else:
        print("❌ No data returned!")

except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()
