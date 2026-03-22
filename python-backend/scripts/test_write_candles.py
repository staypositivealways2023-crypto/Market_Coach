"""Test writing candles directly to Firestore"""

import sys
import os
import asyncio
sys.path.insert(0, '../')

# Load environment variables
from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

import yfinance as yf
from datetime import datetime
from app.services.firestore_writer import FirestoreWriter
from app.models.stock import Candle

async def test_write():
    writer = FirestoreWriter()

    # Check if Firestore is initialized
    if not writer.db:
        print("❌ Firestore not initialized!")
        return

    print("✅ Firestore initialized")

    # Fetch candles using yfinance
    symbol = "AAPL"
    print(f"\nFetching candles for {symbol}...")

    ticker = yf.Ticker(symbol)
    hist = ticker.history(period="1mo", interval="1d")

    if hist.empty:
        print("❌ No data from yfinance")
        return

    print(f"✅ Got {len(hist)} candles from yfinance")

    # Convert to Candle objects
    candles = []
    for index, row in hist.iterrows():
        candles.append(Candle(
            symbol=symbol,
            timestamp=index.to_pydatetime(),
            open=float(row['Open']),
            high=float(row['High']),
            low=float(row['Low']),
            close=float(row['Close']),
            volume=int(row['Volume'])
        ))

    print(f"\n✅ Converted to {len(candles)} Candle objects")
    print(f"\nFirst candle:")
    print(f"  Timestamp: {candles[0].timestamp}")
    print(f"  Open: {candles[0].open}")
    print(f"  Close: {candles[0].close}")

    # Write to Firestore
    print(f"\nWriting candles to Firestore...")
    success = await writer.write_candles(symbol, candles)

    if success:
        print(f"✅ Successfully wrote candles to Firestore!")
    else:
        print(f"❌ Failed to write candles!")

if __name__ == "__main__":
    asyncio.run(test_write())
