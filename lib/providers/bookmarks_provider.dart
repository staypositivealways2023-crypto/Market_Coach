import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firestore_service_provider.dart';
import 'auth_provider.dart';

/// Provider for bookmarked lesson IDs (real-time updates via stream)
///
/// Returns a list of lesson IDs that the user has bookmarked.
/// Updates in real-time when bookmarks are added or removed.
///
/// Usage:
/// ```dart
/// final bookmarksAsync = ref.watch(bookmarksProvider);
/// final isBookmarked = bookmarksAsync.maybeWhen(
///   data: (bookmarks) => bookmarks.contains(lessonId),
///   orElse: () => false,
/// );
/// ```
final bookmarksProvider = StreamProvider<List<String>>((ref) {
  final service = ref.watch(firestoreServiceProvider);
  final userId = ref.watch(userIdProvider);
  return service.bookmarkedLessonsStream(userId);
});
