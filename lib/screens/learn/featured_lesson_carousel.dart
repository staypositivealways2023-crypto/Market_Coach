import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'learn_constants.dart';
import '../../features/lesson_engine/lessons/lesson_registry.dart';
import '../../features/lesson_engine/models/guided_lesson.dart';
import '../../features/lesson_engine/screens/guided_lesson_screen.dart';
import '../../models/guided_lesson_progress.dart';
import '../../providers/guided_lesson_provider.dart';

/// Horizontal carousel of guided (interactive) lessons.
/// Reads its own providers; level selection is passed in from the parent.
class FeaturedLessonCarousel extends ConsumerWidget {
  final LevelFilter selectedLevel;

  const FeaturedLessonCarousel({super.key, required this.selectedLevel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completedIds = ref.watch(completedGuidedLessonIdsProvider);
    final allProgressAsync = ref.watch(allGuidedProgressProvider);

    final progressMap = <String, GuidedLessonProgress>{};
    allProgressAsync.valueOrNull?.forEach((p) => progressMap[p.lessonId] = p);

    final lessons = switch (selectedLevel) {
      LevelFilter.beginner => LessonRegistry.beginner,
      LevelFilter.intermediate => LessonRegistry.intermediate,
      LevelFilter.advanced => LessonRegistry.expert,
      LevelFilter.all => LessonRegistry.all,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Text(
            'Featured',
            style: TextStyle(
              color: kLearnTextPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (lessons.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              'More lessons coming soon.',
              style: TextStyle(color: kLearnTextSecondary, fontSize: 13),
            ),
          )
        else
          SizedBox(
            height: 142,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: lessons.length,
              itemBuilder: (ctx, i) {
                final lesson = lessons[i];
                final isCompleted = completedIds.contains(lesson.id);
                final isUnlocked = lesson.prerequisites.isEmpty ||
                    lesson.prerequisites
                        .every((id) => completedIds.contains(id));
                return _FeaturedCard(
                  lesson: lesson,
                  isCompleted: isCompleted,
                  isUnlocked: isUnlocked,
                  progress: progressMap[lesson.id],
                );
              },
            ),
          ),
      ],
    );
  }
}

// ─── Individual card ───────────────────────────────────────────────────────────

class _FeaturedCard extends StatelessWidget {
  final GuidedLesson lesson;
  final bool isCompleted;
  final bool isUnlocked;
  final GuidedLessonProgress? progress;

  const _FeaturedCard({
    required this.lesson,
    required this.isCompleted,
    required this.isUnlocked,
    required this.progress,
  });

  Color get _levelColor => switch (lesson.level.toLowerCase()) {
        'intermediate' => kLearnIntermediateColor,
        'expert' => kLearnExpertColor,
        _ => kLearnBeginnerColor,
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isUnlocked
          ? () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GuidedLessonScreen(lesson: lesson),
                  fullscreenDialog: true,
                ),
              )
          : null,
      child: Container(
        width: 158,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: isUnlocked ? kLearnCard : kLearnSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isCompleted
                ? kLearnAccent.withValues(alpha: 0.35)
                : isUnlocked
                    ? _levelColor.withValues(alpha: 0.22)
                    : kLearnBorder,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Level badge + status icon
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _levelColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    lesson.level.toUpperCase(),
                    style: TextStyle(
                      color: _levelColor,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const Spacer(),
                if (isCompleted)
                  Icon(Icons.check_circle_rounded,
                      color: kLearnAccent, size: 15)
                else if (!isUnlocked)
                  Icon(Icons.lock_rounded,
                      color: kLearnTextSecondary.withValues(alpha: 0.4), size: 15)
                else
                  Container(
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: _levelColor.withValues(alpha: 0.35)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Title
            Text(
              lesson.title,
              style: TextStyle(
                color: isUnlocked
                    ? kLearnTextPrimary
                    : kLearnTextSecondary.withValues(alpha: 0.45),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            // XP + duration
            Row(
              children: [
                Text(
                  '+${lesson.xpTotal} XP',
                  style: TextStyle(
                    color: isUnlocked
                        ? _levelColor
                        : kLearnTextSecondary.withValues(alpha: 0.3),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.schedule_rounded,
                  size: 10,
                  color: kLearnTextSecondary.withValues(alpha: 0.45),
                ),
                const SizedBox(width: 2),
                Text(
                  '${lesson.estimatedMinutes}m',
                  style: TextStyle(
                    color: kLearnTextSecondary.withValues(alpha: 0.45),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
