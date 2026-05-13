import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/holding.dart';

/// Manages portfolio holdings in Firestore.
/// Collection: users/{uid}/holdings/{symbol}
class PortfolioService {
  final FirebaseFirestore _db;
  final String _userId;

  PortfolioService(this._db, this._userId);

  CollectionReference get _ref =>
      _db.collection('users').doc(_userId).collection('holdings');

  CollectionReference get _txRef =>
      _db.collection('users').doc(_userId).collection('portfolio_transactions');

  /// Real-time stream of all holdings for this user.
  Stream<List<Holding>> streamHoldings() {
    return _ref.orderBy('added_at', descending: false).snapshots().map(
          (snap) => snap.docs
              .map((d) => Holding.fromMap(d.data() as Map<String, dynamic>))
              .toList(),
        );
  }

  Stream<List<PortfolioTransaction>> streamTransactions({int limit = 50}) {
    return _txRef
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(PortfolioTransaction.fromDoc).toList())
        .handleError((_) => <PortfolioTransaction>[]);
  }

  /// Add or overwrite a position (keyed by symbol).
  Future<void> upsert(Holding holding) async {
    final symbol = holding.symbol.toUpperCase();
    final existing = await getHolding(symbol);
    await _ref.doc(symbol).set(holding.toMap());

    String type = 'BUY';
    double txShares = holding.shares;
    double? realizedPnl;
    if (existing != null) {
      final diff = holding.shares - existing.shares;
      if (diff.abs() < 0.0001 && (holding.avgCost - existing.avgCost).abs() > 0.0001) {
        type = 'ADJUST';
      } else if (diff < 0) {
        type = 'SELL';
        txShares = diff.abs();
        // realizedPnl is intentionally null here: upsert() has no execution
        // price, so computing P&L from avgCost diff would be wrong.
        // Use sell() with an explicit currentPrice for accurate P&L tracking.
      } else if (diff > 0) {
        txShares = diff;
      } else {
        type = 'ADJUST';
      }
    }

    await _logTransaction(
      type: type,
      symbol: symbol,
      name: holding.name,
      shares: txShares,
      price: holding.avgCost,
      realizedPnl: realizedPnl,
    );
  }

  /// Remove a position.
  Future<void> remove(String symbol) async {
    final existing = await getHolding(symbol);
    await _ref.doc(symbol).delete();
    if (existing != null) {
      await _logTransaction(
        type: 'REMOVE',
        symbol: existing.symbol,
        name: existing.name,
        shares: existing.shares,
        price: existing.avgCost,
      );
    }
  }

  /// Whether the user already holds this symbol.
  Future<Holding?> getHolding(String symbol) async {
    final doc = await _ref.doc(symbol).get();
    if (!doc.exists) return null;
    return Holding.fromMap(doc.data() as Map<String, dynamic>);
  }

  /// Sell [sharesToSell] shares of [symbol].
  /// - If sharesToSell >= current shares → remove the position.
  /// - Otherwise → update the position with reduced shares count.
  /// [currentPrice] is used only for optional realised P&L logging.
  Future<void> sell(String symbol, double sharesToSell, {double? price}) async {
    final existing = await getHolding(symbol);
    if (existing == null) return;
    final remaining = existing.shares - sharesToSell;
    final executionPrice = price ?? existing.avgCost;
    final realizedPnl = (executionPrice - existing.avgCost) * sharesToSell;
    if (remaining <= 0) {
      await _ref.doc(symbol).delete();
    } else {
      await _ref.doc(symbol).set(Holding(
            symbol: existing.symbol,
            name: existing.name,
            shares: remaining,
            avgCost: existing.avgCost,
            addedAt: existing.addedAt,
          ).toMap());
    }
    await _logTransaction(
      type: 'SELL',
      symbol: existing.symbol,
      name: existing.name,
      shares: sharesToSell,
      price: executionPrice,
      realizedPnl: realizedPnl,
    );
  }

  Future<void> _logTransaction({
    required String type,
    required String symbol,
    required String name,
    required double shares,
    required double price,
    double? realizedPnl,
  }) async {
    try {
      await _txRef.doc().set({
        'type': type,
        'symbol': symbol,
        'name': name,
        'shares': shares,
        'price': price,
        'total_value': shares * price,
        if (realizedPnl != null) 'realized_pnl': realizedPnl,
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Do not block portfolio updates if transaction rules are not deployed yet.
    }
  }
}
