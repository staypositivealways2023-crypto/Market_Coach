"""
Phase 5 — WebSocket Market Streaming Router

Endpoint:
  WS /api/market/stream/{symbol}

Behaviour:
  - Crypto  : connects to Binance miniTicker stream and proxies ticks in real time.
              Reconnects automatically on disconnect (up to MAX_BINANCE_RETRIES).
  - Stocks  : polls yfinance quote every STOCK_POLL_INTERVAL seconds and pushes
              deltas to the client. True tick-by-tick requires Polygon WS (paid).

Message format sent to client (JSON):
  {
    "symbol":     "BTCUSDT",
    "price":      65432.10,
    "change":     1.23,         // % change from open
    "volume":     12345678.0,   // 24h volume
    "high":       66000.00,
    "low":        64800.00,
    "timestamp":  "2026-05-02T12:34:56.789Z",
    "source":     "binance" | "yfinance_poll"
  }

Client sends JSON to control the stream:
  {"action": "ping"}           → server replies {"action": "pong"}
  {"action": "unsubscribe"}    → server closes cleanly
"""

import asyncio
import json
import logging
from datetime import datetime, timezone
from typing import Optional

import aiohttp
import yfinance as yf
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.services.data_fetcher import _is_crypto_symbol, _to_yfinance_symbol

logger = logging.getLogger(__name__)
router = APIRouter()

BINANCE_WS_BASE = "wss://stream.binance.com:9443/ws"
STOCK_POLL_INTERVAL = 5      # seconds between yfinance polls for stocks
MAX_BINANCE_RETRIES = 3
PING_INTERVAL = 20           # send keepalive ping every N seconds


def _to_binance_stream_symbol(symbol: str) -> str:
    """e.g. BTC → btcusdt  |  ETHUSDT → ethusdt"""
    s = symbol.upper().replace("-", "").replace("/", "")
    if not s.endswith("USDT"):
        s = s + "USDT"
    return s.lower()


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


async def _send_safe(ws: WebSocket, payload: dict) -> bool:
    """Send JSON to the WebSocket client; return False if client disconnected."""
    try:
        await ws.send_json(payload)
        return True
    except Exception:
        return False


# ── Crypto stream (Binance miniTicker) ───────────────────────────────────────

async def _stream_crypto(ws: WebSocket, symbol: str):
    """
    Subscribe to Binance 24hr miniTicker stream for real-time price ticks.
    Reconnects on failure up to MAX_BINANCE_RETRIES times.
    """
    stream_sym = _to_binance_stream_symbol(symbol)
    url = f"{BINANCE_WS_BASE}/{stream_sym}@miniTicker"
    retries = 0

    while retries <= MAX_BINANCE_RETRIES:
        try:
            logger.info("[stream] Connecting to Binance WS: %s", url)
            async with aiohttp.ClientSession() as session:
                async with session.ws_connect(
                    url,
                    heartbeat=30,
                    timeout=aiohttp.ClientWSTimeout(ws_close=60),
                ) as binance_ws:
                    retries = 0  # reset on successful connect
                    last_ping = asyncio.get_event_loop().time()

                    async for msg in binance_ws:
                        if msg.type == aiohttp.WSMsgType.TEXT:
                            try:
                                data = json.loads(msg.data)
                            except json.JSONDecodeError:
                                continue

                            # miniTicker fields: c=close, o=open, h=high, l=low, v=volume
                            price = float(data.get("c", 0))
                            open_p = float(data.get("o", price))
                            change_pct = ((price - open_p) / open_p * 100) if open_p > 0 else 0.0

                            tick = {
                                "symbol":    symbol.upper(),
                                "price":     round(price, 8),
                                "change":    round(change_pct, 4),
                                "volume":    float(data.get("v", 0)),
                                "high":      float(data.get("h", 0)),
                                "low":       float(data.get("l", 0)),
                                "timestamp": _now_iso(),
                                "source":    "binance",
                            }

                            alive = await _send_safe(ws, tick)
                            if not alive:
                                logger.info("[stream] Client disconnected from %s", symbol)
                                return

                            # Send keepalive ping and check for client messages
                            now = asyncio.get_event_loop().time()
                            if now - last_ping > PING_INTERVAL:
                                last_ping = now
                                try:
                                    # Non-blocking check for client messages
                                    client_msg = await asyncio.wait_for(
                                        ws.receive_json(), timeout=0.01
                                    )
                                    action = client_msg.get("action", "")
                                    if action == "ping":
                                        await _send_safe(ws, {"action": "pong"})
                                    elif action == "unsubscribe":
                                        await ws.close()
                                        return
                                except (asyncio.TimeoutError, Exception):
                                    pass  # No client message — normal

                        elif msg.type in (aiohttp.WSMsgType.CLOSED, aiohttp.WSMsgType.ERROR):
                            logger.warning("[stream] Binance WS closed/error for %s", symbol)
                            break

        except aiohttp.ClientError as e:
            retries += 1
            logger.warning("[stream] Binance WS error (%d/%d): %s", retries, MAX_BINANCE_RETRIES, e)
            if retries > MAX_BINANCE_RETRIES:
                await _send_safe(ws, {"error": "Streaming unavailable. Binance WS connection failed."})
                return
            await asyncio.sleep(2 ** retries)  # exponential back-off

        except Exception as e:
            logger.error("[stream] Unexpected crypto stream error: %s", e)
            await _send_safe(ws, {"error": f"Stream error: {e}"})
            return


