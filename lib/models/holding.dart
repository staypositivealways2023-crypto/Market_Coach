import 'package:cloud_firestore/cloud_firestore.dart';

/// A single portfolio position stored in Firestore.
/// Path: users/{uid}/holdings/{symbol}
class Holding {
  final String symbol;
  final String name;
  final double shares;
  final double avgCost; // cost per share
  final DateTime addedAt;

  const Holding({
    required this.symbol,
    required this.name,
    required this.shares,
    required this.avgCost,
    required this.addedAt,
  });

  double get totalCost => shares * avgCost;

  Map<String, dynamic> toMap() => {
        'symbol': symbol,
        'name': name,
        'shares': shares,
        'avg_cost': avgCost,
        'added_at': Timestamp.fromDate(addedAt),
      };

  factory Holding.fromMap(Map<String, dynamic> map) {
    return Holding(
      symbol: map['symbol'] as String,
      name: map['name'] as String? ?? map['symbol'] as String,
      shares: (map['shares'] as num).toDouble(),
      avgCost: (map['avg_cost'] as num).toDouble(),
      addedAt: _parseDateTime(map['added_at']) ?? DateTime.now(),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  Holding copyWith({double? shares, double? avgCost}) => Holding(
        symbol: symbol,
        name: name,
        shares: shares ?? this.shares,
        avgCost: avgCost ?? this.avgCost,
        addedAt: addedAt,
      );
}

/// Holding enriched with live price data.
class HoldingWithValue {
  final Holding holding;
  final double? currentPrice;

  const HoldingWithValue({required this.holding, this.currentPrice});

  String get symbol => holding.symbol;
  String get name => holding.name;
  double get shares => holding.shares;
  double get avgCost => holding.avgCost;
  double get totalCost => holding.totalCost;

  double? get currentValue =>
      currentPrice != null ? shares * currentPrice! : null;
  double? get pnl => currentValue != null ? currentValue! - totalCost : null;
  double? get pnlPct =>
      pnl != null && totalCost > 0 ? (pnl! / totalCost) * 100 : null;
  bool get isPositive => (pnl ?? 0) >= 0;
}
