import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/lesson_step.dart';
import '../../engine/lesson_engine.dart';

class MultipleChoiceWidget extends StatelessWidget {
  final MultipleChoiceStep step;
  final LessonEngine engine;
  final void Function(bool isCorrect)? onAnswered;

  const MultipleChoiceWidget({
    super.key,
    required this.step,
    required this.engine,
    this.onAnswered,
  });

  @override
  Widget build(BuildContext context) {
    final selected = engine.selectedAnswer;
    final answered = selected != null;
    final correct = engine.answerCorrect;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF12A28C).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: const Color(0xFF12A28C).withValues(alpha: 0.3)),
            ),
            child: const Text(
              'QUICK CHECK',
              style: TextStyle(
                color: Color(0xFF12A28C),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            step.question,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          // Options
          ...List.generate(step.options.length, (i) {
            final isSelected = selected == i;
            final isCorrect = i == step.correctIndex;

            Color borderColor = Colors.white12;
            Color bgColor = Colors.white.withValues(alpha: 0.03);
            Color textColor = Colors.white70;
            Widget? trailing;

            if (answered) {
              if (isCorrect) {
                borderColor = const Color(0xFF4CAF50);
                bgColor = const Color(0xFF4CAF50).withValues(alpha: 0.08);
                textColor = const Color(0xFF4CAF50);
                trailing = const Icon(Icons.check_circle,
                    color: Color(0xFF4CAF50), size: 20);
              } else if (isSelected) {
                borderColor = Colors.redAccent;
                bgColor = Colors.redAccent.withValues(alpha: 0.08);
                textColor = Colors.redAccent;
                trailing =
                    const Icon(Icons.cancel, color: Colors.redAccent, size: 20);
              }
            } else if (isSelected) {
              borderColor = const Color(0xFF12A28C);
              bgColor = const Color(0xFF12A28C).withValues(alpha: 0.08);
              textColor = const Color(0xFF12A28C);
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: answered
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        engine.selectAnswer(i);
                        final correct = i == step.correctIndex;
                        onAnswered?.call(correct);
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(step.options[i],
                            style: TextStyle(
                                color: textColor,
                                fontSize: 15,
                                height: 1.4)),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 10),
                        trailing,
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
          // Explanation (shown after answering)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: answered
                ? Padding(
                    key: const ValueKey('explanation'),
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: correct == true
                            ? const Color(0xFF4CAF50).withValues(alpha: 0.07)
                            : Colors.orange.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: correct == true
                                ? const Color(0xFF4CAF50).withValues(alpha: 0.25)
                                : Colors.orange.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            correct == true
                                ? Icons.lightbulb_outline
                                : Icons.info_outline,
                            color: correct == true
                                ? const Color(0xFF4CAF50)
                                : Colors.orange,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              step.explanation,
                              style: const TextStyle(
                                  color: Color(0xB3FFFFFF),
                                  fontSize: 13,
                                  height: 1.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('empty')),
          ),
        ],
      ),
    );
  }
}
