import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for managing user's watchlist in Firestore
class WatchlistService {
  final FirebaseFirestore _db;
  final String userId;

  WatchlistService(this._db, {required this.userId});

  String _normalizeSymbol(String symbol) => symbol.trim().toUpperCase();

  /// Check if a symbol is in the watchlist
  Future<bool> isInWatchlist(String symbol) async {
    final normalized = _normalizeSymbol(symbol);
    try {
      final doc = await _db
          .collection('users')
          .doc(userId)
          .collection('watchlist')
          .doc(normalized)
          .get();

      if (doc.exists) return true;
      if (normalized == symbol) return false;

      final legacyDoc = await _db
          .collection('users')
          .doc(userId)
          .collection('watchlist')
          .doc(symbol)
          .get();
      return legacyDoc.exists;
    } catch (e) {
      print('Error checking watchlist: $e');
      return false;
    }
  }

  /// Add a symbol to the watchlist
  Future<void> addToWatchlist(String symbol) async {
    final normalized = _normalizeSymbol(symbol);
    try {
      await _db
          .collection('users')
          .doc(userId)
          .collection('watchlist')
          .doc(normalized)
          .set({
        'symbol': normalized,
        'added_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error adding to watchlist: $e');
      rethrow;
    }
  }

  /// Remove a symbol from the watchlist
  Future<void> removeFromWatchlist(String symbol) async {
    final normalized = _normalizeSymbol(symbol);
    try {
      await _db
          .collection('users')
          .doc(userId)
          .collection('watchlist')
          .doc(normalized)
          .delete();
      if (normalized != symbol) {
        await _db
            .collection('users')
            .doc(userId)
            .collection('watchlist')
            .doc(symbol)
            .delete();
      }
    } catch (e) {
      print('Error removing from watchlist: $e');
      rethrow;
    }
  }

  /// Toggle watchlist status
  Future<bool> toggleWatchlist(String symbol) async {
    final isInList = await isInWatchlist(symbol);

    if (isInList) {
      await removeFromWatchlist(symbol);
      return false;
    } else {
      await addToWatchlist(symbol);
      return true;
    }
  }

  /// Stream to watch if a symbol is in the watchlist
  Stream<bool> watchSymbol(String symbol) {
    final normalized = _normalizeSymbol(symbol);
    return _db
        .collection('users')
        .doc(userId)
        .collection('watchlist')
        .doc(normalized)
        .snapshots()
        .map((snapshot) => snapshot.exists);
  }

  /// Stream the full set of watchlisted symbols (used by HomeScreen).
  Stream<Set<String>> watchAllSymbols() {
    return _db
        .collection('users')
        .doc(userId)
        .collection('watchlist')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => _normalizeSymbol((d.data()['symbol'] as String?) ?? d.id))
            .toSet());
  }

  /// One-shot fetch of all watchlisted symbols.
  Future<Set<String>> getAllSymbols() async {
    try {
      final snap = await _db
          .collection('users')
          .doc(userId)
          .collection('watchlist')
          .get();
      return snap.docs
          .map((d) => _normalizeSymbol((d.data()['symbol'] as String?) ?? d.id))
          .toSet();
    } catch (_) {
      return {};
    }
  }
}
