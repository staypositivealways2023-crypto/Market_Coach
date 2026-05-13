/// UsageAnalyticsService — Phase 8 (Task 8.4)
///
/// Logs feature-usage events to Firestore:
///   users/{uid}/usage/{autoId}
///
/// Each document contains:
///   feature   — String  e.g. 'screener', 'alerts', 'macro_dashboard'
///   tier      — String  'free' | 'pro' | 'admin'
///   timestamp — Timestamp
///   uid       — String  (for cross-collection queries)
///
/// All writes are fire-and-forget — failures are swallowed so they
/// never break the user experience.

library;

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/subscription.dart';

/// Feature name constants — use these instead of raw strings.
class UsageFeature {
  UsageFeature._();

  static const String screener         = 'screener';
  static const String alerts           = 'alerts';
  static const String macroDashboard   = 'macro_dashboard';
  static const String probabilistic    = 'probabilistic';
  static const String aiAnalysis       = 'ai_analysis';
  static const String portfolioAI      = 'portfolio_ai';
  static const String backtest         = 'backtest';
  static const String voice            = 'voice';
  static const String chat             = 'chat_message';
  static const String paperTrade       = 'paper_trade';
  static const String earnings         = 'earnings_calendar';
}

class UsageAnalyticsService {
  final FirebaseFirestore _db;
  final String _uid;
  final SubscriptionTier _tier;

  UsageAnalyticsService(this._db, this._uid, this._tier);

  /// Log that the user accessed [feature].
  /// Fire-and-forget — never throws.
  void logFeatureUsed(String feature) {
    _db
        .collection('users')
        .doc(_uid)
        .collection('usage')
        .add({
          'feature': feature,
          'tier': _tier.name, // 'free' | 'pro' | 'admin'
          'timestamp': FieldValue.serverTimestamp(),
          'uid': _uid,
        })
        .ignore(); // don't await; swallow errors silently
  }
}