# ── Stock stream (yfinance polling) ──────────────────────────────────────────

async def _stream_stocks(ws: WebSocket, symbol: str):
    """
    Poll yfinance every STOCK_POLL_INTERVAL seconds and push price updates.
    Only sends a message when price changes to avoid flooding the client.
    """
    yf_sym = _to_yfinance_symbol(symbol)
    last_price: Optional[float] = None

    logger.info("[stream] Starting stock poll stream for %s (interval=%ds)", symbol, STOCK_POLL_INTERVAL)

    while True:
        try:
            # Non-blocking check for client messages
            try:
                client_msg = await asyncio.wait_for(ws.receive_json(), timeout=0.01)
                action = client_msg.get("action", "")
                if action == "ping":
                    await _send_safe(ws, {"action": "pong"})
                elif action == "unsubscribe":
                    await ws.close()
                    return
            except (asyncio.TimeoutError, Exception):
                pass

            # Fetch quote in thread pool (yfinance is sync)
            def _sync_quote():
                try:
                    t = yf.Ticker(yf_sym)
                    fi = t.fast_info
                    price = float(getattr(fi, "last_price", 0) or 0)
                    open_p = float(getattr(fi, "regular_market_open", price) or price)
                    high = float(getattr(fi, "day_high", 0) or 0)
                    low = float(getattr(fi, "day_low", 0) or 0)
                    volume = float(getattr(fi, "three_month_average_volume", 0) or 0)
                    return price, open_p, high, low, volume
                except Exception as e:
                    logger.debug("[stream] yfinance poll %s: %s", symbol, e)
                    return None, None, None, None, None

            loop = asyncio.get_event_loop()
            price, open_p, high, low, volume = await loop.run_in_executor(None, _sync_quote)

            if price and price > 0:
                # Only push if price changed (or first tick)
                if last_price is None or abs(price - last_price) / last_price > 0.00005:
                    last_price = price
                    change_pct = ((price - open_p) / open_p * 100) if (open_p and open_p > 0) else 0.0

                    tick = {
                        "symbol":    symbol.upper(),
                        "price":     round(price, 4),
                        "change":    round(change_pct, 4),
                        "volume":    volume,
                        "high":      high,
                        "low":       low,
                        "timestamp": _now_iso(),
                        "source":    "yfinance_poll",
                    }
                    alive = await _send_safe(ws, tick)
                    if not alive:
                        return

        except WebSocketDisconnect:
            logger.info("[stream] Client disconnected from stock stream %s", symbol)
            return
        except Exception as e:
            logger.error("[stream] Stock poll error %s: %s", symbol, e)
            await _send_safe(ws, {"error": f"Poll error: {e}"})

        await asyncio.sleep(STOCK_POLL_INTERVAL)


# ── WebSocket endpoint ────────────────────────────────────────────────────────

@router.websocket("/stream/{symbol}")
async def market_stream(websocket: WebSocket, symbol: str):
    """
    Real-time price stream for a symbol.

    Connect: ws://<host>/api/market/stream/AAPL
             ws://<host>/api/market/stream/BTC

    Each message is a JSON tick:
      {"symbol": "AAPL", "price": 189.50, "change": 0.82, ...}

    Send {"action": "ping"} to test the connection.
    Send {"action": "unsubscribe"} to close cleanly.
    """
    await websocket.accept()
    sym = symbol.upper()
    logger.info("[stream] Client connected for %s", sym)

    # Send initial connection confirmation
    await _send_safe(websocket, {
        "action": "connected",
        "symbol": sym,
        "message": f"Streaming {sym}. "
                   + ("Real-time Binance ticks." if _is_crypto_symbol(sym) else f"Polling every {STOCK_POLL_INTERVAL}s (yfinance)."),
    })

    try:
        if _is_crypto_symbol(sym):
            await _stream_crypto(websocket, sym)
        else:
            await _stream_stocks(websocket, sym)
    except WebSocketDisconnect:
        logger.info("[stream] WebSocket disconnected: %s", sym)
    except Exception as e:
        logger.error("[stream] Fatal stream error %s: %s", sym, e)
        await _send_safe(websocket, {"error": str(e)})
    finally:
        try:
            await websocket.close()
        except Exception:
            pass
        logger.info("[stream] Stream closed for %s", sym)
