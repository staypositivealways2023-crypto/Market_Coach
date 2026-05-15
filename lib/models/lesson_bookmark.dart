import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a bookmarked lesson for a user.
///
/// Firestore schema:
/// ```
/// users/{userId}/bookmarks/{lessonId}
///   - lesson_id: string
///   - user_id: string
///   - created_at: Timestamp
/// ```
class LessonBookmark {
  final String lessonId;
  final String userId;
  final DateTime createdAt;

  const LessonBookmark({
    required this.lessonId,
    required this.userId,
    required this.createdAt,
  });

  factory LessonBookmark.fromMap(Map<String, dynamic> map, String id) {
    return LessonBookmark(
      lessonId: map['lesson_id'] as String? ?? id,
      userId: map['user_id'] as String? ?? '',
      createdAt: _parseDateTime(map['created_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lesson_id': lessonId,
      'user_id': userId,
      'created_at': Timestamp.fromDate(createdAt),
    };
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
