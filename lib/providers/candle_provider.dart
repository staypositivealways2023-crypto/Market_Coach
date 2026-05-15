import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/candle.dart';
import 'firebase_provider.dart';

/// Stream provider for candle data (OHLCV)
/// Usage: ref.watch(candleStreamProvider(('AAPL', 100)))
/// Auto-disposes when parameters change to ensure fresh data
final candleStreamProvider = StreamProvider.family.autoDispose<List<Candle>, ({String symbol, int limit})>((ref, params) {
  final db = ref.watch(firebaseProvider);

  return db
      .collection('market_data')
      .doc(params.symbol)
      .collection('candles')
      .orderBy('timestamp', descending: true)
      .limit(params.limit)
      .snapshots()
      .map((snapshot) {
    final candles = snapshot.docs
        .map((doc) => Candle.fromMap(doc.data()))
        .toList();

    // Reverse to get chronological order (oldest first)
    return candles.reversed.toList();
  });
});
