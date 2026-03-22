import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/paper_account.dart';

/// Manages all paper trading operations in Firestore.
///
/// Firestore layout (all under users/{uid}):
///   paper/account            — one doc: cash_balance, is_active
///   paper_holdings/{symbol}  — one doc per position
///   paper_transactions/{id}  — one doc per trade
///
/// Tax model:
///   Short-term (held < 365 days): 22% capital gains
///   Long-term  (held ≥ 365 days): 15% capital gains
///   Tax only applies to profits (losses carry no tax).
class PaperTradingService {
  final FirebaseFirestore _db;
  final String _userId;

  PaperTradingService(this._db, this._userId);

  // ── References ──────────────────────────────────────────────────────────────

  DocumentReference _accountDoc() =>
      _db.collection('users').doc(_userId).collection('paper').doc('account');

  CollectionReference _holdingsCol() =>
      _db.collection('users').doc(_userId).collection('paper_holdings');

  CollectionReference _txCol() =>
      _db.collection('users').doc(_userId).collection('paper_transactions');

  // ── Account ─────────────────────────────────────────────────────────────────

  Stream<PaperAccount?> streamAccount() {
    return _accountDoc().snapshots().map((snap) {
      if (!snap.exists) return null;
      return PaperAccount.fromMap(snap.data() as Map<String, dynamic>);
    });
  }

  /// Creates the paper trading account with $1,000,000 starting balance.
  Future<void> activate() async {
    await _accountDoc().set({
      'cash_balance': PaperAccount.startingBalance,
      'is_active': true,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  // ── Holdings ─────────────────────────────────────────────────────────────────

  Stream<List<PaperHolding>> streamHoldings() {
    return _holdingsCol().snapshots().map((snap) => snap.docs
        .map((d) => PaperHolding.fromMap(d.data() as Map<String, dynamic>))
        .where((h) => h.shares > 0)
        .toList());
  }

  Future<PaperHolding?> getHolding(String symbol) async {
    final doc = await _holdingsCol().doc(symbol.toUpperCase()).get();
    if (!doc.exists) return null;
    return PaperHolding.fromMap(doc.data() as Map<String, dynamic>);
  }

  // ── Transactions ─────────────────────────────────────────────────────────────

  Stream<List<PaperTransaction>> streamTransactions({int limit = 50}) {
    return _txCol()
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(PaperTransaction.fromDoc).toList());
  }

  // ── Trade Execution ───────────────────────────────────────────────────────────

  /// Buy [shares] of [symbol] at [price].
  /// Returns null on success, or an error message string.
  Future<String?> buy(
      String symbol, String name, double shares, double price) async {
    symbol = symbol.toUpperCase();
    final totalCost = shares * price;

    final accountSnap = await _accountDoc().get();
    if (!accountSnap.exists) return 'Paper trading account not activated.';
    final account = PaperAccount.fromMap(accountSnap.data() as Map<String, dynamic>);

    if (account.cashBalance < totalCost) {
      return 'Insufficient funds. Available: \$${account.cashBalance.toStringAsFixed(2)}, '
          'Required: \$${totalCost.toStringAsFixed(2)}';
    }

    final newCash = account.cashBalance - totalCost;

    // Read existing holding (for weighted avg cost)
    final holdingSnap = await _holdingsCol().doc(symbol).get();
    double newShares = shares;
    double newAvgCost = price;
    bool isNewPosition = !holdingSnap.exists;

    if (!isNewPosition) {
      final existing = PaperHolding.fromMap(holdingSnap.data() as Map<String, dynamic>);
      final totalShares = existing.shares + shares;
      newAvgCost = ((existing.shares * existing.avgCost) + (shares * price)) / totalShares;
      newShares = totalShares;
    }

    final batch = _db.batch();

    batch.update(_accountDoc(), {'cash_balance': newCash});

    if (isNewPosition) {
      // New position — set first_purchased_at
      batch.set(_holdingsCol().doc(symbol), {
        'symbol': symbol,
        'name': name,
        'shares': newShares,
        'avg_cost': newAvgCost,
        'first_purchased_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    } else {
      // Adding to existing position — preserve first_purchased_at
      batch.update(_holdingsCol().doc(symbol), {
        'shares': newShares,
        'avg_cost': newAvgCost,
        'updated_at': FieldValue.serverTimestamp(),
      });
    }

    batch.set(_txCol().doc(), {
      'type': 'BUY',
      'symbol': symbol,
      'name': name,
      'shares': shares,
      'price': price,
      'total_value': totalCost,
      'realized_pnl': null,
      'tax_paid': null,
      'after_tax_pnl': null,
      'tax_rate': null,
      'holding_days': null,
      'cash_after': newCash,
      'created_at': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    return null;
  }

  /// Sell [shares] of [symbol] at [price].
  /// Calculates capital gains tax (22% short-term / 15% long-term).
  /// Returns null on success, or an error message string.
  Future<String?> sell(
      String symbol, String name, double shares, double price) async {
    symbol = symbol.toUpperCase();
    final totalValue = shares * price;

    final accountSnap = await _accountDoc().get();
    if (!accountSnap.exists) return 'Paper trading account not activated.';
    final account = PaperAccount.fromMap(accountSnap.data() as Map<String, dynamic>);

    final holdingSnap = await _holdingsCol().doc(symbol).get();
    if (!holdingSnap.exists) return 'You do not hold any $symbol shares.';

    final holding = PaperHolding.fromMap(holdingSnap.data() as Map<String, dynamic>);
    if (holding.shares < shares) {
      return 'Insufficient shares. You own ${holding.shares.toStringAsFixed(4)} $symbol.';
    }

    // ── Tax calculation ──────────────────────────────────────────────────────
    final grossPnl = (price - holding.avgCost) * shares;
    final holdingDays = holding.holdingDays ?? 0;
    final taxRate = holding.taxRate; // 0.22 or 0.15
    final taxPaid = grossPnl > 0 ? grossPnl * taxRate : 0.0;
    final afterTaxPnl = grossPnl - taxPaid;

    // Cash received = sale proceeds minus tax on profit
    final newCash = account.cashBalance + totalValue - taxPaid;
    final remainingShares = holding.shares - shares;

    final batch = _db.batch();

    batch.update(_accountDoc(), {'cash_balance': newCash});

    if (remainingShares <= 0.0001) {
      batch.delete(_holdingsCol().doc(symbol));
    } else {
      batch.update(_holdingsCol().doc(symbol), {
        'shares': remainingShares,
        'updated_at': FieldValue.serverTimestamp(),
      });
    }

    batch.set(_txCol().doc(), {
      'type': 'SELL',
      'symbol': symbol,
      'name': name,
      'shares': shares,
      'price': price,
      'total_value': totalValue,
      'realized_pnl': grossPnl,
      'tax_paid': taxPaid,
      'after_tax_pnl': afterTaxPnl,
      'tax_rate': taxRate,
      'holding_days': holdingDays,
      'cash_after': newCash,
      'created_at': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    return null;
  }

  /// Reset account back to $1M and wipe all holdings/transactions.
  Future<void> resetAccount() async {
    final holdingsSnap = await _holdingsCol().get();
    final txSnap = await _txCol().get();

    final batch = _db.batch();
    for (final doc in holdingsSnap.docs) { batch.delete(doc.reference); }
    for (final doc in txSnap.docs) { batch.delete(doc.reference); }
    batch.set(_accountDoc(), {
      'cash_balance': PaperAccount.startingBalance,
      'is_active': true,
      'created_at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}
