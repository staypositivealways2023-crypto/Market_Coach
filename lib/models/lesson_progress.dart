import 'package:cloud_firestore/cloud_firestore.dart';

/// Tracks user progress through a lesson.
///
/// Firestore schema:
/// ```
/// users/{userId}/lesson_progress/{lessonId}
///   - lesson_id: string
///   - user_id: string
///   - current_screen: int (0-indexed)
///   - total_screens: int
///   - completed: bool
///   - last_accessed_at: Timestamp
///   - completed_at: Timestamp | null
/// ```
class LessonProgress {
  final String lessonId;
  final String userId;
  final bool completed;
  final int currentScreen; // Last screen user viewed (0-indexed)
  final int totalScreens;
  final DateTime? completedAt; // When user finished lesson
  final DateTime lastAccessedAt; // Last time user opened lesson

  const LessonProgress({
    required this.lessonId,
    required this.userId,
    required this.completed,
    required this.currentScreen,
    required this.totalScreens,
    this.completedAt,
    required this.lastAccessedAt,
  });

  /// Returns progress as a percentage (0.0 to 1.0)
  double get progressPercentage =>
      totalScreens > 0 ? (currentScreen + 1) / totalScreens : 0.0;

  /// True if user has started but not completed the lesson
  bool get isInProgress => currentScreen > 0 && !completed;

  /// True if user has never opened the lesson
  bool get isNotStarted => currentScreen == 0 && !completed;

  factory LessonProgress.fromMap(Map<String, dynamic> map, String id) {
    return LessonProgress(
      lessonId: map['lesson_id'] as String? ?? id,
      userId: map['user_id'] as String? ?? '',
      completed: map['completed'] as bool? ?? false,
      currentScreen: map['current_screen'] as int? ?? 0,
      totalScreens: map['total_screens'] as int? ?? 0,
      completedAt: _parseDateTime(map['completed_at']),
      lastAccessedAt: _parseDateTime(map['last_accessed_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lesson_id': lessonId,
      'user_id': userId,
      'completed': completed,
      'current_screen': currentScreen,
      'total_screens': totalScreens,
      'completed_at': completedAt,
      'last_accessed_at': Timestamp.fromDate(lastAccessedAt),
    };
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  LessonProgress copyWith({
    String? lessonId,
    String? userId,
    bool? completed,
    int? currentScreen,
    int? totalScreens,
    DateTime? completedAt,
    DateTime? lastAccessedAt,
  }) {
    return LessonProgress(
      lessonId: lessonId ?? this.lessonId,
      userId: userId ?? this.userId,
      completed: completed ?? this.completed,
      currentScreen: currentScreen ?? this.currentScreen,
      totalScreens: totalScreens ?? this.totalScreens,
      completedAt: completedAt ?? this.completedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    );
  }
}
