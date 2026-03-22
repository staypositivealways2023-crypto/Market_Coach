# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MarketCoach is a Flutter-based financial analysis mobile application that provides market insights, educational content, AI-powered stock analysis, and portfolio tracking. The app integrates with Firebase for backend services (Authentication, Firestore), uses a Python/FastAPI backend for market data and technical indicators, and calls the Claude API directly for AI analysis.

**Target Platforms**: Android, iOS, macOS, Windows
**Package**: `com.finance.coach`

## Development Commands

### Running the App
```bash
# Run on connected device/simulator
flutter run

# Run on specific device
flutter run -d <device-id>

# Run with hot reload enabled (default)
flutter run --hot

# Build and run in release mode
flutter run --release
```

### Building
```bash
# Build APK (Android)
flutter build apk

# Build App Bundle (Android - for Play Store)
flutter build appbundle

# Build iOS
flutter build ios

# Build for macOS
flutter build macos

# Build for Windows
flutter build windows
```

### Testing & Quality
```bash
# Run tests
flutter test

# Run specific test file
flutter test test/widget_test.dart

# Run analyzer (lint)
flutter analyze

# Format code
flutter format lib/

# Check for outdated packages
flutter pub outdated
```

### Dependencies
```bash
# Install dependencies
flutter pub get

# Upgrade dependencies
flutter pub upgrade

# Clean build artifacts
flutter clean
```

### Firestore Data Import
```bash
# Import lessons to Firestore (requires serviceAccountKey.json)
npm run import-lessons

# Import custom lesson file
node scripts/import_lessons.js path/to/lesson.json
```

**Setup**: Download service account key from Firebase Console → Project Settings → Service Accounts and save as `serviceAccountKey.json` in project root.

### Python Backend
```bash
# Start backend (Windows)
cd python-backend && run_dev.bat

# Start backend (Unix)
cd python-backend && ./run_dev.sh

# Run with Docker
cd python-backend && docker-compose up

# Run backend tests
cd python-backend && pytest
```

## Architecture

### Project Structure

