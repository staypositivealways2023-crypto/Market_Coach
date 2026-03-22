import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/holding.dart';
import '../services/portfolio_service.dart';
import 'auth_provider.dart';
import 'firebase_provider.dart';

final portfolioServiceProvider = Provider<PortfolioService?>((ref) {
  final userId = ref.watch(userIdProvider);
  if (userId == 'guest_user') return null;
  final db = ref.watch(firebaseProvider);
  return PortfolioService(db, userId);
});

/// Real-time stream of the user's holdings.
final portfolioHoldingsProvider = StreamProvider<List<Holding>>((ref) {
  final service = ref.watch(portfolioServiceProvider);
  if (service == null) return Stream.value([]);
  return service.streamHoldings();
});
