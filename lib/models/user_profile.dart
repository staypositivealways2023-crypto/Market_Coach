import 'package:cloud_firestore/cloud_firestore.dart';

/// User profile model representing user account data
class UserProfile {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final bool isAnonymous;
  final DateTime createdAt;
  final DateTime lastLoginAt;
  final DateTime? upgradedAt;

  const UserProfile({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    required this.isAnonymous,
    required this.createdAt,
    required this.lastLoginAt,
    this.upgradedAt,
  });

  /// Create UserProfile from Firestore document
  factory UserProfile.fromMap(Map<String, dynamic> map, String id) {
    return UserProfile(
      uid: map['uid'] as String? ?? id,
      email: map['email'] as String?,
      displayName: map['display_name'] as String?,
      photoUrl: map['photo_url'] as String?,
      isAnonymous: map['is_anonymous'] as bool? ?? false,
      createdAt: _parseDateTime(map['created_at']) ?? DateTime.now(),
      lastLoginAt: _parseDateTime(map['last_login_at']) ?? DateTime.now(),
      upgradedAt: _parseDateTime(map['upgraded_at']),
    );
  }

  /// Safely parse DateTime from Firestore field
  /// Handles Timestamp, int (milliseconds), and String formats
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  /// Get display name or email prefix, fallback to 'Guest'
  String get displayNameOrEmail =>
      displayName ?? email?.split('@').first ?? 'Guest';

  /// Get user initials for avatar display
  String get initials {
    if (displayName != null && displayName!.isNotEmpty) {
      final parts = displayName!.trim().split(' ');
      if (parts.length >= 2) {
        return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
      }
      return displayName!.substring(0, 2).toUpperCase();
    }
    if (email != null && email!.isNotEmpty) {
      return email!.substring(0, 2).toUpperCase();
    }
    return 'G';
  }
}