```
lib/
├── app/                    # Application-level widgets & shell
│   ├── market_coach_app.dart   # Root MaterialApp with theme
│   └── root_shell.dart         # Bottom navigation shell (auth-aware)
├── config/                 # App configuration
│   └── api_config.dart         # API keys & endpoints (DO NOT commit real keys)
├── data/                   # Data layer
│   ├── firestore_service.dart  # Firebase Firestore operations
│   ├── mock_data.dart          # Static mock data for development
│   └── watchlist_repository.dart  # Local watchlist persistence
├── models/                 # Data models (plain Dart classes)
│   ├── ai_analysis.dart        # AI analysis result model
│   ├── analysis_highlight.dart
│   ├── candle.dart
│   ├── enhanced_ai_analysis.dart  # Structured Claude API analysis model
│   ├── indicator.dart          # Technical indicator model
│   ├── lesson.dart
│   ├── lesson_bookmark.dart    # Lesson bookmark model
│   ├── lesson_progress.dart    # Lesson progress tracking model
│   ├── lesson_screen.dart      # Individual lesson screen content
│   ├── market_index.dart
│   ├── news_item.dart
│   ├── quote.dart
│   ├── stock_summary.dart
│   ├── user_profile.dart       # User profile stored in Firestore
│   └── valuation.dart          # Stock valuation model
├── providers/              # Riverpod providers for state management
│   ├── analysis_provider.dart
│   ├── auth_provider.dart          # Auth state stream provider
│   ├── bookmarks_provider.dart     # Lesson bookmarks stream
│   ├── candle_provider.dart
│   ├── connectivity_provider.dart  # Network connectivity state
│   ├── enhanced_analysis_provider.dart
│   ├── firebase_provider.dart
│   ├── firestore_service_provider.dart
│   ├── lesson_progress_provider.dart  # Progress stream provider
│   ├── lesson_provider.dart
│   ├── market_data_provider.dart
│   └── watchlist_service_provider.dart
├── screens/               # Feature screens (one directory per screen)
│   ├── analysis/           # AI analysis tab + private widgets
│   │   ├── analysis_screen.dart
│   │   ├── _ai_analysis_card.dart
│   │   ├── _analysis_error_card.dart
│   │   ├── _analysis_loading_state.dart
│   │   ├── _enhanced_analysis_display.dart
│   │   └── _stock_selector.dart
│   ├── auth/               # Authentication screens
│   │   ├── login_screen.dart
│   │   ├── signup_screen.dart
│   │   ├── forgot_password_screen.dart
│   │   └── account_upgrade_screen.dart  # Anonymous → real account
│   ├── home/
│   ├── learn/
│   ├── lesson_detail/
│   ├── market/
│   │   ├── market_screen.dart
│   │   ├── market_category_screen.dart  # Stocks vs Crypto filtered view
│   │   └── market_view_all_screen.dart
│   ├── news/
│   ├── profile/
│   └── stock_detail/
│       ├── stock_detail_screen.dart          # Basic stock detail
│       └── stock_detail_screen_enhanced.dart # Enhanced with charts + indicators
├── services/              # External API services
│   ├── analysis_cache_service.dart     # Caches AI analysis results
│   ├── auth_service.dart               # Firebase Auth operations
│   ├── candle_service.dart             # Binance/Yahoo/AlphaVantage candles
│   ├── claude_analysis_service.dart    # Direct Claude API integration
│   ├── enhanced_analysis_service.dart  # Orchestrates analysis pipeline
│   ├── pattern_recognition_service.dart  # Chart pattern detection
│   ├── quote_service.dart
│   ├── stock_data_service.dart         # Aggregates stock data for analysis
│   ├── technical_analysis_service.dart # EMA, RSI, MACD calculations
│   └── watchlist_service.dart          # Watchlist CRUD operations
├── utils/                 # Utility functions
│   ├── auth_helper.dart        # Auth convenience helpers
│   ├── crypto_helper.dart      # Crypto-specific utilities
│   └── performance_utils.dart  # Performance helpers
├── widgets/               # Reusable widgets
│   ├── chart/                  # Chart widget hierarchy
│   │   ├── advanced_indicator_settings.dart  # Indicator parameter UI
│   │   ├── advanced_price_chart.dart         # Main chart widget (candle/line/area)
│   │   ├── chart_type_selector.dart          # Chart type toggle
│   │   ├── indicator_controls.dart           # EMA/RSI/MACD toggles
│   │   ├── macd_sub_chart.dart               # MACD sub-chart panel
│   │   └── rsi_sub_chart.dart                # RSI sub-chart panel
│   ├── educational_bottom_sheet.dart  # Educational popups for chart patterns
│   ├── glass_card.dart                # Glassmorphic card widget
│   ├── lesson_screen_widget.dart      # Renders lesson screen types
│   └── live_line_chart.dart
├── firebase_options.dart  # Generated Firebase config
└── main.dart             # App entry point
```

### Python Backend Structure

```
python-backend/
├── app/
│   ├── main.py                      # FastAPI app entry point
│   ├── config.py                    # Environment config (reads .env)
│   ├── models/
│   │   ├── analysis.py              # Pydantic analysis models
│   │   ├── indicator.py
│   │   ├── stock.py
│   │   └── valuation.py
│   ├── routers/
│   │   ├── analysis.py              # /api/analysis endpoints (Claude)
│   │   ├── indicators.py            # /api/indicators endpoints
│   │   ├── internal.py              # Internal/admin endpoints
│   │   └── market.py               # /api/market endpoints
│   ├── services/
│   │   ├── analysis_aggregator.py   # Aggregates analysis data
│   │   ├── claude_service.py        # Claude API calls
│   │   ├── data_fetcher.py          # Multi-source data (AV/Finnhub/yfinance)
│   │   ├── firestore_writer.py      # Writes to Firestore
│   │   ├── indicator_service.py     # TA-Lib indicators
│   │   ├── mock_analysis_service.py # Mock for dev/testing
│   │   └── valuation_service.py     # DCF + comparative metrics
│   └── utils/
│       ├── analysis_rate_limiter.py
│       ├── cache.py                 # In-memory caching
│       ├── logger.py
│       ├── prompt_builder.py        # Claude prompt templates
│       └── rate_limiter.py
├── scripts/                         # Data population scripts
│   ├── populate_all_market_data.py
│   ├── populate_crypto_data.py
│   ├── populate_popular_stocks.py
│   └── ...
├── .env                             # Local secrets (never commit)
├── .env.example                     # Template for secrets
├── docker-compose.yml
├── Dockerfile
└── requirements.txt
```

