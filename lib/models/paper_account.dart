import 'package:cloud_firestore/cloud_firestore.dart';

// ── Paper Trading Account ─────────────────────────────────────────────────────

class PaperAccount {
  final double cashBalance;
  final bool isActive;
  final DateTime? createdAt;

  static const double startingBalance = 1_000_000.0;

  const PaperAccount({
    required this.cashBalance,
    required this.isActive,
    this.createdAt,
  });

  factory PaperAccount.fromMap(Map<String, dynamic> map) {
    return PaperAccount(
      cashBalance: (map['cash_balance'] as num).toDouble(),
      isActive: map['is_active'] as bool? ?? false,
      createdAt: _ts(map['created_at']),
    );
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }
}

// ── Paper Holding ─────────────────────────────────────────────────────────────

class PaperHolding {
  final String symbol;
  final String name;
  final double shares;
  final double avgCost; // weighted average cost per share
  final DateTime? firstPurchasedAt; // when position was first opened
  final DateTime? updatedAt;

  const PaperHolding({
    required this.symbol,
    required this.name,
    required this.shares,
    required this.avgCost,
    this.firstPurchasedAt,
    this.updatedAt,
  });

  double get totalCost => shares * avgCost;

  /// Days held since first purchase (null if unknown).
  int? get holdingDays => firstPurchasedAt != null
      ? DateTime.now().difference(firstPurchasedAt!).inDays
      : null;

  /// True if held < 1 year (short-term capital gains apply).
  bool get isShortTerm => (holdingDays ?? 0) < 365;

  /// Applicable capital gains tax rate.
  double get taxRate => isShortTerm ? 0.22 : 0.15;

  factory PaperHolding.fromMap(Map<String, dynamic> map) {
    return PaperHolding(
      symbol: map['symbol'] as String,
      name: map['name'] as String? ?? map['symbol'] as String,
      shares: (map['shares'] as num).toDouble(),
      avgCost: (map['avg_cost'] as num).toDouble(),
      firstPurchasedAt: _ts(map['first_purchased_at']),
      updatedAt: _ts(map['updated_at']),
    );
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }
}

/// Paper holding enriched with live price.
class PaperHoldingWithValue {
  final PaperHolding holding;
  final double? currentPrice;

  const PaperHoldingWithValue({required this.holding, this.currentPrice});

  String get symbol => holding.symbol;
  String get name => holding.name;
  double get shares => holding.shares;
  double get avgCost => holding.avgCost;
  double get totalCost => holding.totalCost;
  int? get holdingDays => holding.holdingDays;
  bool get isShortTerm => holding.isShortTerm;

  double? get currentValue => currentPrice != null ? shares * currentPrice! : null;
  double? get unrealizedPnl => currentValue != null ? currentValue! - totalCost : null;
  double? get unrealizedPnlPct =>
      unrealizedPnl != null && totalCost > 0 ? (unrealizedPnl! / totalCost) * 100 : null;
  bool get isPositive => (unrealizedPnl ?? 0) >= 0;

  /// Estimated tax if sold now at currentPrice (only on profit).
  double? get estimatedTax {
    final pnl = unrealizedPnl;
    if (pnl == null || pnl <= 0) return 0;
    return pnl * holding.taxRate;
  }

  /// After-tax profit if sold now.
  double? get afterTaxPnl {
    final pnl = unrealizedPnl;
    if (pnl == null) return null;
    return pnl - (estimatedTax ?? 0);
  }

  /// Profit margin = after-tax profit / current value × 100.
  double? get profitMarginPct {
    final cv = currentValue;
    final atp = afterTaxPnl;
    if (cv == null || atp == null || cv == 0) return null;
    return (atp / cv) * 100;
  }
}

// ── Paper Transaction ─────────────────────────────────────────────────────────

class PaperTransaction {
  final String id;
  final String type; // BUY | SELL
  final String symbol;
  final String name;
  final double shares;
  final double price; // execution price
  final double totalValue; // shares × price
  final double? realizedPnl; // gross P&L on SELL (before tax)
  final double? taxPaid; // capital gains tax deducted
  final double? afterTaxPnl; // realizedPnl - taxPaid
  final double? taxRate; // 0.22 or 0.15
  final int? holdingDays; // days held before selling
  final double cashAfter;
  final DateTime timestamp;

  const PaperTransaction({
    required this.id,
    required this.type,
    required this.symbol,
    required this.name,
    required this.shares,
    required this.price,
    required this.totalValue,
    this.realizedPnl,
    this.taxPaid,
    this.afterTaxPnl,
    this.taxRate,
    this.holdingDays,
    required this.cashAfter,
    required this.timestamp,
  });

  bool get isBuy => type == 'BUY';
  bool get isShortTerm => (holdingDays ?? 0) < 365;

  /// Net profit as a % of total sale value (after tax).
  double? get profitMarginPct {
    if (realizedPnl == null || totalValue == 0) return null;
    final net = afterTaxPnl ?? realizedPnl!;
    return (net / totalValue) * 100;
  }

  factory PaperTransaction.fromDoc(DocumentSnapshot doc) {
    final map = doc.data() as Map<String, dynamic>;
    return PaperTransaction(
      id: doc.id,
      type: map['type'] as String,
      symbol: map['symbol'] as String,
      name: map['name'] as String? ?? map['symbol'] as String,
      shares: (map['shares'] as num).toDouble(),
      price: (map['price'] as num).toDouble(),
      totalValue: (map['total_value'] as num).toDouble(),
      realizedPnl: (map['realized_pnl'] as num?)?.toDouble(),
      taxPaid: (map['tax_paid'] as num?)?.toDouble(),
      afterTaxPnl: (map['after_tax_pnl'] as num?)?.toDouble(),
      taxRate: (map['tax_rate'] as num?)?.toDouble(),
      holdingDays: (map['holding_days'] as num?)?.toInt(),
      cashAfter: (map['cash_after'] as num).toDouble(),
      timestamp: _ts(map['created_at']),
    );
  }

  static DateTime _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return DateTime.now();
  }
}
