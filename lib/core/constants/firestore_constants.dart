class FirestoreConstants {
  FirestoreConstants._();

  // Top-level collections
  static const String users = 'users';
  static const String lessons = 'lessons';

  // Sub-collections under users/{uid}
  static const String watchlist = 'watchlist';
  static const String progress = 'progress';
  static const String trades = 'trades';
  static const String alerts = 'alerts';

  // User document fields
  static const String displayName = 'displayName';
  static const String email = 'email';
  static const String skillLevel = 'skillLevel';
  static const String assetInterest = 'assetInterest';
  static const String tier = 'tier';
  static const String createdAt = 'createdAt';
  static const String coachQueriesUsedToday = 'coachQueriesUsedToday';
  static const String coachQueriesResetAt = 'coachQueriesResetAt';
  static const String currentStreak = 'currentStreak';
  static const String longestStreak = 'longestStreak';
  static const String lastActivityAt = 'lastActivityAt';
  static const String fcmToken = 'fcmToken';
}
