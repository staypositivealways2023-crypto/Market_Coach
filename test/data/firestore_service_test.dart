import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:market_coach/data/firestore_service.dart';

void main() {
  group('FirestoreService Tests', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService service;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      service = FirestoreService(fakeFirestore);
    });

    test('fetchLesson returns null when lesson does not exist', () async {
      final lesson = await service.fetchLesson('non-existent');

      expect(lesson, isNull);
    });

    test('fetchLesson returns lesson when it exists', () async {
      // Add a lesson to fake Firestore
      await fakeFirestore.collection('lessons').doc('test-lesson').set({
        'title': 'Test Lesson',
        'subtitle': 'Test Subtitle',
        'level': 'Beginner',
        'minutes': 10,
        'body': 'Test body',
        'published_at': Timestamp.now(),
      });

      final lesson = await service.fetchLesson('test-lesson');

      expect(lesson, isNotNull);
      expect(lesson!.id, 'test-lesson');
      expect(lesson.title, 'Test Lesson');
      expect(lesson.level, 'Beginner');
    });

    test('fetchLessonScreens returns empty list when no screens exist', () async {
      final screens = await service.fetchLessonScreens('test-lesson');

      expect(screens, isEmpty);
    });

    test('fetchLessonScreens returns screens ordered by order field', () async {
      // Add screens in random order
      await fakeFirestore
          .collection('lessons')
          .doc('test-lesson')
          .collection('screens')
          .doc('screen-2')
          .set({'type': 'text', 'order': 2, 'title': 'Screen 2'});

      await fakeFirestore
          .collection('lessons')
          .doc('test-lesson')
          .collection('screens')
          .doc('screen-1')
          .set({'type': 'intro', 'order': 1, 'title': 'Screen 1'});

      await fakeFirestore
          .collection('lessons')
          .doc('test-lesson')
          .collection('screens')
          .doc('screen-3')
          .set({'type': 'quiz_single', 'order': 3, 'title': 'Screen 3'});

      final screens = await service.fetchLessonScreens('test-lesson');

      expect(screens, hasLength(3));
      expect(screens[0].order, 1);
      expect(screens[1].order, 2);
      expect(screens[2].order, 3);
      expect(screens[0].title, 'Screen 1');
      expect(screens[2].type, 'quiz_single');
    });

    test('updateLessonProgress creates progress document', () async {
      await service.updateLessonProgress(
        userId: 'user-1',
        lessonId: 'lesson-1',
        currentScreen: 3,
        totalScreens: 10,
        completed: false,
      );

      final doc = await fakeFirestore
          .collection('users')
          .doc('user-1')
          .collection('lesson_progress')
          .doc('lesson-1')
          .get();

      expect(doc.exists, true);
      expect(doc.data()!['current_screen'], 3);
      expect(doc.data()!['total_screens'], 10);
      expect(doc.data()!['completed'], false);
    });

    test('markLessonComplete marks lesson as completed', () async {
      await service.markLessonComplete('user-1', 'lesson-1');

      final doc = await fakeFirestore
          .collection('users')
          .doc('user-1')
          .collection('lesson_progress')
          .doc('lesson-1')
          .get();

      expect(doc.exists, true);
      expect(doc.data()!['completed'], true);
      expect(doc.data()!['completed_at'], isNotNull);
    });

    test('fetchLessonProgress returns null when not exists', () async {
      final progress = await service.fetchLessonProgress('user-1', 'lesson-1');

      expect(progress, isNull);
    });

    test('fetchLessonProgress returns progress when exists', () async {
      await fakeFirestore
          .collection('users')
          .doc('user-1')
          .collection('lesson_progress')
          .doc('lesson-1')
          .set({
        'lesson_id': 'lesson-1',
        'user_id': 'user-1',
        'current_screen': 5,
        'total_screens': 10,
        'completed': false,
        'last_accessed_at': Timestamp.now(),
      });

      final progress = await service.fetchLessonProgress('user-1', 'lesson-1');

      expect(progress, isNotNull);
      expect(progress!.lessonId, 'lesson-1');
      expect(progress.currentScreen, 5);
      expect(progress.totalScreens, 10);
    });

    test('bookmarkLesson creates bookmark', () async {
      await service.bookmarkLesson('user-1', 'lesson-1');

      final doc = await fakeFirestore
          .collection('users')
          .doc('user-1')
          .collection('bookmarks')
          .doc('lesson-1')
          .get();

      expect(doc.exists, true);
      expect(doc.data()!['lesson_id'], 'lesson-1');
    });

    test('unbookmarkLesson removes bookmark', () async {
      // First create bookmark
      await service.bookmarkLesson('user-1', 'lesson-1');

      // Then remove it
      await service.unbookmarkLesson('user-1', 'lesson-1');

      final doc = await fakeFirestore
          .collection('users')
          .doc('user-1')
          .collection('bookmarks')
          .doc('lesson-1')
          .get();

      expect(doc.exists, false);
    });

    test('isLessonBookmarked returns true when bookmarked', () async {
      await service.bookmarkLesson('user-1', 'lesson-1');

      final isBookmarked =
          await service.isLessonBookmarked('user-1', 'lesson-1');

      expect(isBookmarked, true);
    });

    test('isLessonBookmarked returns false when not bookmarked', () async {
      final isBookmarked =
          await service.isLessonBookmarked('user-1', 'lesson-1');

      expect(isBookmarked, false);
    });

    test('userProgressStream emits progress updates', () async {
      final stream = service.userProgressStream('user-1');

      // Add progress
      await fakeFirestore
          .collection('users')
          .doc('user-1')
          .collection('lesson_progress')
          .doc('lesson-1')
          .set({
        'lesson_id': 'lesson-1',
        'user_id': 'user-1',
        'current_screen': 3,
        'total_screens': 10,
        'completed': false,
        'last_accessed_at': Timestamp.now(),
      });

      await expectLater(
        stream,
        emits(predicate<List>((list) =>
            list.isNotEmpty && list.first.lessonId == 'lesson-1')),
      );
    });
  });
}
