import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:market_coach/models/lesson_progress.dart';

void main() {
  group('LessonProgress Model Tests', () {
    test('fromMap creates progress from valid data', () {
      final data = {
        'lesson_id': 'lesson-1',
        'user_id': 'user-1',
        'completed': true,
        'current_screen': 5,
        'total_screens': 10,
        'completed_at': Timestamp.now(),
        'last_accessed_at': Timestamp.now(),
      };

      final progress = LessonProgress.fromMap(data, 'lesson-1');

      expect(progress.lessonId, 'lesson-1');
      expect(progress.userId, 'user-1');
      expect(progress.completed, true);
      expect(progress.currentScreen, 5);
      expect(progress.totalScreens, 10);
      expect(progress.completedAt, isNotNull);
      expect(progress.lastAccessedAt, isNotNull);
    });

    test('progressPercentage calculates correctly', () {
      final progress = LessonProgress(
        lessonId: 'test',
        userId: 'user',
        completed: false,
        currentScreen: 4,
        totalScreens: 10,
        lastAccessedAt: DateTime.now(),
      );

      expect(progress.progressPercentage, 0.5); // (4 + 1) / 10 = 0.5
    });

    test('progressPercentage handles zero total screens', () {
      final progress = LessonProgress(
        lessonId: 'test',
        userId: 'user',
        completed: false,
        currentScreen: 0,
        totalScreens: 0,
        lastAccessedAt: DateTime.now(),
      );

      expect(progress.progressPercentage, 0.0);
    });

    test('isInProgress returns true when not completed and screen > 0', () {
      final progress = LessonProgress(
        lessonId: 'test',
        userId: 'user',
        completed: false,
        currentScreen: 3,
        totalScreens: 10,
        lastAccessedAt: DateTime.now(),
      );

      expect(progress.isInProgress, true);
    });

    test('isInProgress returns false when completed', () {
      final progress = LessonProgress(
        lessonId: 'test',
        userId: 'user',
        completed: true,
        currentScreen: 10,
        totalScreens: 10,
        lastAccessedAt: DateTime.now(),
      );

      expect(progress.isInProgress, false);
    });

    test('isNotStarted returns true when screen is 0 and not completed', () {
      final progress = LessonProgress(
        lessonId: 'test',
        userId: 'user',
        completed: false,
        currentScreen: 0,
        totalScreens: 10,
        lastAccessedAt: DateTime.now(),
      );

      expect(progress.isNotStarted, true);
    });

    test('toMap converts to map correctly', () {
      final now = DateTime.now();
      final progress = LessonProgress(
        lessonId: 'lesson-1',
        userId: 'user-1',
        completed: true,
        currentScreen: 10,
        totalScreens: 10,
        completedAt: now,
        lastAccessedAt: now,
      );

      final map = progress.toMap();

      expect(map['lesson_id'], 'lesson-1');
      expect(map['user_id'], 'user-1');
      expect(map['completed'], true);
      expect(map['current_screen'], 10);
      expect(map['total_screens'], 10);
      expect(map['completed_at'], now);
      expect(map['last_accessed_at'], isA<Timestamp>());
    });

    test('copyWith creates new instance with updated values', () {
      final original = LessonProgress(
        lessonId: 'lesson-1',
        userId: 'user-1',
        completed: false,
        currentScreen: 5,
        totalScreens: 10,
        lastAccessedAt: DateTime.now(),
      );

      final updated = original.copyWith(
        currentScreen: 7,
        completed: true,
      );

      expect(updated.currentScreen, 7);
      expect(updated.completed, true);
      expect(updated.lessonId, original.lessonId);
      expect(updated.userId, original.userId);
    });
  });
}
