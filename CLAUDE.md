# CLAUDE.md

MarketCoach — Flutter financial analysis app. Firebase Auth + Firestore, Python/FastAPI backend, Claude API for AI analysis.
**Platforms**: Android, iOS, macOS, Windows | **Package**: `com.finance.coach`

## Dev Commands

```bash
# Flutter
flutter run                           # run app
flutter run -d <device-id>            # specific device
flutter build apk / appbundle / ios   # build
flutter test && flutter analyze       # test + lint
flutter pub get && flutter clean      # deps / clean

# Backend
cd python-backend && run_dev.bat      # Windows
cd python-backend && docker-compose up -d  # Docker (API + Ollama)

# Firestore data
npm run import-lessons                # requires serviceAccountKey.json in project root
```

## Architecture

**Stack**: Flutter + Riverpod | Firebase Auth + Firestore | FastAPI (`python-backend/`) | Claude API

```
lib/
├── app/           # MarketCoachApp + RootShell (bottom nav, auth-aware)
├── config/        # api_config.dart — DO NOT commit real keys
├── data/          # FirestoreService, mock_data.dart, watchlist_repository
├── models/        # Plain Dart classes with fromMap() — see docs/architecture.md
├── providers/     # Riverpod providers
├── screens/       # One dir per screen; private widgets prefixed _
├── services/      # External APIs: auth, candle, claude, quote, watchlist…
├── utils/
└── widgets/       # Reusable widgets incl. chart/ sub-hierarchy
```

**Navigation**: `RootShell` → 6 tabs (Home, Market, Learn, Analysis, News, Profile). Detail screens use `Navigator.push()` / `MaterialPageRoute`.

**State management**:
- Riverpod — data providers (auth, lessons, analysis, candles, watchlist)
- StatefulWidget — local UI state
- StreamBuilder — real-time Firestore in screens

**Theme**: Material 3 dark. Seed `#12A28C`, bg `#0D131A`, card `#111925`.

## Key Data Flows

| Data | Source | Service/Provider |
|---|---|---|
| Market indices / news | `mock_data.dart` | — |
| Lessons | Firestore `lessons/` | `lessonProvider` |
| Auth state | Firebase Auth | `authStateProvider` |
| Candles (crypto) | Binance WS | `CandleService` |
| Candles (stocks) | Alpha Vantage → Yahoo fallback | `CandleService` |
| AI analysis | Claude API direct | `ClaudeAnalysisService` (24hr cache) |
| Watchlist | Firestore `users/{uid}/watchlist/` | `watchlistServiceProvider` |

**Firestore collections**: `lessons`, `learning`, `market_data`, `users`
**User subcollections**: `lesson_progress/{lessonId}`, `bookmarks/{lessonId}`, `watchlist/{symbol}`

## API Configuration

Keys in `lib/config/api_config.dart` — placeholder values only. Real keys in `python-backend/.env` (gitignored).

```dart
class APIConfig {
  static const String claudeApiKey = 'YOUR_KEY_HERE';
  static const String claudeModel = 'claude-sonnet-4-20250514';
  static bool get isConfigured => claudeApiKey != 'YOUR_KEY_HERE' && claudeApiKey.isNotEmpty;
}
```

## Auth Flow

`authStateProvider` (StreamProvider<User?>) → null → LoginScreen → RootShell on success.

`AuthService`: `signUpWithEmail`, `signInWithEmail`, `signInAnonymously`, `linkAnonymousAccount`, `signOut`.

User profile path: `users/{uid}` — fields: `uid`, `email`, `display_name`, `is_anonymous`, `created_at`, `last_seen_at`.

Admin account: `sandippandey01.sp@gmail.com` → `SubscriptionTier.admin` (bypasses RevenueCat).

## Critical Patterns

### Firestore Timestamp — always safe-parse
```dart
static DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}
```
Field name: use `minutes` not `duration_minutes` in lesson schema.

### StreamBuilder in CustomScrollView
Wrap the **entire** `CustomScrollView` with `StreamBuilder`. Never embed `StreamBuilder` inside a slivers list — causes `RenderViewport expected RenderSliver` + GlobalKey conflicts.

### ZoomPanBehavior (Syncfusion chart)
Declare as `late final` field in State class, not inline in `build()`. Required for `reset()` calls.

### Stock vs Crypto Candles
Check `stock.isCrypto` in `_loadData()`. Crypto → Binance; Stocks → AlphaVantage + Yahoo fallback. Default timeframe: crypto=`1h`, stocks=`1D`.

### Riverpod Provider Pattern
```dart
// Service
final myProvider = Provider<MyService>((ref) => MyService(ref.watch(depProvider)));

// Async with param
final lessonProvider = FutureProvider.family<T, String>((ref, id) async { … });

// Real-time
final progressProvider = StreamProvider.family<T?, String>((ref, id) { … });
```

## Working Rules

**Prime directive**: Ship working code in small vertical slices. Do not redesign UI unless explicitly asked.

**Output format**: plan (≤8 bullets) → minimal diff → explanation (≤5 bullets) → how to test. Do NOT paste entire files.

**Architecture**: Respect existing `lib/` structure. Riverpod for new providers, StatefulWidget for local UI state. No speculative abstractions.

