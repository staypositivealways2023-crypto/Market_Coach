import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/lesson_progress.dart';
import 'firestore_service_provider.dart';
import 'auth_provider.dart';

/// Provider for single lesson progress (real-time updates via stream)
///
/// Usage:
/// ```dart
/// final progressAsync = ref.watch(lessonProgressProvider(lessonId));
/// progressAsync.when(
///   data: (progress) => Text('Progress: ${progress?.progressPercentage}'),
///   loading: () => CircularProgressIndicator(),
///   error: (err, stack) => Text('Error: $err'),
/// );
/// ```
final lessonProgressProvider =
    StreamProvider.family<LessonProgress?, String>((ref, lessonId) {
  final service = ref.watch(firestoreServiceProvider);
  final userId = ref.watch(userIdProvider);
  return service.userProgressStream(userId).map(
        (progresses) => progresses
            .cast<LessonProgress?>()
            .firstWhere((p) => p?.lessonId == lessonId, orElse: () => null),
      );
});

/// Provider for all user progress (used in LearnScreen for filtering)
///
/// Returns a list of all lesson progress records for the current user.
/// Updates in real-time as progress changes.
final allProgressProvider = StreamProvider<List<LessonProgress>>((ref) {
  final service = ref.watch(firestoreServiceProvider);
  final userId = ref.watch(userIdProvider);
  return service.userProgressStream(userId);
});
