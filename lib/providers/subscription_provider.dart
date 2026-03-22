import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/subscription.dart';
import '../providers/auth_provider.dart';
import '../providers/firebase_provider.dart';
import '../services/subscription_service.dart';

final subscriptionServiceProvider = Provider<SubscriptionService?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final db = ref.watch(firebaseProvider);
  return SubscriptionService(db, user.uid);
});

final subscriptionProvider = StreamProvider<Subscription?>((ref) {
  final service = ref.watch(subscriptionServiceProvider);
  if (service == null) return Stream.value(null);
  return service.streamSubscription();
});