### Navigation Architecture

The app uses a **bottom navigation bar shell** (`RootShell`) with 6 main tabs:
1. Home - Dashboard with watchlist and market overview
2. Market - Market data and indices (Stocks/Crypto category views)
3. Learn - Educational lessons and resources
4. Analysis - AI-powered market analysis via Claude API
5. News - Financial news feed
6. Profile - User profile and settings

`RootShell` is auth-aware: shows login/signup flow before the main app when unauthenticated.
Navigation between detail screens uses standard `Navigator.push()` with `MaterialPageRoute`.

### Data Flow

- **Mock Data**: Static mock data from `lib/data/mock_data.dart` for Home, Market (indices), News screens
- **Firebase Integration**:
  - `FirestoreService` provides methods to read/write learning content and market data
  - Supports both one-time reads and real-time streams via `snapshots()`
  - Collections: `lessons`, `learning`, `market_data`, `users`
  - **Lessons Structure**:
    - Lesson metadata: `lessons/{lessonId}`
    - Lesson screens: `lessons/{lessonId}/screens/{screenId}` (ordered by `order` field)
  - **User Data**:
    - Profile: `users/{userId}`
    - Progress: `users/{userId}/lesson_progress/{lessonId}`
    - Bookmarks: `users/{userId}/bookmarks/{lessonId}`
- **Candle Data**: `CandleService` fetches from Binance (crypto), Yahoo Finance, or Alpha Vantage with fallbacks
- **AI Analysis**: `ClaudeAnalysisService` → calls Claude API directly with stock data context
- **State Management**:
  - **Riverpod**: Used for lesson data, auth state, analysis, candles, watchlist, connectivity
  - **StatefulWidget/ConsumerWidget**: Mixed approach - Riverpod for complex data fetching, StatefulWidget for local UI state
  - **StreamBuilder**: Used directly in some screens (e.g., `LearnScreen`) for real-time Firestore updates

### Theme & Styling

- **Material 3**: Uses Material Design 3 with dark theme
- **Color Scheme**: Seed color `#12A28C` (teal/green accent)
- **Background**: Dark background `#0D131A` with card color `#111925`
- **Typography**: White Mountain View typography with white text

## Firebase Setup

### Configuration Files
- Android: `android/app/google-services.json`
- iOS: `ios/Runner/GoogleService-Info.plist`
- Generated options: `lib/firebase_options.dart` (via `flutterfire configure`)

### Initialization
Firebase is initialized in `main.dart` before running the app:
```dart
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
```

### Re-generating Firebase Config
If Firebase configuration changes:
```bash
# Install FlutterFire CLI if not already installed
dart pub global activate flutterfire_cli

# Regenerate config
flutterfire configure
```

## Models

All models are simple Dart classes with `fromMap` factory constructors for Firestore deserialization:

- **Lesson**: Educational content metadata (title, subtitle, duration, level, body)
- **LessonScreen**: Individual lesson screen content with type-based rendering
  - Types: `intro`, `text`, `diagram`, `quiz_single`, `bullets`, `takeaways`
