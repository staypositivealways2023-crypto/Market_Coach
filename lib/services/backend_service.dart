import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/fundamentals.dart';
import '../models/holding.dart';
import '../models/market_detail.dart';
import '../models/signal_analysis.dart';

/// Calls the MarketCoach Python backend (FastAPI).
/// All methods fail silently — the UI degrades gracefully if the backend is down.
class BackendService {
  static String get _base => APIConfig.backendBaseUrl;
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
      final resp = await http
          .get(Uri.parse('$_base/api/market/quote/${symbol.toUpperCase()}'))
          .timeout(_timeout);
      if (resp.statusCode == 200) {
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
      final resp = await http
          .get(Uri.parse('$_base/api/market/quotes?symbols=$joined'))
          .timeout(_timeout);
      if (resp.statusCode == 200) {
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

  /// Fetch prices directly from Finnhub (stocks) and Binance REST (crypto).
  /// Used as fallback when the backend is down or missing API keys.
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
    final stocks = symbols.where((s) => !_isCryptoSymbol(s)).toList();

    // Crypto via Binance public REST (no auth needed)
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

    // Stocks via Finnhub (free tier, 60 req/min)
    for (final sym in stocks) {
      try {
        final resp = await http
            .get(Uri.parse(
                'https://finnhub.io/api/v1/quote?symbol=${sym.toUpperCase()}'
                '&token=${APIConfig.finnhubKey}'))
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final price = (data['c'] as num?)?.toDouble();
          if (price != null && price > 0) {
            prices[sym.toUpperCase()] = {
              'symbol': sym.toUpperCase(),
              'price': price,
              'change': (data['d'] as num?)?.toDouble() ?? 0.0,
              'change_percent': (data['dp'] as num?)?.toDouble() ?? 0.0,
            };
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
          '$_base/api/market/candles/${symbol.toUpperCase()}'
          '?interval=$interval&limit=$limit');
      final resp = await http.get(uri).timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        return (jsonDecode(resp.body) as List<dynamic>)
            .cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  // ── Market range ──────────────────────────────────────────────────────────

  Future<MarketRange?> getPriceRange(String symbol) async {
    // Range fetches quote + 365 candles in parallel on the backend.
    // yfinance fallback (when Massive fails) can be slow — use a longer timeout.
    const rangeTimeout = Duration(seconds: 25);
    try {
      final resp = await http
          .get(Uri.parse('$_base/api/market/range/${symbol.toUpperCase()}'))
          .timeout(rangeTimeout);
      if (resp.statusCode == 200) {
        return MarketRange.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  // ── News ─────────────────────────────────────────────────────────────────

  Future<List<NewsArticleItem>> getTickerNews(String symbol, {int limit = 15}) async {
    try {
      final resp = await http
          .get(Uri.parse('$_base/api/news/ticker/${symbol.toUpperCase()}?limit=$limit'))
          .timeout(_timeout);
      if (resp.statusCode == 200) {
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
      final resp = await http
          .get(Uri.parse('$_base/api/news/market?limit=$limit'))
          .timeout(_timeout);
      if (resp.statusCode == 200) {
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
      final resp = await http
          .get(Uri.parse('$_base/api/macro/overview'))
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        return MacroOverview.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  // ── Fundamentals ──────────────────────────────────────────────────────────

  Future<FundamentalData?> getFundamentals(String symbol) async {
    try {
      final resp = await http
          .get(Uri.parse('$_base/api/fundamentals/${symbol.toUpperCase()}'))
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        return FundamentalData.fromJson(
            jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  // ── Earnings ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getEarnings(String symbol) async {
    try {
      final resp = await http
          .get(Uri.parse('$_base/api/earnings/${symbol.toUpperCase()}'))
          .timeout(_timeout);
      if (resp.statusCode == 200) {
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
    final uri = Uri.parse(
      '$_base/api/analyse/${symbol.toUpperCase()}'
      '?interval=$interval&user_level=$userLevel',
    );
    try {
      if (kDebugMode) debugPrint('[BackendService] analyseStock → $uri');
      final resp = await http.get(uri, headers: await _authHeaders()).timeout(const Duration(seconds: 45));
      if (kDebugMode) debugPrint('[BackendService] analyseStock ← ${resp.statusCode}');
      if (resp.statusCode == 200) {
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

  Future<Map<String, dynamic>?> getStructuredAnalysis(String symbol) async {
    try {
      final resp = await http
          .get(Uri.parse('$_base/api/analysis/structured/${symbol.toUpperCase()}'))
          .timeout(const Duration(seconds: 60));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
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
      final resp = await http
          .post(
            Uri.parse('$_base/api/trade-debrief'),
            headers: await _authHeaders(),
            body: body,
          )
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return data['text'] as String?;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendService] getTradeDebrief error: $e');
    }
    return null;
  }

  // ── Portfolio Analysis (Phase 7) ──────────────────────────────────────────

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
      final resp = await http
          .post(
            Uri.parse('$_base/api/portfolio/analyse'),
            headers: await _authHeaders(),
            body: body,
          )
          .timeout(const Duration(seconds: 45));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendService] analysePortfolio error: $e');
    }
    return null;
  }
}
