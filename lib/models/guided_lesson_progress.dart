import 'package:cloud_firestore/cloud_firestore.dart';

/// Tracks a user's completion state for a single guided lesson.
/// Stored at: users/{uid}/guided_progress/{lessonId}
class GuidedLessonProgress {
  final String lessonId;
  final String level; // beginner | intermediate | expert
  final bool completed;
  final int xpEarned;
  final DateTime? completedAt;
  final DateTime? lastOpenedAt;

  const GuidedLessonProgress({
    required this.lessonId,
    required this.level,
    required this.completed,
    required this.xpEarned,
    this.completedAt,
    this.lastOpenedAt,
  });

  factory GuidedLessonProgress.fromMap(Map<String, dynamic> map) {
    return GuidedLessonProgress(
      lessonId: map['lesson_id'] as String? ?? '',
      level: map['level'] as String? ?? 'beginner',
      completed: map['completed'] as bool? ?? false,
      xpEarned: map['xp_earned'] as int? ?? 0,
      completedAt: _parseTimestamp(map['completed_at']),
      lastOpenedAt: _parseTimestamp(map['last_opened_at']),
    );
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }
}
