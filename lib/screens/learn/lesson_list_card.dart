import 'package:flutter/material.dart';
import '../../models/lesson.dart';
import '../../models/lesson_progress.dart';
import '../../utils/auth_helper.dart';
import 'learn_constants.dart';

/// Clean, consistent lesson card for the Firestore-backed lesson list.
/// Layout: [icon] [title + subtitle + meta row] [trailing state]
class LessonListCard extends StatelessWidget {
  final Lesson lesson;
  final LessonProgress? progress;
  final VoidCallback onTap;

  const LessonListCard({
    super.key,
    required this.lesson,
    required this.onTap,
    this.progress,
  });

  Color get _levelColor => switch (lesson.level.toLowerCase()) {
        'intermediate' => kLearnIntermediateColor,
        'advanced' => kLearnExpertColor,
        _ => kLearnBeginnerColor,
      };

  IconData get _levelIcon => switch (lesson.level.toLowerCase()) {
        'intermediate' => Icons.trending_up_rounded,
        'advanced' => Icons.military_tech_rounded,
        _ => Icons.school_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kLearnCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kLearnBorder),
        ),
        child: Row(
          children: [
            // ── Left icon ─────────────────────────────────────────────
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _levelColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_levelIcon, color: _levelColor, size: 22),
            ),
            const SizedBox(width: 12),

            // ── Center text ───────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson.title,
                    style: const TextStyle(
                      color: kLearnTextPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    lesson.subtitle,
                    style: const TextStyle(
                      color: kLearnTextSecondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // Meta row
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 11,
                        color: kLearnTextSecondary.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${lesson.minutes} min',
                        style: TextStyle(
                          color: kLearnTextSecondary.withValues(alpha: 0.8),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _dot,
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _levelColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          lesson.level,
                          style: TextStyle(
                            color: _levelColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (progress != null && progress!.isInProgress) ...[
                        const SizedBox(width: 8),
                        _dot,
                        const SizedBox(width: 8),
                        Text(
                          '${(progress!.progressPercentage * 100).toInt()}%',
                          style: const TextStyle(
                            color: kLearnAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // ── Trailing state ────────────────────────────────────────
            _buildTrailing(),
          ],
        ),
      ),
    );
  }

  Widget get _dot => Container(
        width: 2,
        height: 2,
        decoration: BoxDecoration(
          color: kLearnTextSecondary.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
      );

  Widget _buildTrailing() {
    if (progress?.completed == true) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: kLearnSuccess.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded, size: 14, color: kLearnSuccess),
      );
    }
    if (progress != null && progress!.isInProgress) {
      return SizedBox(
        width: 28,
        height: 28,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: progress!.progressPercentage,
              strokeWidth: 2,
              color: kLearnAccent,
              backgroundColor: kLearnBorder,
            ),
            Text(
              '${(progress!.progressPercentage * 100).toInt()}',
              style: const TextStyle(
                  color: kLearnAccent,
                  fontSize: 8,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }
    if (AuthHelper.requiresAuthentication(lesson.level) &&
        !AuthHelper.isUserAuthenticated()) {
      return const Icon(Icons.lock_rounded,
          size: 16, color: kLearnIntermediateColor);
    }
    return Icon(
      Icons.chevron_right_rounded,
      size: 18,
      color: kLearnTextSecondary.withValues(alpha: 0.35),
    );
  }
}
