import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/order_book.dart';
import '../models/market_flow.dart';
import '../services/market_data_service.dart';

// Shared singleton service — avoids recreating it on every provider build.
final _marketDataSvc = MarketDataService();

// ── Order Book ─────────────────────────────────────────────────────────────────

/// Fetches the Level-2 order book for [symbol].
///
/// Crypto: real Binance L2 (20 levels). Stocks: yfinance L1 best bid/ask.
/// Refreshed by calling `ref.invalidate(orderBookProvider(symbol))`.
final orderBookProvider =
    FutureProvider.family<OrderBook?, String>((ref, symbol) {
  return _marketDataSvc.getOrderBook(symbol, levels: 10);
});

// ── Money Flow ─────────────────────────────────────────────────────────────────

/// CMF-20, institutional vs retail flow, net position, ADX, VWAP for [symbol].
/// Underlying data uses daily candles — 5-minute cache on the backend.
final moneyFlowProvider =
    FutureProvider.family<MoneyFlowData?, String>((ref, symbol) {
  return _marketDataSvc.getMoneyFlow(symbol);
});

// ── Market Position ────────────────────────────────────────────────────────────

/// Net positioning score (-1 to +1) plus trend / smart-money signal for [symbol].
final marketPositionProvider =
    FutureProvider.family<MarketPositionData?, String>((ref, symbol) {
  return _marketDataSvc.getMarketPosition(symbol);
});

// ── Options ────────────────────────────────────────────────────────────────────

/// Options chain summary for [symbol] — PCR, max pain, ATM IV, top strikes.
/// Returns [OptionsData.available] == false for crypto / unsupported symbols.
final optionsProvider =
    FutureProvider.family<OptionsData?, String>((ref, symbol) {
  return _marketDataSvc.getOptions(symbol);
});

// ── Price Stream ───────────────────────────────────────────────────────────────

/// Live WebSocket price ticks for [symbol].
///
/// - Crypto : real-time Binance miniTicker (sub-second updates)
/// - Stocks : yfinance polling every 5 s
///
/// The stream closes automatically when the last listener cancels.
/// Use `ref.watch(priceStreamProvider(symbol))` inside a ConsumerWidget;
/// use `ref.listen(priceStreamProvider(symbol), ...)` inside ConsumerState
/// to imperatively update local state.
final priceStreamProvider =
    StreamProvider.family<PriceTick, String>((ref, symbol) {
  return _marketDataSvc.streamPrice(symbol);
});
