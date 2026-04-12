# APP_OVERVIEW.md — MarketCoach AI

**Last updated:** March 2026 (Phase 8)  
**Previous version was Feb 2026 (pre-Phase 3) — that version is now obsolete.**

---

## What the App Does

MarketCoach AI is a personal market learning and investing app. It combines real-time market data, AI-powered analysis, paper trading, and a coaching layer to help retail investors learn and grow.

---

## Navigation — 4 Tabs

| Tab | Screens |
|---|---|
| Home | Live markets strip (SPY/QQQ/BTC/ETH), watchlist, IQ Score card, today's lesson card |
| Trade | Markets tab + Paper Trading tab |
| Coach | Learn tab (guided lessons) + Chat tab (AI chat with Claude) |
| Portfolio | Real portfolio holdings + Paper trading P&L |

---

## Features — Actual Current State

### ✅ Built and Working
- Live market strip — SPY/QQQ via Yahoo WebSocket, BTC/ETH via Binance WebSocket
- Watchlist — defaults AAPL/BHP/BTC, stored in WatchlistRepository
- Stock detail screen — custom chart (custom painter), candlestick view
- Signal analysis engine — 6-layer pipeline, composite score -1.0 to +1.0
- MacroCard — FRED data tiles (Fed Rate, Yield Curve, DXY, Inflation) — **requires FRED_API_KEY in Railway**
- AI Chat — SSE streaming, session history, suggestion chips, markdown rendering
- Guided lessons — 12 step types, lesson engine
- Paper trading — buy/sell with weighted avg cost, 22%/15% capital gains tax on sell, reset to $1M
- Real portfolio — holdings CRUD, live price refresh, P&L
- Trade debrief — post-trade Claude coaching via /api/trade-debrief
- Investor IQ Score — 4 components (Lessons 300, Quizzes 250, Paper Trades 300, AI Chats 150)
- Freemium gate — 5 free AI messages/day, paywall UI
- Regulatory disclaimer — "For educational purposes only. Not financial advice."
- Fundamentals card — P/E, margins, ROE, D/E
- Earnings card — upcoming date + 8 quarters EPS history
- News sentiment — FinBERT or VADER, per-article scores

### ⚠️ Built but Broken (see BUGS.md)
- Paper trade holdings not updating after trade — BUG-004
- Chat paywall triggering too early — BUG-005
- FCM notifications never arrive — BUG-006 (send-side Cloud Function missing)
- IQ Score not persisted to Firestore — BUG-007
- Trade debrief missing indicator context — BUG-008
- Portfolio AI analysis crashes — BUG-001
- MacroCard empty if FRED_API_KEY missing from Railway — BUG-003

### ❌ Not Yet Built
- RevenueCat IAP — BUG-009 (payments not real)
- FCM Cloud Function (send-side)
- IQ Score Firestore persistence
- CORS lockdown for production
- Endpoint authentication (HTTPBearer)
- IP rate limiting (slowapi)

---

## Data Flow Summary

```
Market data  →  FastAPI backend  →  Signal package  →  Claude synthesis  →  Flutter UI
Firestore    →  User data (holdings, paper trades, subscriptions, IQ score)
FRED API     →  Macro data  →  MacroCard
Polygon/Finnhub/yfinance  →  Quotes, candles, fundamentals, news
```

---

## Deployment

- **Backend:** Railway — Docker, uvicorn, health check at /health
- **Frontend:** Flutter — iOS + Android
- **Database:** Firebase Firestore
- **Auth:** Firebase Auth
- **AI:** Anthropic API (claude-sonnet-4-6)
