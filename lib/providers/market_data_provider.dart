import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/stock_summary.dart';
import '../models/indicator.dart';
import '../models/valuation.dart';
import '../services/backend_service.dart';
import 'firebase_provider.dart';
import 'auth_provider.dart';

/// Stream provider for market data of a specific symbol
/// Usage: ref.watch(marketDataStreamProvider('AAPL'))
final marketDataStreamProvider =
    StreamProvider.family<StockSummary?, String>((ref, symbol) {
  final db = ref.watch(firebaseProvider);

  return db.collection('market_data').doc(symbol).snapshots().map((snapshot) {
    if (!snapshot.exists || snapshot.data() == null) return null;
    return StockSummary.fromMap(snapshot.data()!);
  });
});

/// Stream provider for technical indicators of a specific symbol
/// Usage: ref.watch(indicatorsStreamProvider('AAPL'))
final indicatorsStreamProvider =
    StreamProvider.family<Indicator?, String>((ref, symbol) {
  final db = ref.watch(firebaseProvider);

  return db.collection('indicators').doc(symbol).snapshots().map((snapshot) {
    if (!snapshot.exists || snapshot.data() == null) return null;
    return Indicator.fromMap(snapshot.data()!);
  });
});

/// Stream provider for valuation analysis of a specific symbol
/// Usage: ref.watch(valuationStreamProvider('AAPL'))
final valuationStreamProvider =
    StreamProvider.family<Valuation?, String>((ref, symbol) {
  final db = ref.watch(firebaseProvider);

  return db.collection('valuations').doc(symbol).snapshots().map((snapshot) {
    if (!snapshot.exists || snapshot.data() == null) return null;
    return Valuation.fromMap(snapshot.data()!);
  });
});

/// Stream provider for user's watchlist (list of symbols)
final watchlistProvider = StreamProvider<List<String>>((ref) {
  final db = ref.watch(firebaseProvider);
  final userId = ref.watch(userIdProvider);

  return db
      .collection('users')
      .doc(userId)
      .collection('watchlist')
      .orderBy('added_at', descending: true)
      .snapshots()
      .map((snapshot) {
    return snapshot.docs
        .map((doc) => doc.data()['symbol'] as String?)
        .whereType<String>()
        .toList();
  });
});

/// Combined watchlist data provider
final watchlistDataProvider = StreamProvider<List<StockSummary>>((ref) {
  final watchlistAsync = ref.watch(watchlistProvider);

  return watchlistAsync.when(
    data: (symbols) {
      if (symbols.isEmpty) {
        return Stream.value(<StockSummary>[]);
      }

      final db = ref.watch(firebaseProvider);

      return db
          .collection('market_data')
          .where(FieldPath.documentId, whereIn: symbols)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs
            .map((doc) => StockSummary.fromMap(doc.data()))
            .toList();
      });
    },
    loading: () => Stream.value(<StockSummary>[]),
    error: (error, stackTrace) => Stream.value(<StockSummary>[]),
  );
});

/// Model class combining market data with indicators and valuation
class MarketDataComplete {
  final StockSummary? marketData;
  final Indicator? indicators;
  final Valuation? valuation;

  const MarketDataComplete({
    this.marketData,
    this.indicators,
    this.valuation,
  });

  bool get hasData =>
      marketData != null || indicators != null || valuation != null;
}

/// Combined provider for complete market data (market data + indicators + valuation)
final completeMarketDataProvider =
    StreamProvider.family<MarketDataComplete, String>((ref, symbol) {
  final marketDataStream = ref.watch(marketDataStreamProvider(symbol));
  final indicatorsStream = ref.watch(indicatorsStreamProvider(symbol));
  final valuationStream = ref.watch(valuationStreamProvider(symbol));

  return Stream.periodic(const Duration(milliseconds: 100)).asyncMap((_) async {
    return MarketDataComplete(
      marketData: marketDataStream.value,
      indicators: indicatorsStream.value,
      valuation: valuationStream.value,
    );
  });
});

// ── Phase 5: Real-data providers (indices, heatmap, calendar, screener) ──────

final _backendSvc = BackendService();

/// Live major indices — refreshes on invalidate
/// category: 'all' | 'stock' | 'crypto'
final indicesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, category) => _backendSvc.getIndices(category: category),
);

/// Sector heatmap — 11 SPDR ETFs by daily %
final sectorHeatmapProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) => _backendSvc.getSectorHeatmap(),
);

/// Upcoming high-impact economic events (next 14 days)
final economicCalendarProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) => _backendSvc.getEconomicCalendar(daysAhead: 14),
);

/// Top movers screener — biggest absolute daily % changes
/// assetType: 'all' | 'stock' | 'crypto'
final topMoversProvider = FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, assetType) => _backendSvc.getTopMovers(assetType: assetType, limit: 20),
);
