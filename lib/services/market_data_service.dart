import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/api_config.dart';
import '../models/order_book.dart';
import '../models/market_flow.dart';

/// Phase 5 — Centralized service for all real-time market data endpoints.
///
/// REST endpoints (FastAPI backend):
///   GET /api/market/orderbook/{symbol}
///   GET /api/market/moneyflow/{symbol}
///   GET /api/market/marketposition/{symbol}
///   GET /api/market/options/{symbol}
///
/// WebSocket endpoint:
///   WS /api/market/stream/{symbol}
///
/// All HTTP methods fail silently and return null — the UI degrades gracefully.
class MarketDataService {
  static final MarketDataService _instance = MarketDataService._internal();
  factory MarketDataService() => _instance;
  MarketDataService._internal();

  static String get _base => APIConfig.backendBaseUrl;
  static String get _wsBase => APIConfig.backendWsUrl;
  static const _timeout = Duration(seconds: 10);

  // ── Order Book ─────────────────────────────────────────────────────────────

  Future<OrderBook?> getOrderBook(String symbol, {int levels = 10}) async {
    final url =
        '$_base/api/market/orderbook/${symbol.toUpperCase()}?levels=$levels';
    try {
      final resp =
          await http.get(Uri.parse(url)).timeout(_timeout);
      if (resp.statusCode == 200) {
        return OrderBook.fromMap(
            jsonDecode(resp.body) as Map<String, dynamic>);
      }
      if (kDebugMode) {
        debugPrint(
            '[MarketDataService] orderbook ${resp.statusCode}: ${resp.body.substring(0, resp.body.length.clamp(0, 200))}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[MarketDataService] getOrderBook error: $e');
    }
    return null;
  }

  // ── Money Flow ─────────────────────────────────────────────────────────────

  Future<MoneyFlowData?> getMoneyFlow(String symbol) async {
    final url = '$_base/api/market/moneyflow/${symbol.toUpperCase()}';
    try {
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        return MoneyFlowData.fromMap(
            jsonDecode(resp.body) as Map<String, dynamic>);
      }
      if (kDebugMode) {
        debugPrint(
            '[MarketDataService] moneyflow ${resp.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[MarketDataService] getMoneyFlow error: $e');
    }
    return null;
  }

  // ── Market Position ────────────────────────────────────────────────────────

  Future<MarketPositionData?> getMarketPosition(String symbol) async {
    final url = '$_base/api/market/marketposition/${symbol.toUpperCase()}';
    try {
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        return MarketPositionData.fromMap(
            jsonDecode(resp.body) as Map<String, dynamic>);
      }
      if (kDebugMode) {
        debugPrint(
            '[MarketDataService] marketposition ${resp.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MarketDataService] getMarketPosition error: $e');
      }
    }
    return null;
  }

  // ── Options ────────────────────────────────────────────────────────────────

  Future<OptionsData?> getOptions(String symbol) async {
    final url = '$_base/api/market/options/${symbol.toUpperCase()}';
    try {
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        return OptionsData.fromMap(
            jsonDecode(resp.body) as Map<String, dynamic>);
      }
      if (kDebugMode) {
        debugPrint('[MarketDataService] options ${resp.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[MarketDataService] getOptions error: $e');
    }
    return null;
  }

  // ── WebSocket Price Stream ─────────────────────────────────────────────────

  /// Returns a broadcast [Stream<PriceTick>] connected to the backend WS endpoint.
  ///
  /// The stream is lazy — it only connects when listened to.
  /// Errors are swallowed; the stream simply closes.
  /// The caller is responsible for cancelling the subscription when done.
  Stream<PriceTick> streamPrice(String symbol) {
    final uri =
        Uri.parse('$_wsBase/api/market/stream/${symbol.toUpperCase()}');

    late WebSocketChannel channel;
    late StreamController<PriceTick> controller;

    controller = StreamController<PriceTick>.broadcast(
      onListen: () {
        try {
          channel = WebSocketChannel.connect(uri);
          channel.stream.listen(
            (raw) {
              try {
                final data = jsonDecode(raw as String) as Map<String, dynamic>;
                // Skip control messages (connected, pong, error)
                if (data.containsKey('price')) {
                  if (!controller.isClosed) {
                    controller.add(PriceTick.fromMap(data));
                  }
                }
              } catch (_) {}
            },
            onError: (e) {
              if (kDebugMode) {
                debugPrint('[MarketDataService] WS stream error: $e');
              }
              if (!controller.isClosed) controller.close();
            },
            onDone: () {
              if (!controller.isClosed) controller.close();
            },
          );
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[MarketDataService] WS connect error: $e');
          }
          if (!controller.isClosed) controller.close();
        }
      },
      onCancel: () {
        try {
          channel.sink.close();
        } catch (_) {}
        if (!controller.isClosed) controller.close();
      },
    );

    return controller.stream;
  }
}
