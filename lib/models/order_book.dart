class OrderBookLevel {
  final double price;
  final double? size;

  const OrderBookLevel({required this.price, this.size});

  factory OrderBookLevel.fromMap(Map<String, dynamic> m) => OrderBookLevel(
        price: (m['price'] as num).toDouble(),
        size: m['size'] != null ? (m['size'] as num).toDouble() : null,
      );
}

class OrderBook {
  final String symbol;
  final bool isCrypto;
  final double? spread;
  final double? spreadPct;
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
    required this.bids,
    required this.asks,
    required this.bidTotal,
    required this.askTotal,
    required this.buyPressurePct,
    required this.timestampMs,
  });

  factory OrderBook.fromMap(Map<String, dynamic> m) => OrderBook(
        symbol: m['symbol'] as String,
        isCrypto: m['is_crypto'] as bool? ?? false,
        spread: m['spread'] != null ? (m['spread'] as num).toDouble() : null,
        spreadPct: m['spread_pct'] != null ? (m['spread_pct'] as num).toDouble() : null,
        bids: (m['bids'] as List<dynamic>? ?? [])
            .map((e) => OrderBookLevel.fromMap(e as Map<String, dynamic>))
            .toList(),
        asks: (m['asks'] as List<dynamic>? ?? [])
            .map((e) => OrderBookLevel.fromMap(e as Map<String, dynamic>))
            .toList(),
        bidTotal: (m['bid_total'] as num? ?? 0).toDouble(),
        askTotal: (m['ask_total'] as num? ?? 0).toDouble(),
        buyPressurePct: (m['buy_pressure_pct'] as num? ?? 50).toDouble(),
        timestampMs: (m['timestamp_ms'] as num? ?? 0).toInt(),
      );
}