- **LessonProgress**: Tracks user progress per lesson (`current_screen`, `completed`, `last_accessed_at`)
- **LessonBookmark**: Stores bookmarked lessons per user with `created_at` timestamp
- **StockSummary**: Represents stock/crypto with price, fundamentals, and technical highlights
- **MarketIndex**: Index ticker, name, value, and change percentage
- **NewsItem**: News article with title, source, timestamp, summary, and sentiment
- **AnalysisHighlight**: Market analysis with title, subtitle, tag, confidence, and body
- **Quote**: Real-time stock quote data
- **Candle**: OHLCV candlestick data
- **EnhancedAIAnalysis**: Structured Claude API analysis — `sentimentScore` (0-100), `recommendation`, `bullishFactors`, `bearishFactors`, `riskLevel`, `priceTarget`, `technicalSummary`
- **AIAnalysis**: Simpler AI analysis wrapper (markdown body)
- **Indicator**: Technical indicator data (EMA, RSI, MACD values)
- **Valuation**: DCF and comparative valuation metrics
- **UserProfile**: User account data stored in Firestore (`displayName`, `email`, `isAnonymous`, `createdAt`)

### Important Model Patterns

**Timestamp Handling**: Firestore returns `Timestamp` objects, not integers. Use safe parsing:
```dart
static DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}
```

Models use constructors with named parameters and computed getters where appropriate (e.g., `StockSummary.isPositive`).

## Key Patterns

### Screen Organization
Each screen directory contains:
- Main screen file (e.g., `home_screen.dart`)
- Private widgets prefixed with underscore (e.g., `_LiveMarketCard`)
- Related child screens if applicable

### Navigation Pattern
```dart
Navigator.of(context).push(
  MaterialPageRoute(builder: (_) => DetailScreen(data: data)),
);
```

### Firebase Streams
```dart
// Real-time updates
_db.collection('lessons')
   .orderBy('published_at', descending: true)
   .snapshots();

// Document-specific stream
_db.collection('market_data')
   .doc(symbol)
   .snapshots();
```

### Riverpod Provider Pattern
```dart
// Service provider
final firestoreServiceProvider = Provider<FirestoreService>((ref) {
  final db = ref.watch(firebaseProvider);
  return FirestoreService(db);
});

// Data provider with family modifier for parameters
final lessonProvider = FutureProvider.family<LessonWithScreens, String>((ref, lessonId) async {
  final service = ref.watch(firestoreServiceProvider);
  return LessonWithScreens(lesson: lesson, screens: screens);
});

// Stream provider for real-time data
final lessonProgressProvider = StreamProvider.family<LessonProgress?, String>((ref, lessonId) {
  // returns stream from Firestore
});
```

### StreamBuilder in CustomScrollView

**Critical Pattern**: When using `StreamBuilder` with `CustomScrollView`, wrap the entire `CustomScrollView` with `StreamBuilder`, not individual slivers. Build the slivers list conditionally inside the builder:

```dart
StreamBuilder<QuerySnapshot>(
  stream: FirebaseFirestore.instance.collection('lessons').snapshots(),
  builder: (context, snapshot) {
    final List<Widget> slivers = [
      SliverToBoxAdapter(child: Header()),
    ];
    if (snapshot.hasError) {
      slivers.add(SliverToBoxAdapter(child: ErrorWidget()));
    } else if (snapshot.connectionState == ConnectionState.waiting) {
      slivers.add(SliverToBoxAdapter(child: LoadingWidget()));
    } else {
      slivers.add(SliverList(...));
    }
    return CustomScrollView(slivers: slivers);
  },
)
```

**Why**: Embedding `StreamBuilder` directly in the slivers list causes `RenderViewport expected RenderSliver` errors and GlobalKey conflicts.

## Platform-Specific Notes

### Android
- Min SDK: 24 (Android 7.0)
- Target SDK: 34
- Application ID: `com.finance.coach`
- Multidex enabled

