import 'package:intl/intl.dart';

enum SubscriptionTier { free, pro }

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

  bool get isPro => tier == SubscriptionTier.pro;
  bool get isAtLimit => !isPro && aiMessagesToday >= freeDailyLimit;

  factory Subscription.fromMap(Map<String, dynamic> map) {
    final tierStr = map['subscription_tier'] as String? ?? 'free';
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final savedDate = (map['ai_messages_date'] as String?) ?? '';
    // Reset count if the stored date is not today — avoids yesterday's count blocking today's messages
    final messagesCount = savedDate == today ? ((map['ai_messages_today'] as int?) ?? 0) : 0;
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
}
