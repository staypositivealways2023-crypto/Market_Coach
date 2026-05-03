class OrderBookLevel {
  final double price;
  final double? size;

  const OrderBookLevel({required this.price, this.size});

  factory OrderBookLevel.fromMap(Map<String, dynamic> m) => OrderBookLevel(
        price: (m['price'] as num).toDouble(),
        size: m['quantity'] != null
            ? (m['quantity'] as num).toDouble()
            : m['size'] != null
                ? (m['size'] as num).toDouble()
                : null,
      );
}

class OrderBook {
  final String symbol;
  final bool isCrypto;
  final double? spread;
  final double? spreadPct;
  final double? midPrice;
  final String? imbalanceSignal;
  final List<OrderBookLevel> bids;
  final List<OrderBookLevel> asks;
  final double bidTotal;
  final double askTotal;
  final double buyPressurePct;
  final int timestampMs;

  const OrderBook({
    required this.symbol,
    required this.isCrypto,
    this.spread,
    this.spreadPct,
    this.midPrice,
    this.imbalanceSignal,
    required this.bids,
    required this.asks,
    required this.bidTotal,
    required this.askTotal,
    required this.buyPressurePct,
    required this.timestampMs,
  });

  factory OrderBook.fromMap(Map<String, dynamic> m) {
    final double buyPct;
    if (m['buy_pressure_pct'] != null) {
      buyPct = (m['buy_pressure_pct'] as num).toDouble();
    } else if (m['imbalance'] != null) {
      buyPct = (m['imbalance'] as num).toDouble() * 100;
    } else {
      buyPct = 50.0;
    }
    return OrderBook(
      symbol: m['symbol'] as String,
      isCrypto: m['is_crypto'] as bool? ?? false,
      spread: m['spread'] != null ? (m['spread'] as num).toDouble() : null,
      spreadPct: m['spread_pct'] != null ? (m['spread_pct'] as num).toDouble() : null,
      midPrice: m['mid_price'] != null ? (m['mid_price'] as num).toDouble() : null,
      imbalanceSignal: m['imbalance_signal'] as String?,
      bids: (m['bids'] as List<dynamic>? ?? [])
          .map((e) => OrderBookLevel.fromMap(e as Map<String, dynamic>))
          .toList(),
      asks: (m['asks'] as List<dynamic>? ?? [])
          .map((e) => OrderBookLevel.fromMap(e as Map<String, dynamic>))
          .toList(),
      bidTotal: ((m['bid_volume'] ?? m['bid_total']) as num? ?? 0).toDouble(),
      askTotal: ((m['ask_volume'] ?? m['ask_total']) as num? ?? 0).toDouble(),
      buyPressurePct: buyPct,
      timestampMs: (m['timestamp_ms'] as num? ?? 0).toInt(),
    );
  }
}
