import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/watchlist_service.dart';
import 'firebase_provider.dart';
import 'auth_provider.dart';

/// Provider for WatchlistService
final watchlistServiceProvider = Provider<WatchlistService>((ref) {
  final db = ref.watch(firebaseProvider);
  final userId = ref.watch(userIdProvider);
  return WatchlistService(db, userId: userId);
});

/// Stream provider to watch if a symbol is in the watchlist
final isInWatchlistProvider = StreamProvider.family<bool, String>((ref, symbol) {
  final service = ref.watch(watchlistServiceProvider);
  return service.watchSymbol(symbol);
});

/// Stream provider for the full set of watchlisted symbols.
/// Used by HomeScreen to reactively update its quote subscriptions.
final watchlistSymbolsProvider = StreamProvider<Set<String>>((ref) {
  final service = ref.watch(watchlistServiceProvider);
  return service.watchAllSymbols();
});
