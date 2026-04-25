import '../core/enums/app_enums.dart';

class AppUser {
  final String uid;
  final String displayName;
  final String email;
  final LessonLevel skillLevel;
  final List<AssetClass> assetInterests;
  final SubscriptionTier tier;
  final DateTime createdAt;
  final int coachQueriesUsedToday;
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastActivityAt;
  final String? fcmToken;

  const AppUser({
    required this.uid,
    required this.displayName,
    required this.email,
    this.skillLevel = LessonLevel.beginner,
    this.assetInterests = const [],
    this.tier = SubscriptionTier.free,
    required this.createdAt,
    this.coachQueriesUsedToday = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.lastActivityAt,
    this.fcmToken,
  });

  AppUser copyWith({
    String? uid,
    String? displayName,
    String? email,
    LessonLevel? skillLevel,
    List<AssetClass>? assetInterests,
    SubscriptionTier? tier,
    DateTime? createdAt,
    int? coachQueriesUsedToday,
    int? currentStreak,
    int? longestStreak,
    DateTime? lastActivityAt,
    String? fcmToken,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      skillLevel: skillLevel ?? this.skillLevel,
      assetInterests: assetInterests ?? this.assetInterests,
      tier: tier ?? this.tier,
      createdAt: createdAt ?? this.createdAt,
      coachQueriesUsedToday: coachQueriesUsedToday ?? this.coachQueriesUsedToday,
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      fcmToken: fcmToken ?? this.fcmToken,
    );
  }

  factory AppUser.fromJson(Map<String, dynamic> json, {required String uid}) {
    return AppUser(
      uid: uid,
      displayName: json['displayName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      skillLevel: _parseSkillLevel(json['skillLevel'] as String?),
      assetInterests: (json['assetInterest'] as List<dynamic>?)
              ?.map((e) => _parseAssetClass(e as String))
              .toList() ??
          const [],
      tier: _parseTier(json['tier'] as String?),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      coachQueriesUsedToday: (json['coachQueriesUsedToday'] as num?)?.toInt() ?? 0,
      currentStreak: (json['currentStreak'] as num?)?.toInt() ?? 0,
      longestStreak: (json['longestStreak'] as num?)?.toInt() ?? 0,
      lastActivityAt: json['lastActivityAt'] != null
          ? DateTime.tryParse(json['lastActivityAt'] as String)
          : null,
      fcmToken: json['fcmToken'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'displayName': displayName,
      'email': email,
      'skillLevel': skillLevel.name,
      'assetInterest': assetInterests.map((e) => e.name).toList(),
      'tier': tier.name,
      'createdAt': createdAt.toIso8601String(),
      'coachQueriesUsedToday': coachQueriesUsedToday,
      'currentStreak': currentStreak,
      'longestStreak': longestStreak,
      if (lastActivityAt != null) 'lastActivityAt': lastActivityAt!.toIso8601String(),
      if (fcmToken != null) 'fcmToken': fcmToken,
    };
  }

  static LessonLevel _parseSkillLevel(String? value) {
    switch (value) {
      case 'intermediate':
        return LessonLevel.intermediate;
      case 'advanced':
        return LessonLevel.advanced;
      default:
        return LessonLevel.beginner;
    }
  }

  static AssetClass _parseAssetClass(String value) {
    switch (value) {
      case 'crypto':
        return AssetClass.crypto;
      case 'etf':
        return AssetClass.etf;
      case 'marketIndex':
        return AssetClass.marketIndex;
      default:
        return AssetClass.stock;
    }
  }

  static SubscriptionTier _parseTier(String? value) {
    switch (value) {
      case 'pro':
        return SubscriptionTier.pro;
      default:
        return SubscriptionTier.free;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppUser && runtimeType == other.runtimeType && uid == other.uid;

  @override
  int get hashCode => uid.hashCode;

  @override
  String toString() => 'AppUser(uid: $uid, email: $email)';
}