### Dependencies
- **firebase_core** `^4.4.0`: Firebase initialization
- **firebase_auth** `^6.1.4`: Authentication (login/signup/forgot password)
- **cloud_firestore** `^6.1.2`: Firestore database
- **flutter_riverpod** `^2.0.6`: State management for data providers
- **provider** `^6.0.5`: Alternative state management (legacy, prefer Riverpod)
- **http** `^1.2.2`: HTTP client for REST APIs (Claude API, Alpha Vantage)
- **web_socket_channel** `^3.0.1`: WebSocket connections (Binance live data)
- **syncfusion_flutter_charts** `^28.1.33`: Charting library (candlestick, line, area)
- **shared_preferences** `^2.3.3`: Local key-value storage
- **connectivity_plus** `^5.0.0`: Network connectivity detection
- **intl** `^0.19.0`: Date/number formatting

## API Configuration

API keys are stored in `lib/config/api_config.dart`. **Never commit real keys.** The file contains placeholder values that fail `isConfigured` checks, causing the app to gracefully show an error instead of crashing.

```dart
class APIConfig {
  static const String claudeApiKey = 'YOUR_KEY_HERE';
  static const String alphaVantageKey = 'YOUR_KEY_HERE';
  static const String claudeModel = 'claude-sonnet-4-20250514';

  static bool get isConfigured => claudeApiKey != 'YOUR_KEY_HERE' && claudeApiKey.isNotEmpty;
}
```

Real keys go in `python-backend/.env` (gitignored). Flutter reads them via `dart-define` or the Python backend serves them.

## Authentication System

Full Firebase Auth flow with Riverpod state management:

### Auth Flow
1. App starts → checks `authStateProvider` (stream of `User?`)
2. If `null` → shows `LoginScreen`
3. `LoginScreen` → email/password sign-in or navigate to `SignupScreen`
4. `SignupScreen` → creates account, writes `users/{uid}` profile to Firestore
5. `ForgotPasswordScreen` → Firebase password reset email
6. `AccountUpgradeScreen` → converts anonymous session to permanent account
7. On sign-in success → `RootShell` shown with full app

### Auth Providers
- **`authStateProvider`**: `StreamProvider<User?>` — stream of Firebase auth state
- **`authProvider`**: Current `User?` via `authStateProvider.stream`

### AuthService
`lib/services/auth_service.dart` wraps all Firebase Auth operations:
- `signUpWithEmail()` — creates account + Firestore profile
- `signInWithEmail()` — email/password login
- `signInAnonymously()` — guest access
- `sendPasswordResetEmail()` — forgot password
- `linkAnonymousAccount()` — upgrade guest to real account
- `signOut()`

### User Profile Firestore Schema
```
users/{userId}
  - uid: string
  - email: string
  - display_name: string
  - is_anonymous: bool
  - created_at: Timestamp
  - last_seen_at: Timestamp
```

### Current Auth State
- Firebase Auth fully wired; hardcoded `guest_user` ID removed from lesson progress
- Auth gates the app — unauthenticated users see login screen

## AI Analysis System

The Analysis tab provides Claude-powered stock analysis with caching.

### Flow
1. User selects a stock symbol via `_StockSelector`
2. `AnalysisScreen` calls `EnhancedAnalysisService.analyze(symbol)`
3. `EnhancedAnalysisService` checks `AnalysisCacheService` (24hr TTL)
4. If miss: `ClaudeAnalysisService` fetches stock data via `StockDataService`, builds prompt, calls Claude API
5. Claude returns structured JSON → parsed into `EnhancedAIAnalysis`
6. Result cached + displayed in `_EnhancedAnalysisDisplay`

### Claude API Integration
`ClaudeAnalysisService` calls `https://api.anthropic.com/v1/messages` directly:
- Model: `claude-sonnet-4-20250514` (configurable in `APIConfig`)
- Returns structured JSON (not markdown) for reliable parsing
- Error types: `AnalysisException`, `RateLimitException` (429), `ServiceUnavailableException` (503)

### EnhancedAIAnalysis Fields
- `sentimentScore`: 0–100 (bearish → bullish)
- `recommendation`: enum (strongBuy / buy / hold / sell / strongSell)
- `bullishFactors` / `bearishFactors`: `List<String>`
- `riskLevel`: enum (low / medium / high / veryHigh)
- `priceTarget`: optional `PriceTarget` with low/mid/high values
- `technicalSummary`: optional string

