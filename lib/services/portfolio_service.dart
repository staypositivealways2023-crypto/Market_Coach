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

  /// Real-time stream of all holdings for this user.
  Stream<List<Holding>> streamHoldings() {
    return _ref.orderBy('added_at', descending: false).snapshots().map(
          (snap) => snap.docs
              .map((d) => Holding.fromMap(d.data() as Map<String, dynamic>))
              .toList(),
        );
  }

  /// Add or overwrite a position (keyed by symbol).
  Future<void> upsert(Holding holding) async {
    await _ref.doc(holding.symbol).set(holding.toMap());
  }

  /// Remove a position.
  Future<void> remove(String symbol) async {
    await _ref.doc(symbol).delete();
  }

  /// Whether the user already holds this symbol.
  Future<Holding?> getHolding(String symbol) async {
    final doc = await _ref.doc(symbol).get();
    if (!doc.exists) return null;
    return Holding.fromMap(doc.data() as Map<String, dynamic>);
  }
}
