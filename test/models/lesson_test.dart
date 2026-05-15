import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:market_coach/models/lesson.dart';

void main() {
  group('Lesson Model Tests', () {
    test('fromMap creates lesson from valid data', () {
      final data = {
        'title': 'Test Lesson',
        'subtitle': 'Test Subtitle',
        'level': 'Beginner',
        'minutes': 10,
        'body': 'Test body content',
        'published_at': Timestamp.now(),
        'type': 'educational',
      };

      final lesson = Lesson.fromMap(data, 'test-id');

      expect(lesson.id, 'test-id');
      expect(lesson.title, 'Test Lesson');
      expect(lesson.subtitle, 'Test Subtitle');
      expect(lesson.level, 'Beginner');
      expect(lesson.minutes, 10);
      expect(lesson.body, 'Test body content');
      expect(lesson.publishedAt, isNotNull);
    });

    test('fromMap handles Timestamp correctly', () {
      final timestamp = Timestamp.now();
      final data = {
        'title': 'Test',
        'subtitle': 'Test',
        'level': 'Beginner',
        'minutes': 5,
        'body': 'Body',
        'published_at': timestamp,
      };

      final lesson = Lesson.fromMap(data, 'id');

      expect(lesson.publishedAt, timestamp.toDate());
    });

    test('fromMap handles int timestamp', () {
      final milliseconds = DateTime.now().millisecondsSinceEpoch;
      final data = {
        'title': 'Test',
        'subtitle': 'Test',
        'level': 'Beginner',
        'minutes': 5,
        'body': 'Body',
        'published_at': milliseconds,
      };

      final lesson = Lesson.fromMap(data, 'id');

      expect(lesson.publishedAt, isNotNull);
      expect(lesson.publishedAt!.millisecondsSinceEpoch, milliseconds);
    });

    test('fromMap handles String timestamp', () {
      final dateString = DateTime.now().toIso8601String();
      final data = {
        'title': 'Test',
        'subtitle': 'Test',
        'level': 'Beginner',
        'minutes': 5,
        'body': 'Body',
        'published_at': dateString,
      };

      final lesson = Lesson.fromMap(data, 'id');

      expect(lesson.publishedAt, isNotNull);
    });

    test('fromMap handles null timestamp', () {
      final data = {
        'title': 'Test',
        'subtitle': 'Test',
        'level': 'Beginner',
        'minutes': 5,
        'body': 'Body',
        'published_at': null,
      };

      final lesson = Lesson.fromMap(data, 'id');

      expect(lesson.publishedAt, isNull);
    });

    test('fromMap handles missing optional fields', () {
      final data = {
        'title': 'Test',
        'subtitle': 'Test',
        'level': 'Beginner',
        'minutes': 5,
        'body': 'Body',
      };

      final lesson = Lesson.fromMap(data, 'id');

      expect(lesson.title, 'Test');
      expect(lesson.publishedAt, isNull);
    });

    test('fromMap handles missing fields with defaults', () {
      final data = <String, dynamic>{};

      final lesson = Lesson.fromMap(data, 'id');

      expect(lesson.id, 'id');
      expect(lesson.title, '');
      expect(lesson.subtitle, '');
      expect(lesson.level, '');
      expect(lesson.minutes, 0);
      expect(lesson.body, '');
    });
  });
}
