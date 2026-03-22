import '../models/guided_lesson.dart';
import 'rsi_lesson.dart';
import 'candlestick_lesson.dart';
import 'support_resistance_lesson.dart';
import 'risk_basics_lesson.dart';
import 'macd_lesson.dart';
import 'risk_reward_lesson.dart';

// ─── LessonRegistry ───────────────────────────────────────────────────────────
// Central registry for all guided lessons.
// Lessons are grouped by level and follow the prerequisite chain defined in
// the MarketCoach curriculum plan.

class LessonRegistry {
  LessonRegistry._();

  static final List<GuidedLesson> beginner = [
    candlestickLesson,        // B-01
    rsiLesson,                // B-08 (existing)
    supportResistanceLesson,  // B-04
    riskBasicsLesson,         // B-11
  ];

  static final List<GuidedLesson> intermediate = [
    macdLesson,          // I-02
    riskRewardLesson,    // I-12
  ];

  static final List<GuidedLesson> expert = [];

  static List<GuidedLesson> get all => [
        ...beginner,
        ...intermediate,
        ...expert,
      ];

  static GuidedLesson? byId(String id) {
    try {
      return all.firstWhere((l) => l.id == id);
    } catch (_) {
      return null;
    }
  }
}
