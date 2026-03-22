import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/paper_account.dart';
import '../services/paper_trading_service.dart';
import 'auth_provider.dart';
import 'firebase_provider.dart';

final paperTradingServiceProvider = Provider<PaperTradingService?>((ref) {
  final userId = ref.watch(userIdProvider);
  if (userId == 'guest_user') return null;
  final db = ref.watch(firebaseProvider);
  return PaperTradingService(db, userId);
});

/// Real-time paper account stream (null = not activated yet).
final paperAccountProvider = StreamProvider<PaperAccount?>((ref) {
  final service = ref.watch(paperTradingServiceProvider);
  if (service == null) return Stream.value(null);
  return service.streamAccount();
});

/// Real-time paper holdings stream.
final paperHoldingsProvider = StreamProvider<List<PaperHolding>>((ref) {
  final service = ref.watch(paperTradingServiceProvider);
  if (service == null) return Stream.value([]);
  return service.streamHoldings();
});

/// Real-time transaction history stream.
final paperTransactionsProvider = StreamProvider<List<PaperTransaction>>((ref) {
  final service = ref.watch(paperTradingServiceProvider);
  if (service == null) return Stream.value([]);
  return service.streamTransactions();
});