### Python Backend Analysis
The Python backend at `python-backend/` also provides analysis via:
- `POST /api/analysis/{symbol}` — Claude-powered analysis
- `GET /api/indicators/{symbol}` — Technical indicators via TA-Lib
- `GET /api/market/{symbol}` — Market data (multi-source with fallback)

## Enhanced Stock Detail Screen

`StockDetailScreenEnhanced` (`lib/screens/stock_detail/stock_detail_screen_enhanced.dart`) provides:

### Chart Features
- **Chart types**: Candlestick (default), Line, Area — toggled via `ChartTypeSelector`
- **Default state**: Candlestick chart only, no indicators on load
- **Timeframes**:
  - Crypto: 1m, 5m, 15m, 1h, 4h, 1D
  - Stocks: 1D, 1W, 1M, 3M, 1Y
- **Zoom controls**: Zoom in, zoom out, reset — via `ZoomPanBehavior` stored in state
- **Double-tap zoom**, **mouse wheel zoom**, **selection zoom** all enabled

### Data Sources (with fallback chain)
- **Crypto**: Binance WebSocket → `BinanceCandleService`
- **Stocks**: Alpha Vantage primary → Yahoo Finance fallback → `AlphaVantageCandleService` / `YahooFinanceCandleService`

### Technical Indicators (via `IndicatorControls`)
- **EMA** (9, 21, 50, 200 periods) — overlaid on price chart
- **RSI** (14 period) — shown in `RsiSubChart` below price chart
- **MACD** (12/26/9) — shown in `MacdSubChart` below price chart
- Settings configurable via `AdvancedIndicatorSettings` bottom sheet

### Chart Axis Behaviour
- X-axis: auto date format + interval based on data range duration
- Y-axis: `desiredIntervals=5`, compact number format for large prices
- `edgeLabelPlacement` and `enableAutoIntervalOnZooming` on both axes
- `CandleSeries` spacing=0.2 for cleaner proportions

### Educational Bottom Sheet
Tapping chart patterns triggers `EducationalBottomSheet` with pattern explanations (from `PatternRecognitionService`).

## Technical Analysis

`TechnicalAnalysisService` (`lib/services/technical_analysis_service.dart`) provides pure-Dart indicator calculations:
- `calculateEMA(candles, period)` — Exponential Moving Average
- `calculateRSI(candles, period)` — Relative Strength Index
- `calculateMACD(candles, fast, slow, signal)` — MACD line + signal + histogram

`PatternRecognitionService` (`lib/services/pattern_recognition_service.dart`) detects:
- Double top / double bottom
- Head and shoulders
- Support / resistance levels

## Watchlist System

- **`WatchlistRepository`** (`lib/data/watchlist_repository.dart`): Local persistence via `shared_preferences`
- **`WatchlistService`** (`lib/services/watchlist_service.dart`): Business logic — add/remove/check
- **`watchlistServiceProvider`**: Riverpod provider for watchlist state
- Watchlist state shown in `StockDetailScreenEnhanced` via heart/bookmark icon

## Lesson System Architecture

The app has a complete lesson delivery system with interactive content:

### Lesson Flow
1. **LearnScreen** (`lib/screens/learn/learn_screen.dart`):
   - Displays list of lessons from Firestore using `StreamBuilder`
   - Real-time updates when new lessons are added
   - Search by title/subtitle; filter by status and level
   - Tapping a lesson navigates to `LessonDetailScreen`

2. **LessonDetailScreen** (`lib/screens/lesson_detail/lesson_detail_screen.dart`):
   - Uses Riverpod `lessonProvider` to fetch lesson + screens
   - Renders screens in a `PageView` with navigation controls
   - Auto-saves progress as user navigates screens
   - Bookmark icon in AppBar

