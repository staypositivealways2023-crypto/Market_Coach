/// Provider for UsageAnalyticsService.
/// Returns null when no user is signed in.

library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/subscription.dart';
import '../providers/auth_provider.dart';
import '../providers/firebase_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/usage_analytics_service.dart';

final usageAnalyticsProvider = Provider<UsageAnalyticsService?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;

  final db       = ref.watch(firebaseProvider);
  final tier     = ref.watch(subscriptionProvider).valueOrNull?.tier
                       ?? SubscriptionTier.free;

  return UsageAnalyticsService(db, user.uid, tier);
});
