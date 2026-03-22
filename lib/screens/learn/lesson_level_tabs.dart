import 'package:flutter/material.dart';
import 'learn_constants.dart';
import '../../features/lesson_engine/lessons/lesson_registry.dart';

/// Compact segmented level selector:
/// Beginner | Intermediate | Expert
/// Selected tab has a tinted background and colored label.
class LessonLevelTabs extends StatelessWidget {
  final LevelFilter selected;
  final ValueChanged<LevelFilter> onChanged;

  const LessonLevelTabs({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: kLearnSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kLearnBorder),
        ),
        child: Row(
          children: [
            _LevelTab(
              label: 'Beginner',
              count: LessonRegistry.beginner.length,
              color: kLearnBeginnerColor,
              isSelected: selected == LevelFilter.beginner,
              onTap: () => onChanged(LevelFilter.beginner),
            ),
            _LevelTab(
              label: 'Intermediate',
              count: LessonRegistry.intermediate.length,
              color: kLearnIntermediateColor,
              isSelected: selected == LevelFilter.intermediate,
              onTap: () => onChanged(LevelFilter.intermediate),
            ),
            _LevelTab(
              label: 'Expert',
              count: LessonRegistry.expert.length,
              color: kLearnExpertColor,
              isSelected: selected == LevelFilter.advanced,
              onTap: () => onChanged(LevelFilter.advanced),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelTab extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _LevelTab({
    required this.label,
    required this.count,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: isSelected
                ? Border.all(color: color.withValues(alpha: 0.35), width: 1)
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? color : kLearnTextSecondary,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.1,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(height: 2),
                Text(
                  '$count lessons',
                  style: TextStyle(
                    color: isSelected
                        ? color.withValues(alpha: 0.6)
                        : kLearnTextSecondary.withValues(alpha: 0.4),
                    fontSize: 9,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
