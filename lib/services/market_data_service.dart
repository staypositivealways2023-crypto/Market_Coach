import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/api_config.dart';
import '../models/market_flow.dart';
import '../models/order_book.dart';
import '../utils/backend_http.dart';

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

  static String get _wsBase => APIConfig.backendWsUrl;

  // ── Order Book ─────────────────────────────────────────────────────────────

  Future<OrderBook?> getOrderBook(String symbol, {int levels = 10}) async {
    final resp = await BackendHttp.get(
      '/api/market/orderbook/${symbol.toUpperCase()}?levels=$levels',
    );
    if (resp != null && resp.statusCode == 200) {
      return OrderBook.fromMap(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    return null;
  }

  // ── Money Flow ─────────────────────────────────────────────────────────────

  Future<MoneyFlowData?> getMoneyFlow(String symbol) async {
    final resp = await BackendHttp.get(
      '/api/market/moneyflow/${symbol.toUpperCase()}',
      timeout: const Duration(seconds: 20),
    );
    if (resp != null && resp.statusCode == 200) {
      return MoneyFlowData.fromMap(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    return null;
  }

  // ── Market Position ────────────────────────────────────────────────────────

  Future<MarketPositionData?> getMarketPosition(String symbol) async {
    final resp = await BackendHttp.get(
      '/api/market/marketposition/${symbol.toUpperCase()}',
      timeout: const Duration(seconds: 20),
    );
    if (resp != null && resp.statusCode == 200) {
      return MarketPositionData.fromMap(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    return null;
  }

  // ── Options ────────────────────────────────────────────────────────────────

  Future<OptionsData?> getOptions(String symbol) async {
    final resp = await BackendHttp.get(
      '/api/market/options/${symbol.toUpperCase()}',
      timeout: const Duration(seconds: 20),
    );
    if (resp != null && resp.statusCode == 200) {
      return OptionsData.fromMap(jsonDecode(resp.body) as Map<String, dynamic>);
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