3. **LessonScreenWidget** (`lib/widgets/lesson_screen_widget.dart`):
   - Type-based rendering: intro, text, diagram, quiz_single, bullets, takeaways
   - Stateful quiz screens with answer checking
   - Extracts content from `content` map based on screen type

### Lesson Data Structure

**Firestore Schema**:
```
lessons/{lessonId}
  - title: string
  - subtitle: string
  - level: string (Beginner/Intermediate/Advanced)
  - minutes: int
  - body: string
  - published_at: Timestamp
  - type: string (optional)

lessons/{lessonId}/screens/{screenId}
  - type: string (intro|text|diagram|quiz_single|bullets|takeaways)
  - order: int (determines display order)
  - title: string (optional)
  - subtitle: string (optional)
  - content: map (type-specific fields)
```

### Screen Type Content Fields

- **intro**: `icon` (string)
- **text**: `body` (string)
- **diagram**: `imageUrl` (string), `caption` (string)
- **quiz_single**: `question` (string), `options` (array), `correctIndex` (int), `explanation` (string)
- **bullets**: `items` (array of strings)
- **takeaways**: `items` (array of strings)

## Lesson Progress Tracking

The app tracks user progress through lessons using Firestore with real-time updates.

### Firestore Schema

```
users/{userId}/lesson_progress/{lessonId}
  - lesson_id: string
  - user_id: string
  - current_screen: int (0-indexed, last viewed screen)
  - total_screens: int
  - completed: bool
  - last_accessed_at: Timestamp
  - completed_at: Timestamp | null

users/{userId}/bookmarks/{lessonId}
  - lesson_id: string
  - user_id: string
  - created_at: Timestamp
```

### Providers

- **`lessonProgressProvider(lessonId)`**: StreamProvider for real-time progress on a single lesson
- **`allProgressProvider`**: StreamProvider for all lesson progress records for the current user
- **`bookmarksProvider`**: StreamProvider for bookmarked lesson IDs

### Progress States

- **Not Started**: `current_screen == 0 && !completed`
- **In Progress**: `current_screen > 0 && !completed`
- **Completed**: `completed == true`

### User Features

- **Progress Tracking**: Automatically saves progress as users navigate through lesson screens
- **Bookmarking**: Users can bookmark lessons for quick access via the bookmark icon in LessonDetailScreen
- **Search**: Search lessons by title or subtitle
- **Filters**:
  - **Status**: All, Bookmarked, Completed, In Progress, Not Started
  - **Level**: All, Beginner, Intermediate, Advanced
- **Offline Support**: Firestore persistence enabled — lessons cached automatically for offline viewing
- **Visual Indicators**:
  - Green checkmark on completed lessons
  - Circular progress indicator on in-progress lessons
  - Progress percentage shown in lesson card
  - Offline banner when no network connection

### Adding New Screen Types

To add a new lesson screen type:

1. Add type constant to `LessonScreen` model (lib/models/lesson_screen.dart)
2. Create new widget method in `lesson_screen_widget.dart` (e.g., `_buildVideoScreen`)
3. Add case to switch statement in `LessonScreenWidget.build()`
4. Document content structure in method comment
5. Add to seed data JSON schema for import script

## Testing Guidelines

### Running Tests
```bash
flutter test                    # All tests
flutter test test/models/       # Model tests only
flutter test test/widgets/      # Widget tests only
flutter test --coverage         # With coverage report
```

### Test Files
```
test/
├── analysis_test.dart
├── data/
│   └── firestore_service_test.dart
├── models/
│   ├── lesson_progress_test.dart
│   └── lesson_test.dart
├── services/
│   └── candle_service_test.dart
├── utils/
│   └── auth_helper_test.dart
├── watchlist_repository_test.dart
├── widget_test.dart
└── widgets/
    └── lesson_screen_widget_test.dart
```

### Mock Firestore
Use `fake_cloud_firestore` for testing Firestore operations:
```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

final firestore = FakeFirebaseFirestore();
final service = FirestoreService(firestore);

await firestore.collection('lessons').doc('test-lesson').set({
  'title': 'Test Lesson',
  'subtitle': 'Test subtitle',
});

final lesson = await service.fetchLesson('test-lesson');
expect(lesson?.title, 'Test Lesson');
```

