import 'dart:convert';
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
  /// Returns map of symbol → quote data.
  Future<Map<String, Map<String, dynamic>>> getQuotes(List<String> symbols) async {
    if (symbols.isEmpty) return {};
    try {
      final joined = symbols.map((s) => s.toUpperCase()).join(',');
      final resp = await http
          .get(Uri.parse('$_base/api/market/quotes?symbols=$joined'))
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        return {
          for (final q in list)
            (q as Map<String, dynamic>)['symbol'] as String: q,
        };
      }
    } catch (_) {}
    return {};
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
    try {
      final resp = await http
          .get(Uri.parse('$_base/api/market/range/${symbol.toUpperCase()}'))
          .timeout(_timeout);
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
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      if (kDebugMode) debugPrint('[BackendService] analyseStock ← ${resp.statusCode}');
      if (resp.statusCode == 200) {
        return SignalAnalysis.fromJson(
            jsonDecode(resp.body) as Map<String, dynamic>);
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
  }) async {
    try {
      final body = jsonEncode({
        'symbol': symbol,
        'action': action,
        'shares': shares,
        'price': price,
        if (compositeScore != null) 'composite_score': compositeScore,
        if (trend != null) 'trend': trend,
      });
      final resp = await http
          .post(
            Uri.parse('$_base/api/trade-debrief'),
            headers: {'Content-Type': 'application/json'},
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
            headers: {'Content-Type': 'application/json'},
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