**Security**: Never hardcode API keys in committed files. Use TODO comments instead of guessing.

**Done criteria**: builds + no nav crashes + works end-to-end.

## AI Upgrade Status

Full detail in `docs/ai-upgrade.md`.

| Feature | Status |
|---|---|
| CrewAI 6-agent swarm (Market/Sentiment/Fundamentals/Technical/Risk/Coach) | ✅ Done |
| LangGraph 5-node pipeline (intent→tool_router→reasoning→verification→synthesis) | ✅ Done |
| FundamentalsAgent (DCF, WACC, margin of safety, earnings quality) | ✅ Done |
| RiskAgent (ATR stop/TP, 2%-rule position sizing) | ✅ Done |
| ChromaDB per-user memory | ✅ Done |
| Ollama / Mistral 7B | ✅ Done |
| Scenario Card (Bull/Base/Bear) | ✅ Done |
| Dean Agent coaching nudges | ✅ Done |
| Email verification gate | ✅ Done |
| RevenueCat purchase flow | ✅ Done |
| Market data endpoints (yfinance) | ✅ Done |
| Jarvis Voice — voice_ws.py proxy + VoiceOverlayBar + FloatingVoiceButton wired | ✅ Done |
| Voice persistent overlay bar in RootShell | ✅ Done |
| Chart Vision — backend (vision.py + vision_analysis_service.py) + Flutter (vision_repository.dart + image picker in JarvisChatScreen) | ✅ Done |
| Backend endpoints: orderbook, moneyflow, marketposition, options | ✅ Done |
| FinBERT wired to CrewAI (per-article scoring + VADER fallback) | ✅ Done |
| PostgreSQL + pgvector RAG (SEC filings) — embedder, ingestor, retriever | ✅ Done |
| Voice workers: session_summary, memory_extraction, behavior_analysis | ✅ Done |
| FRED macro service | ✅ Done |
| Redis — in docker-compose, session_repo + usage_counter_repo wired | ✅ Done |
| Coach screen — Chat + Voice unified (TabBar with JarvisChatScreen + VoiceCoachScreen) | ✅ Done |
| Stock detail overhaul (MooMoo UI) | 🔴 Not started — directory empty |
| Crypto detail overhaul (MooMoo UI) | 🔴 Not started — no screen exists |
| TradingView Lightweight Charts | 🔴 Not started — Syncfusion only |
| Strategy overlay | 🔴 Not started |
| Phase 9: Probabilistic engine (Monte Carlo, Bayesian, MacroAgent, Black Swan) | 🔴 Not started — no service files |
| Reddit PRAW sentiment | 🔴 Not started — no files |
| Dynamic quizzes via Ollama | 🔴 Not started |
| Subscription tier gating (full) | 🟡 Partial — service + RevenueCat wired, gating in 5 screens only |
| PersonaPlex voice (desktop) | ⏳ Future |

## Remaining Work — Priority Order

*Updated 2026-05-02 — verified against actual codebase. Items 1–5 from previous list are DONE.*

| # | Item | Effort | Depends |
|---|---|---|---|
| 1 | Stock detail overhaul (A1–A6, MooMoo UI) | 3d | — (backend ✅) |
| 2 | Crypto detail overhaul (B1–B4, MooMoo UI) | 2d | — (backend ✅) |
| 3 | TradingView chart widget (replace Syncfusion) | 1wk | — |
| 4 | MooMoo data panels (orderbook/moneyflow UI) | 1wk | #1, #3 |
| 5 | Strategy overlay | 5d | #3 |
| 6 | Phase 9: Probabilistic engine (Monte Carlo, Bayesian, MacroAgent, Black Swan) | 1wk | — |
| 7 | Full subscription tier gating | 2d | RevenueCat ✅ |
| 8 | Reddit PRAW sentiment | 1d | — |
| 9 | Dynamic quizzes via Ollama | 2d | Ollama ✅ |
| 10 | PersonaPlex voice (desktop) | Future | — |

## Docker Services

`cd python-backend && docker-compose up -d`

| Service | Port | Notes |
|---|---|---|
| `python-backend-api-1` | 8000 | FastAPI; mounts `market-coach-chroma` volume |
| `market-coach-ollama` | 11434 | Mistral 7B. First run: `docker exec market-coach-ollama ollama pull mistral` |

Env vars: `OLLAMA_BASE_URL=http://ollama:11434`, `CHROMA_PERSIST_PATH=/data/chroma`

## Jarvis Voice Architecture

Flutter → `POST /api/voice/session/create` → ephemeral OpenAI token → Flutter opens WebSocket to OpenAI Realtime.
Tool calls are proxied: `tool_call` event → `POST /api/voice/tools/invoke` → result returned.
End session triggers 3 background workers: summary, memory extraction, behaviour analysis.

**Chrome is broken**: `IOWebSocketChannel` (dart:io) fails on web. Fix = WS backend proxy (`voice_ws.py`). See `docs/remaining-work.md` #1.

Key files: `jarvis_realtime_service.dart`, `voice_session_provider.dart`, `voice_coach_screen.dart`, `python-backend/app/routers/voice.py`, `session_bootstrap.py`.

Voice entry point: `FloatingVoiceButton` FAB in `RootShell` (bottom-right, above nav bar).
