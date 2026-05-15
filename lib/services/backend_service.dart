import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/backend_http.dart';
import '../models/fundamentals.dart';
import '../models/holding.dart';
import '../models/market_detail.dart';
import '../models/signal_analysis.dart';

/// Calls the MarketCoach Python backend (FastAPI).
/// All methods fail silently — the UI degrades gracefully if the backend is down.
class BackendService {
  static const _timeout = Duration(seconds: 10);


  // ── Auth headers ──────────────────────────────────────────────────────────
  // Used by AI-cost endpoints (analyse, portfolio/analyse, trade-debrief, chat).
  // Falls back to unauthenticated if no user is signed in (should not happen
  // in practice since auth gates the app).
  static Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {'Content-Type': 'application/json'};
    try {
      final token = await user.getIdToken();
      return {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
    } catch (_) {
      return {'Content-Type': 'application/json'};
    }
  }

  // ── Quotes ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getQuote(String symbol) async {
    try {
      final resp = await BackendHttp.get(
        '/api/market/quote/${symbol.toUpperCase()}',
        timeout: _timeout,
      );
      if (resp != null && resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Fetch quotes for multiple symbols in one call.
  /// Falls back to Finnhub (stocks) + Binance (crypto) if backend returns no data.
  Future<Map<String, Map<String, dynamic>>> getQuotes(List<String> symbols) async {
    if (symbols.isEmpty) return {};

    // ── 1. Try backend batch endpoint ────────────────────────────────────────
    Map<String, Map<String, dynamic>> results = {};
    try {
      final joined = symbols.map((s) => s.toUpperCase()).join(',');
      final resp = await BackendHttp.get(
        '/api/market/quotes?symbols=$joined',
        timeout: _timeout,
      );
      if (resp != null && resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        results = {
          for (final q in list)
            (q as Map<String, dynamic>)['symbol'] as String: q,
        };
      }
    } catch (_) {}

    // ── 2. Direct fallback for any symbols the backend missed ─────────────────
    final missing = symbols.where((s) => !results.containsKey(s.toUpperCase())).toList();
    if (missing.isNotEmpty) {
      final direct = await _fetchDirectPrices(missing);
      results.addAll(direct);
    }

    return results;
  }

  /// Fetch prices directly from Binance REST (crypto, no key required).
  /// Used as fallback when the backend is down. Stock symbols are skipped —
  /// no client-side stock key is available; they remain empty until backend recovers.
  static bool _isCryptoSymbol(String s) {
    const cryptoBases = {
      'BTC', 'ETH', 'SOL', 'BNB', 'ADA', 'XRP', 'DOGE',
      'DOT', 'MATIC', 'AVAX', 'LINK', 'LTC', 'XLM', 'USDT'
    };
    final base = s.split('-').first.split('/').first.toUpperCase();
    return cryptoBases.contains(base) ||
        s.toUpperCase().contains('-USD') ||
        s.toUpperCase().contains('/USD');
  }

  Future<Map<String, Map<String, dynamic>>> _fetchDirectPrices(
      List<String> symbols) async {
    final prices = <String, Map<String, dynamic>>{};
    final crypto = symbols.where(_isCryptoSymbol).toList();
    // Stock symbols are not fetched client-side — no key available.
    // They will remain absent from the map until the backend recovers.

    for (final sym in crypto) {
      try {
        final base = sym.split('-').first.split('/').first.toUpperCase();
        final resp = await http
            .get(Uri.parse(
                'https://api.binance.com/api/v3/ticker/price?symbol=${base}USDT'))
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final price = double.tryParse(data['price'] as String? ?? '');
          if (price != null && price > 0) {
            prices[sym.toUpperCase()] = {'symbol': sym.toUpperCase(), 'price': price};
          }
        }
      } catch (_) {}
    }

    return prices;
  }

  // ── Candles ───────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getCandles(
      String symbol, {String interval = '1d', int limit = 200}) async {
    try {
      final uri = Uri.parse(
          '/api/market/candles/${symbol.toUpperCase()}'
          '?interval=$interval&limit=$limit');
      final resp = await BackendHttp.get(
        uri.toString(),
        timeout: const Duration(seconds: 7),
      );
      if (resp != null && resp.statusCode == 200) {
        return (jsonDecode(resp.body) as List<dynamic>)
            .cast<Map<String, dynamic>>();
      }
      if (kDebugMode && resp != null) {
        debugPrint('[BackendService] getCandles ${resp.statusCode}: ${resp.body}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendService] getCandles exception: $e');
    }
    return [];
  }

  // ── Market range ──────────────────────────────────────────────────────────

  Future<MarketRange?> getPriceRange(String symbol) async {
    // Range fetches quote + 365 candles in parallel on the backend.
    // yfinance fallback (when Massive fails) can be slow — use a longer timeout.
    const rangeTimeout = Duration(seconds: 25);
    try {
      final resp = await BackendHttp.get(
        '/api/market/range/${symbol.toUpperCase()}',
        timeout: rangeTimeout,
      );
      if (resp != null && resp.statusCode == 200) {
        return MarketRange.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  // ── News ─────────────────────────────────────────────────────────────────

  Future<List<NewsArticleItem>> getTickerNews(String symbol, {int limit = 15}) async {
    try {
      final resp = await BackendHttp.get(
        '/api/news/ticker/${symbol.toUpperCase()}?limit=$limit',
        timeout: _timeout,
      );
      if (resp != null && resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final articles = data['articles'] as List<dynamic>;
        return articles
            .map((a) => NewsArticleItem.fromJson(a as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<NewsArticleItem>> getMarketNews({int limit = 20}) async {
    try {
      final resp = await BackendHttp.get(
        '/api/news/market?limit=$limit',
        timeout: _timeout,
      );
      if (resp != null && resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final articles = data['articles'] as List<dynamic>;
        return articles
            .map((a) => NewsArticleItem.fromJson(a as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // ── Macro ─────────────────────────────────────────────────────────────────

  Future<MacroOverview?> getMacroOverview() async {
    try {
      final resp = await BackendHttp.get(
        '/api/macro/overview',
        timeout: _timeout,
      );
      if (resp != null && resp.statusCode == 200) {
        return MacroOverview.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  // ── Fundamentals ──────────────────────────────────────────────────────────

  Future<FundamentalData?> getFundamentals(String symbol) async {
    try {
      final resp = await BackendHttp.get(
        '/api/fundamentals/${symbol.toUpperCase()}',
        timeout: _timeout,
      );
      if (resp != null && resp.statusCode == 200) {
        return FundamentalData.fromJson(
            jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  // ── Earnings ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getEarnings(String symbol) async {
    try {
      final resp = await BackendHttp.get(
        '/api/earnings/${symbol.toUpperCase()}',
        timeout: _timeout,
      );
      if (resp != null && resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  // ── Signal Engine Analysis (Phase 3) ─────────────────────────────────────

  /// Calls POST /api/analyse/{symbol} — runs the full 5-layer signal engine
  /// and returns composite score, signal label, candlestick pattern, and
  /// Claude's narrative.  Returns null if backend is unreachable.
  Future<SignalAnalysis?> analyseStock(
    String symbol, {
    String interval = '1d',
    String userLevel = 'beginner',
  }) async {
    final path = '/api/analyse/${symbol.toUpperCase()}'
        '?interval=$interval&user_level=$userLevel';
    final uri = path;
    try {
      if (kDebugMode) debugPrint('[BackendService] analyseStock → $uri');
      final resp = await BackendHttp.get(
        path,
        headers: await _authHeaders(),
        timeout: const Duration(seconds: 45),
      );
      if (resp == null) return null;
      if (kDebugMode) debugPrint('[BackendService] analyseStock ← ${resp.statusCode}');
      if (resp != null && resp.statusCode == 200) {
        if (kDebugMode) {
          // Log first 400 chars so we can verify field names in raw JSON
          debugPrint('[BackendService] analyseStock body: ${resp.body.substring(0, resp.body.length.clamp(0, 400))}');
        }
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        if (kDebugMode) {
          debugPrint('[BackendService] analyseStock top-level keys: ${decoded.keys.toList()}');
          final signals = decoded['signals'] as Map<String, dynamic>?;
          if (signals != null) {
            debugPrint('[BackendService] signals keys: ${signals.keys.toList()}');
            debugPrint('[BackendService] composite_score=${signals["composite_score"]} signal_label=${signals["signal_label"]}');
          }
        }
        return SignalAnalysis.fromJson(decoded);
      }
      if (kDebugMode) debugPrint('[BackendService] analyseStock error body: ${resp.body.substring(0, resp.body.length.clamp(0, 300))}');
    } catch (e, st) {
      if (kDebugMode) debugPrint('[BackendService] analyseStock exception: $e\n$st');
    }
    return null;
  }

  // ── Structured AI Analysis ────────────────────────────────────────────────

  /// Returns `{'data': Map}` on success or `{'error': String, 'status': int}`
  /// on failure so callers can surface the actual backend reason to the user.
  Future<Map<String, dynamic>?> getStructuredAnalysis(String symbol) async {
    final resp = await BackendHttp.get(
      '/api/structured/${symbol.toUpperCase()}',
      timeout: const Duration(seconds: 60),
    );
    if (resp == null) return {'error': 'Backend unreachable', 'status': 0};
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    // Preserve backend error detail so the UI can show a meaningful message.
    String detail = 'AI analysis unavailable (HTTP ${resp.statusCode})';
    try {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (body['detail'] != null) detail = body['detail'].toString();
    } catch (_) {
      if (resp.body.isNotEmpty) detail = resp.body.substring(0, resp.body.length.clamp(0, 200));
    }
    return {'error': detail, 'status': resp.statusCode};
  }

  // ── Phase 4: Probabilistic Engine ─────────────────────────────────────────

  /// GET /api/probabilistic/{symbol}
  /// Returns Monte Carlo percentile fan, VaR/CVaR, black-swan flag,
  /// Bayesian posterior target, macro regime, and Reddit sentiment.
  /// Cached 30 min server-side.
  Future<Map<String, dynamic>?> getProbabilistic(String symbol) async {
    try {
      final resp = await BackendHttp.get(
        '/api/probabilistic/${symbol.toUpperCase()}',
        timeout: const Duration(seconds: 45),
      );
      if (resp != null && resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendService] getProbabilistic error: $e');
    }
    return null;
  }

  // ── Trade Debrief ─────────────────────────────────────────────────────────

  /// POST /api/trade-debrief — server-side Claude call for trade debrief.
  /// Returns the debrief text, or null if the backend is unreachable.
  Future<String?> getTradeDebrief({
    required String symbol,
    required String action,
    required double shares,
    required double price,
    double? compositeScore,
    String? trend,
    double? rsiValue,
    String? rsiSignal,
    String? macdSignal,
    String? patternName,
    String? emaStack,
  }) async {
    try {
      final body = jsonEncode({
        'symbol': symbol,
        'action': action,
        'shares': shares,
        'price': price,
        'composite_score': compositeScore,
        'trend': trend,
        'rsi_value': rsiValue,
        'rsi_signal': rsiSignal,
        'macd_signal': macdSignal,
        'pattern_name': patternName,
        'ema_stack': emaStack,
      }..removeWhere((_, v) => v == null));
      final resp = await BackendHttp.post(
        '/api/trade-debrief',
        headers: await _authHeaders(),
        body: body,
        timeout: const Duration(seconds: 30),
      );
      if (resp != null && resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return data['text'] as String?;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendService] getTradeDebrief error: $e');
    }
    return null;
  }

  // ── Phase 5: Real Data Endpoints ─────────────────────────────────────────

  /// GET /api/market/indices?category=all|stock|crypto
  Future<List<Map<String, dynamic>>> getIndices({String category = 'all'}) async {
    try {
      final resp = await BackendHttp.get(
        '/api/market/indices?category=$category',
        timeout: _timeout,
      );
      if (resp != null && resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendService] getIndices error: $e');
    }
    return [];
  }

  /// GET /api/market/heatmap — sector performance
  Future<List<Map<String, dynamic>>> getSectorHeatmap() async {
    try {
      final resp = await BackendHttp.get(
        '/api/market/heatmap',
        timeout: _timeout,
      );
      if (resp != null && resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendService] getSectorHeatmap error: $e');
    }
    return [];
  }

  /// GET /api/market/economic-calendar
  Future<List<Map<String, dynamic>>> getEconomicCalendar({int daysAhead = 14}) async {
    try {
      final resp = await BackendHttp.get(
        '/api/market/economic-calendar?days_ahead=$daysAhead',
        timeout: _timeout,
      );
      if (resp != null && resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = body['events'] as List<dynamic>;
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendService] getEconomicCalendar error: $e');
    }
    return [];
  }

  /// GET /api/market/screener — top movers
  Future<List<Map<String, dynamic>>> getTopMovers({
    String assetType = 'all',
    int limit = 20,
  }) async {
    try {
      final resp = await BackendHttp.get(
        '/api/market/screener?asset_type=$assetType&limit=$limit',
        timeout: _timeout,
      );
      if (resp != null && resp.statusCode == 200) {
        return _parseScreenerResponse(resp.body);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendService] getTopMovers error: $e');
    }
    return [];
  }


  // ── Phase 5: Screener + Earnings Intelligence ───────────────────────────

  // ── Safe screener response parser ────────────────────────────────────────
  // Backend returns {"count":N,"results":[...]} but older cached payloads or
  // error paths could return a bare list.  This helper handles both.
  static List<Map<String, dynamic>> _parseScreenerResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final raw = decoded['results'];
        if (raw is List) {
          return raw.whereType<Map<String, dynamic>>().toList();
        }
        return [];
      }
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendService] _parseScreenerResponse error: $e');
    }
    return [];
  }

  /// GET /api/market/screener — multi-factor screener.
  Future<List<Map<String, dynamic>>> getScreenerResults({
    String assetType = 'all',
    String? sector,
    String? signal,
    double? minChange,
    double? maxChange,
    double? minVolume,
    String sortBy = 'change_percent',
    int limit = 25,
  }) async {
    try {
      final params = <String, String>{
        'asset_type': assetType,
        'sort_by': sortBy,
        'limit': '$limit',
        if (sector != null) 'sector': sector,
        if (signal != null) 'signal': signal,
        if (minChange != null) 'min_change': '$minChange',
        if (maxChange != null) 'max_change': '$maxChange',
        if (minVolume != null) 'min_volume': '$minVolume',
      };
      final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
      final resp = await BackendHttp.get(
        '/api/market/screener?$query',
        timeout: const Duration(seconds: 30),
      );
      if (resp != null && resp.statusCode == 200) {
        return _parseScreenerResponse(resp.body);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendService] getScreenerResults error: $e');
    }
    return [];
  }

  /// GET /api/earnings/calendar — upcoming earnings grouped by date.
  Future<Map<String, dynamic>?> getEarningsCalendar({int daysAhead = 30}) async {
    try {
      final resp = await BackendHttp.get(
        '/api/earnings/calendar?days_ahead=$daysAhead',
        timeout: const Duration(seconds: 30),
      );
      if (resp != null && resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendService] getEarningsCalendar error: $e');
    }
    return null;
  }

  /// GET /api/earnings/pre-prediction/{symbol} — Claude BULLISH/BEARISH/NEUTRAL verdict.
  Future<Map<String, dynamic>?> getPreEarningsPrediction(String symbol) async {
    try {
      final resp = await BackendHttp.get(
        '/api/earnings/pre-prediction/${symbol.toUpperCase()}',
        timeout: const Duration(seconds: 20),
      );
      if (resp != null && resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendService] getPreEarningsPrediction error: $e');
    }
    return null;
  }

  /// GET /api/earnings/post-analysis/{symbol} — EPS beat/miss + Claude analysis.
  Future<Map<String, dynamic>?> getPostEarningsAnalysis(String symbol) async {
    try {
      final resp = await BackendHttp.get(
        '/api/earnings/post-analysis/${symbol.toUpperCase()}',
        timeout: const Duration(seconds: 20),
      );
      if (resp != null && resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendService] getPostEarningsAnalysis error: $e');
    }
    return null;
  }

  // ── Phase 7: Macro Dashboard + Alerts ───────────────────────────────────

  /// GET /api/market/fear-greed — composite 0-100 score with label + components.
  Future<Map<String, dynamic>?> getFearGreed() async {
    try {
      final resp = await BackendHttp.get(
        '/api/market/fear-greed',
        timeout: _timeout,
      );
      if (resp != null && resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendService] getFearGreed error: $e');
    }
    return null;
  }

  /// GET /api/macro/regime/{symbol} — classify current macro regime.
  Future<Map<String, dynamic>?> getMacroRegime(String symbol) async {
    try {
      final resp = await BackendHttp.get(
        '/api/macro/regime/${symbol.toUpperCase()}',
        headers: await _authHeaders(),
        timeout: const Duration(seconds: 20),
      );
      if (resp != null && resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendService] getMacroRegime error: $e');
    }
    return null;
  }

  /// GET /api/macro/series/{seriesKey} — FRED historical data points.
  Future<List<Map<String, dynamic>>?> getMacroSeries(
    String seriesKey, {
    int limit = 24,
  }) async {
    try {
      final resp = await BackendHttp.get(
        '/api/macro/series/$seriesKey?limit=$limit',
        timeout: _timeout,
      );
      if (resp != null && resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final data = body['data'] as List<dynamic>?;
        return data?.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendService] getMacroSeries error: $e');
    }
    return null;
  }

  /// GET /api/market/technical-alerts — RSI crosses + volume spikes.
  Future<Map<String, dynamic>> getTechnicalAlerts({String? symbols}) async {
    try {
      final query = symbols != null
          ? '?symbols=${Uri.encodeComponent(symbols)}'
          : '';
      final resp = await BackendHttp.get(
        '/api/market/technical-alerts$query',
        timeout: const Duration(seconds: 30),
      );
      if (resp != null && resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendService] getTechnicalAlerts error: $e');
    }
    return {'count': 0, 'alerts': []};
  }

  // ── Portfolio Analysis ───────────────────────────────────────────────────

  /// POST /api/portfolio/analyse — Sharpe, Sortino, correlation, rebalancing, AI insight.
  Future<Map<String, dynamic>?> analysePortfolio(List<Holding> holdings) async {
    try {
      final body = jsonEncode({
        'holdings': holdings.map((h) => {
          'symbol': h.symbol,
          'name': h.name,
          'shares': h.shares,
          'avg_cost': h.avgCost,
        }).toList(),
      });
      final resp = await BackendHttp.post(
        '/api/portfolio/analyse',
        headers: await _authHeaders(),
        body: body,
        timeout: const Duration(seconds: 45),
      );
      if (resp != null && resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendService] analysePortfolio error: $e');
    }
    return null;
  }

  /// POST /api/portfolio/backtest — yfinance historical portfolio backtest.
  Future<Map<String, dynamic>?> backtestPortfolio(
    List<Holding> holdings, {
    String period = '1y',
    double initialValue = 10000,
  }) async {
    try {
      final body = jsonEncode({
        'period': period,
        'initial_value': initialValue,
        'holdings': holdings.map((h) => {
          'symbol': h.symbol,
          'name': h.name,
          'shares': h.shares,
          'avg_cost': h.avgCost,
        }).toList(),
      });
      final resp = await BackendHttp.post(
        '/api/portfolio/backtest',
        headers: await _authHeaders(),
        body: body,
        timeout: const Duration(seconds: 45),
      );
      if (resp != null && resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendService] backtestPortfolio error: $e');
    }
    return null;
  }
}
