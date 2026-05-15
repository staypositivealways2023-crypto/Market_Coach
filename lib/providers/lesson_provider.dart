import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/lesson.dart';
import '../models/lesson_screen.dart';
import 'firestore_service_provider.dart';

/// Container for lesson metadata and its screens.
///
/// Used by [lessonProvider] to return complete lesson data.
class LessonWithScreens {
  final Lesson lesson;
  final List<LessonScreen> screens;

  const LessonWithScreens({
    required this.lesson,
    required this.screens,
  });
}

/// Provides complete lesson data (metadata + screens) for a given [lessonId].
///
/// Fetches lesson metadata and screens concurrently using [Future.wait] for
/// optimal performance. Results are cached automatically by Riverpod.
///
/// Throws [Exception] if:
/// - Lesson doesn't exist
/// - No screens found for the lesson
/// - Firestore fetch operation fails
///
/// Usage:
/// ```dart
/// final lessonAsync = ref.watch(lessonProvider(lessonId));
/// lessonAsync.when(
///   data: (data) => Text(data.lesson.title),
///   loading: () => CircularProgressIndicator(),
///   error: (err, stack) => Text('Error: $err'),
/// );
/// ```
final lessonProvider = FutureProvider.family<LessonWithScreens, String>((ref, lessonId) async {
  final service = ref.watch(firestoreServiceProvider);

  // Load both concurrently for optimal performance
  final results = await Future.wait([
    service.fetchLesson(lessonId),
    service.fetchLessonScreens(lessonId),
  ]);

  final lesson = results[0] as Lesson?;
  final screens = results[1] as List<LessonScreen>;

  if (lesson == null) {
    throw Exception('Lesson not found');
  }

  if (screens.isEmpty) {
    throw Exception('No screens found for this lesson');
  }

  return LessonWithScreens(lesson: lesson, screens: screens);
});
