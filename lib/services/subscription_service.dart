import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../config/api_config.dart';
import '../models/subscription.dart';

class SubscriptionService {
  final FirebaseFirestore _db;
  final String _uid;
  final String? _userEmail;

  SubscriptionService(this._db, this._uid, {String? userEmail})
      : _userEmail = userEmail;

  /// Real-time subscription stream.
  /// Admin emails bypass Firestore tier entirely.
  Stream<Subscription> streamSubscription() {
    if (APIConfig.isAdminEmail(_userEmail)) {
      return Stream.value(Subscription.admin);
    }
    return _db.collection('users').doc(_uid).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return Subscription.defaultFree;
      return Subscription.fromMap(data, userEmail: _userEmail);
    });
  }

  /// Increments today's AI message count with day-reset logic.
  Future<void> incrementMessageCount() async {
    if (APIConfig.isAdminEmail(_userEmail)) return;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final ref = _db.collection('users').doc(_uid);
    await _db.runTransaction((txn) async {
      final snap = await txn.get(ref);
      final data = snap.data() ?? {};
      final lastDate = data['ai_messages_date'] as String? ?? '';
      final count = lastDate == today
          ? ((data['ai_messages_today'] as int?) ?? 0) + 1
          : 1;
      txn.set(ref, {
        'ai_messages_today': count,
        'ai_messages_date': today,
      }, SetOptions(merge: true));
    });
  }

  /// Purchase Pro via RevenueCat.
  /// No-op on web (purchases_flutter does not support web).
  Future<void> upgradeToPro() async {
    if (kIsWeb) throw UnsupportedError('In-app purchases are not available on web.');
    try {
      final offerings = await Purchases.getOfferings();
      final package = offerings.current?.monthly ??
          offerings.current?.availablePackages.firstOrNull;
      if (package == null) throw Exception('No offering available');

      final customerInfo = await Purchases.purchasePackage(package);
      final isActive = customerInfo.entitlements.active
          .containsKey(APIConfig.revenueCatEntitlement);

      if (isActive) {
        await _db.collection('users').doc(_uid).set(
          {'subscription_tier': 'pro'},
          SetOptions(merge: true),
        );
      }
    } on PurchasesErrorCode catch (e) {
      if (e == PurchasesErrorCode.purchaseCancelledError) return;
      rethrow;
    }
  }

  /// Restore previous purchases (e.g. after reinstall).
  /// Returns false on web.
  Future<bool> restorePurchases() async {
    if (kIsWeb) return false;
    try {
      final customerInfo = await Purchases.restorePurchases();
      final isActive = customerInfo.entitlements.active
          .containsKey(APIConfig.revenueCatEntitlement);
      if (isActive) {
        await _db.collection('users').doc(_uid).set(
          {'subscription_tier': 'pro'},
          SetOptions(merge: true),
        );
      }
      return isActive;
    } catch (_) {
      return false;
    }
  }
}
