import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/subscription.dart';

class SubscriptionService {
  final FirebaseFirestore _db;
  final String _uid;

  SubscriptionService(this._db, this._uid);

  Stream<Subscription> streamSubscription() {
    return _db.collection('users').doc(_uid).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return Subscription.defaultFree;
      return Subscription.fromMap(data);
    });
  }

  /// Increments today's AI message count with day-reset logic.
  Future<void> incrementMessageCount() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final ref = _db.collection('users').doc(_uid);
    await _db.runTransaction((txn) async {
      final snap = await txn.get(ref);
      final data = snap.data() ?? {};
      final lastDate = data['ai_messages_date'] as String? ?? '';
      final count = lastDate == today
          ? ((data['ai_messages_today'] as int?) ?? 0) + 1
          : 1;
      txn.update(ref, {
        'ai_messages_today': count,
        'ai_messages_date': today,
      });
    });
  }

  /// Sets the user's tier to pro.
  /// TODO: wire IAP before public launch.
  Future<void> upgradeToPro() async {
    await _db.collection('users').doc(_uid).update({
      'subscription_tier': 'pro',
    });
  }
}
