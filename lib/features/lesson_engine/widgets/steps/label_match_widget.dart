import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/lesson_step.dart';
import '../../engine/lesson_engine.dart';

/// ST-5: Tap a label chip, then tap a target slot to assign it.
/// Continue unlocks when all items are correctly matched.
class LabelMatchWidget extends StatefulWidget {
  final LabelMatchStep step;
  final LessonEngine engine;

  const LabelMatchWidget({super.key, required this.step, required this.engine});

  @override
  State<LabelMatchWidget> createState() => _LabelMatchWidgetState();
}

class _LabelMatchWidgetState extends State<LabelMatchWidget> {
  String? _selectedItemId;

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    final engine = widget.engine;

    return AnimatedBuilder(
      animation: engine,
      builder: (context, _) {
        final matches = engine.labelMatches;
        final complete = engine.labelMatchComplete;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Instruction
              Text(
                step.instruction,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              if (step.backgroundDescription.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  step.backgroundDescription,
                  style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 14, height: 1.5),
                ),
              ],
              const SizedBox(height: 24),

              // Diagram: target slots
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF111925),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: complete
                        ? const Color(0xFF1DE9B6).withValues(alpha: 0.4)
                        : const Color(0xFF12A28C).withValues(alpha: 0.15),
                  ),
                ),
                child: Column(
                  children: step.targets.map((target) {
                    final assignedItemId = matches.entries
                        .where((e) => e.value == target.id)
                        .map((e) => e.key)
                        .firstOrNull;
                    final assignedItem = assignedItemId != null
                        ? step.items.where((i) => i.id == assignedItemId).firstOrNull
                        : null;
                    final isCorrect = step.correctMapping[assignedItemId] == target.id;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: GestureDetector(
                        onTap: () {
                          if (complete) return;
                          if (_selectedItemId != null) {
                            // Assign selected item to this target
                            engine.setLabelMatch(_selectedItemId!, target.id);
                            if (engine.labelMatchComplete) HapticFeedback.lightImpact();
                            setState(() => _selectedItemId = null);
                          } else if (assignedItemId != null) {
                            // Clear this target's assignment
                            engine.clearLabelMatch(assignedItemId);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: assignedItem != null
                                ? (isCorrect
                                    ? const Color(0xFF1DE9B6).withValues(alpha: 0.1)
                                    : const Color(0xFFEF5350).withValues(alpha: 0.08))
                                : (_selectedItemId != null
                                    ? const Color(0xFF12A28C).withValues(alpha: 0.15)
                                    : const Color(0xFF1A2235)),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: assignedItem != null
                                  ? (isCorrect
                                      ? const Color(0xFF1DE9B6).withValues(alpha: 0.5)
                                      : const Color(0xFFEF5350).withValues(alpha: 0.4))
                                  : (_selectedItemId != null
                                      ? const Color(0xFF12A28C).withValues(alpha: 0.5)
                                      : const Color(0x22FFFFFF)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      target.hint,
                                      style: const TextStyle(
                                        color: Color(0x99FFFFFF),
                                        fontSize: 11,
                                      ),
                                    ),
                                    if (assignedItem != null) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        assignedItem.label,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ] else
                                      const Text(
                                        'Tap to place',
                                        style: TextStyle(color: Color(0x55FFFFFF), fontSize: 13),
                                      ),
                                  ],
                                ),
                              ),
                              if (assignedItem != null)
                                Icon(
                                  isCorrect
                                      ? Icons.check_circle_rounded
                                      : Icons.cancel_rounded,
                                  color: isCorrect
                                      ? const Color(0xFF1DE9B6)
                                      : const Color(0xFFEF5350),
                                  size: 18,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 24),

              // Label chips
              const Text(
                'LABELS',
                style: TextStyle(
                  color: Color(0x66FFFFFF),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: step.items.map((item) {
                  final isAssigned = matches.containsKey(item.id);
                  final isSelected = _selectedItemId == item.id;

                  return GestureDetector(
                    onTap: () {
                      if (complete || isAssigned) return;
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedItemId = isSelected ? null : item.id;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isAssigned
                            ? const Color(0x11FFFFFF)
                            : isSelected
                                ? const Color(0xFF12A28C).withValues(alpha: 0.25)
                                : const Color(0xFF1A2235),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isAssigned
                              ? const Color(0x22FFFFFF)
                              : isSelected
                                  ? const Color(0xFF12A28C)
                                  : const Color(0x33FFFFFF),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        item.label,
                        style: TextStyle(
                          color: isAssigned
                              ? const Color(0x44FFFFFF)
                              : isSelected
                                  ? const Color(0xFF12A28C)
                                  : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              // Complete banner
              if (complete) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1DE9B6).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF1DE9B6).withValues(alpha: 0.35)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Color(0xFF1DE9B6), size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'All matched correctly!',
                          style: TextStyle(
                            color: Color(0xFF1DE9B6),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