## Development Notes

- **Lesson System**: Fully integrated with Firestore with progress tracking and bookmarking — use `npm run import-lessons` to add content
- **Mixed State Management**: Riverpod for data providers, StatefulWidget for local UI state, StreamBuilder for real-time updates
- **Mock Data**: Still used in some screens (Home, Market indices, News, Analysis highlights) — migrating to Firestore gradually
- **Authentication**: Fully wired — login/signup/forgot-password/anonymous→upgrade flow; no more hardcoded `guest_user`
- **Offline First**: Firestore persistence enabled in main.dart with unlimited cache size
- **Analysis Caching**: AI analysis cached 24 hrs in `AnalysisCacheService` to avoid API overuse
- **Python Backend**: FastAPI service in `python-backend/` handles market data aggregation, TA-Lib indicators, and Claude analysis for server-side use

## MarketCoach Working Rules (Token Saver)

### Prime directive
Ship working code in small vertical slices. Do not redesign UI unless explicitly asked.

### Output rules (to reduce token usage)
- When implementing features: return ONLY:
  1) a short plan (max 8 bullets)
  2) a git-style diff
  3) a brief explanation (max 5 bullets)
  4) how to run/test
- Do NOT paste entire files unless asked.
- Prefer minimal diffs over full rewrites.

### Architecture rules
- Respect existing structure: lib/app, lib/config, lib/data, lib/models, lib/providers, lib/screens, lib/services, lib/utils, lib/widgets
- **State Management**: Use Riverpod for new data providers, StatefulWidget for local UI state
- UI layout and styling must not be changed unless requested
- When working with Firestore timestamps, always use safe parsing (see Models section)

### Safety rules
- Never hardcode API keys in committed files
- `lib/config/api_config.dart` uses placeholder values — real keys go in `python-backend/.env`
- Add TODO comments instead of guessing

### Done criteria
A feature is done only if:
1) App builds
2) No navigation crashes
3) Feature works end-to-end

## Common Pitfalls & Solutions

### 1. Firestore Timestamp Casting
**Problem**: `type 'Timestamp' is not a subtype of type 'int'`

**Solution**: Firestore returns `Timestamp` objects, not integers. Always use safe parsing in `fromMap`:
```dart
publishedAt: _parseDateTime(map['published_at'])

static DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}
```

### 2. StreamBuilder in CustomScrollView
**Problem**: `RenderViewport expected RenderSliver` errors, GlobalKey conflicts

**Solution**: Wrap entire `CustomScrollView` with `StreamBuilder`, not individual slivers. Build slivers list conditionally inside the builder function.

### 3. Field Name Mismatches
**Problem**: Reading wrong Firestore field names (e.g., `duration_minutes` vs `minutes`)

**Solution**: Check the actual Firestore schema before implementing `fromMap`. The lesson schema uses `minutes`, not `duration_minutes`.

### 4. Candlestick Chart — ZoomPanBehavior reset()
**Problem**: `reset()` can't be called on a `ZoomPanBehavior` created inline in `build()`

**Solution**: Create `ZoomPanBehavior` as a `late final` field in State and pass it to both `SfCartesianChart.zoomPanBehavior` and the reset button.

### 5. Stock vs Crypto Candle Loading
**Problem**: Crypto timeframes (1h) crash for stocks; stocks need different API

**Solution**: Check `stock.isCrypto` in `_loadData()`. Crypto → `BinanceCandleService`. Stocks → `AlphaVantageCandleService` with Yahoo fallback. Default timeframe: crypto=`1h`, stocks=`1D`.

### 6. APIConfig isConfigured always false
**Problem**: `isConfigured` compares key against itself (placeholder string)

**Solution**: Replace placeholder string in `api_config.dart` with your actual key, or configure via `dart-define` and update `isConfigured` logic.
