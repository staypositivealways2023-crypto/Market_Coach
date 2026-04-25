import 'package:intl/intl.dart';
import '../config/api_config.dart';

enum SubscriptionTier { free, pro, admin }

class Subscription {
  final SubscriptionTier tier;
  final int aiMessagesToday;
  final String aiMessagesDate;

  static const int freeDailyLimit = 5;

  const Subscription({
    required this.tier,
    required this.aiMessagesToday,
    required this.aiMessagesDate,
  });

  // ── Tier helpers ───────────────────────────────────────────────────────────

  /// Admin accounts get all Pro features for free.
  bool get isAdmin => tier == SubscriptionTier.admin;

  /// True for both Pro subscribers and Admin accounts.
  bool get isPro => tier == SubscriptionTier.pro || isAdmin;

  /// Free users are limited to 5 AI messages/day. Admins and Pro users are not.
  bool get isAtLimit => !isPro && aiMessagesToday >= freeDailyLimit;

  /// Whether the voice coach feature is accessible.
  bool get canUseVoice => isPro;

  /// Whether portfolio AI analysis is accessible.
  bool get canUsePortfolioAI => isPro;

  // ── Factory ────────────────────────────────────────────────────────────────

  factory Subscription.fromMap(Map<String, dynamic> map, {String? userEmail}) {
    // Admin override: check email first, no payment required
    if (APIConfig.isAdminEmail(userEmail)) {
      return const Subscription(
        tier: SubscriptionTier.admin,
        aiMessagesToday: 0,
        aiMessagesDate: '',
      );
    }

    final tierStr = map['subscription_tier'] as String? ?? 'free';
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final savedDate = (map['ai_messages_date'] as String?) ?? '';
    final messagesCount =
        savedDate == today ? ((map['ai_messages_today'] as int?) ?? 0) : 0;

    return Subscription(
      tier: tierStr == 'pro' ? SubscriptionTier.pro : SubscriptionTier.free,
      aiMessagesToday: messagesCount,
      aiMessagesDate: savedDate,
    );
  }

  static Subscription get defaultFree => const Subscription(
        tier: SubscriptionTier.free,
        aiMessagesToday: 0,
        aiMessagesDate: '',
      );

  /// Full admin subscription — all features unlocked, no limits.
  static Subscription get admin => const Subscription(
        tier: SubscriptionTier.admin,
        aiMessagesToday: 0,
        aiMessagesDate: '',
      );
}
