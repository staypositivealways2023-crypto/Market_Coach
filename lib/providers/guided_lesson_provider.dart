import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/lesson_engine/models/guided_lesson.dart';
import '../features/lesson_engine/lessons/lesson_registry.dart';
import '../models/guided_lesson_progress.dart';
import 'auth_provider.dart' show currentUserProvider;

// ─── Lesson list providers ─────────────────────────────────────────────────────

/// All guided lessons grouped by level.
final guidedLessonsProvider = Provider.family<List<GuidedLesson>, String>((ref, level) {
  return switch (level.toLowerCase()) {
    'beginner' => LessonRegistry.beginner,
    'intermediate' => LessonRegistry.intermediate,
    'expert' => LessonRegistry.expert,
    _ => LessonRegistry.all,
  };
});

/// All guided lessons (flat list).
final allGuidedLessonsProvider = Provider<List<GuidedLesson>>((ref) {
  return LessonRegistry.all;
});

// ─── Progress providers ────────────────────────────────────────────────────────

/// Progress stream for a single guided lesson.
final guidedProgressProvider =
    StreamProvider.family<GuidedLessonProgress?, String>((ref, lessonId) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('guided_progress')
      .doc(lessonId)
      .snapshots()
      .map((s) => s.exists ? GuidedLessonProgress.fromMap(s.data()!) : null);
});

/// All guided progress records for the current user.
final allGuidedProgressProvider =
    StreamProvider<List<GuidedLessonProgress>>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('guided_progress')
      .snapshots()
      .map((s) =>
          s.docs.map((d) => GuidedLessonProgress.fromMap(d.data())).toList());
});

/// Set of completed lesson IDs for the current user.
final completedGuidedLessonIdsProvider = Provider<Set<String>>((ref) {
  return ref
          .watch(allGuidedProgressProvider)
          .valueOrNull
          ?.where((p) => p.completed)
          .map((p) => p.lessonId)
          .toSet() ??
      {};
});

/// Total XP earned across all completed guided lessons.
final guidedTotalXpProvider = Provider<int>((ref) {
  final list = ref.watch(allGuidedProgressProvider).valueOrNull;
  if (list == null) return 0;
  return list.where((p) => p.completed).fold<int>(0, (acc, p) => acc + p.xpEarned);
});

/// Whether a given lesson is unlocked (all prerequisites completed).
final lessonUnlockedProvider =
    Provider.family<bool, String>((ref, lessonId) {
  final lesson = LessonRegistry.byId(lessonId);
  if (lesson == null || lesson.prerequisites.isEmpty) return true;
  final completedIds = ref.watch(completedGuidedLessonIdsProvider);
  return lesson.prerequisites.every((id) => completedIds.contains(id));
});

// ─── Firestore write helper ────────────────────────────────────────────────────

/// Saves lesson completion to Firestore.
/// Call this from CompletionStepWidget or the lesson screen after the user
/// finishes the last step.
Future<void> saveGuidedLessonCompletion({
  required String uid,
  required GuidedLesson lesson,
}) async {
  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('guided_progress')
      .doc(lesson.id)
      .set({
    'lesson_id': lesson.id,
    'level': lesson.level.toLowerCase(),
    'completed': true,
    'xp_earned': lesson.xpTotal,
    'completed_at': FieldValue.serverTimestamp(),
    'last_opened_at': FieldValue.serverTimestamp(),
  });
}

/// Saves a "lesson opened" event without marking it complete.
Future<void> saveGuidedLessonOpened({
  required String uid,
  required String lessonId,
  required String level,
}) async {
  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('guided_progress')
      .doc(lessonId)
      .set(
    {
      'lesson_id': lessonId,
      'level': level.toLowerCase(),
      'last_opened_at': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );
}
