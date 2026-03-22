import 'lesson_step.dart';

class GuidedLesson {
  final String id;
  final String title;
  final String subtitle;
  final String topic;
  final String level; // 'Beginner' | 'Intermediate' | 'Expert'
  final int estimatedMinutes;
  final List<LessonStep> steps;
  final int xpTotal;
  final List<String> prerequisites; // lesson IDs that must be completed first

  const GuidedLesson({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.topic,
    required this.level,
    required this.estimatedMinutes,
    required this.steps,
    this.xpTotal = 50,
    this.prerequisites = const [],
  });

  int get totalSteps => steps.length;
}
