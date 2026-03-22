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
    return Subscription(
      tier: tierStr == 'pro' ? SubscriptionTier.pro : SubscriptionTier.free,
      aiMessagesToday: (map['ai_messages_today'] as int?) ?? 0,
      aiMessagesDate: (map['ai_messages_date'] as String?) ?? '',
    );
  }

  static Subscription get defaultFree => const Subscription(
        tier: SubscriptionTier.free,
        aiMessagesToday: 0,
        aiMessagesDate: '',
      );
}
