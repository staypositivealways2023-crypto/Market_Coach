import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_coach/models/lesson_screen.dart';
import 'package:market_coach/widgets/lesson_screen_widget.dart';

void main() {
  group('LessonScreenWidget Tests', () {
    testWidgets('renders intro screen correctly', (tester) async {
      final screen = LessonScreen(
        id: 'screen-1',
        type: 'intro',
        order: 0,
        title: 'Welcome',
        subtitle: 'Get Started',
        content: {'icon': 'school'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonScreenWidget(screen: screen),
          ),
        ),
      );

      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.byIcon(Icons.school), findsOneWidget);
    });

    testWidgets('renders text screen correctly', (tester) async {
      final screen = LessonScreen(
        id: 'screen-2',
        type: 'text',
        order: 1,
        title: 'Lesson Title',
        content: {'body': 'This is the lesson content.'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonScreenWidget(screen: screen),
          ),
        ),
      );

      expect(find.text('Lesson Title'), findsOneWidget);
      expect(find.text('This is the lesson content.'), findsOneWidget);
    });

    testWidgets('renders bullets screen correctly', (tester) async {
      final screen = LessonScreen(
        id: 'screen-3',
        type: 'bullets',
        order: 2,
        title: 'Key Points',
        content: {
          'items': ['Point 1', 'Point 2', 'Point 3']
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonScreenWidget(screen: screen),
          ),
        ),
      );

      expect(find.text('Key Points'), findsOneWidget);
      expect(find.text('Point 1'), findsOneWidget);
      expect(find.text('Point 2'), findsOneWidget);
      expect(find.text('Point 3'), findsOneWidget);
    });

    testWidgets('renders quiz screen with options', (tester) async {
      final screen = LessonScreen(
        id: 'screen-4',
        type: 'quiz_single',
        order: 3,
        content: {
          'question': 'What is 2 + 2?',
          'options': ['2', '3', '4', '5'],
          'correctIndex': 2,
          'explanation': '2 + 2 equals 4',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonScreenWidget(screen: screen),
          ),
        ),
      );

      expect(find.text('What is 2 + 2?'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('quiz screen allows selecting answer', (tester) async {
      final screen = LessonScreen(
        id: 'screen-5',
        type: 'quiz_single',
        order: 4,
        content: {
          'question': 'What is the capital of France?',
          'options': ['London', 'Paris', 'Berlin', 'Madrid'],
          'correctIndex': 1,
          'explanation': 'Paris is the capital of France',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonScreenWidget(screen: screen),
          ),
        ),
      );

      // Tap on an option
      await tester.tap(find.text('Paris'));
      await tester.pump();

      // Check Answer button should appear
      expect(find.text('Check Answer'), findsOneWidget);

      // Tap Check Answer
      await tester.tap(find.text('Check Answer'));
      await tester.pump();

      // Explanation should appear
      expect(find.text('Paris is the capital of France'), findsOneWidget);
    });

    testWidgets('quiz screen calls onQuizAnswered callback', (tester) async {
      bool? wasCorrect;

      final screen = LessonScreen(
        id: 'screen-6',
        type: 'quiz_single',
        order: 5,
        content: {
          'question': 'Is Flutter awesome?',
          'options': ['Yes', 'No'],
          'correctIndex': 0,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonScreenWidget(
              screen: screen,
              onQuizAnswered: (isCorrect) {
                wasCorrect = isCorrect;
              },
            ),
          ),
        ),
      );

      // Select correct answer
      await tester.tap(find.text('Yes'));
      await tester.pump();

      // Check answer
      await tester.tap(find.text('Check Answer'));
      await tester.pump();

      // Verify callback was called with true
      expect(wasCorrect, true);
    });

    testWidgets('renders unsupported screen type', (tester) async {
      final screen = LessonScreen(
        id: 'screen-7',
        type: 'unknown_type',
        order: 6,
        content: {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonScreenWidget(screen: screen),
          ),
        ),
      );

      expect(find.text('Unsupported screen type: unknown_type'), findsOneWidget);
    });
  });
}
