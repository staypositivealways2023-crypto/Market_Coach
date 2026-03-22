import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/lesson_step.dart';
import '../../engine/lesson_engine.dart';

/// ST-4: Labelled spectrum slider. User sets a value then taps Submit.
/// Correct bracket is revealed after submission.
class RangeSliderQuizWidget extends StatelessWidget {
  final RangeSliderQuizStep step;
  final LessonEngine engine;

  const RangeSliderQuizWidget({super.key, required this.step, required this.engine});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: engine,
      builder: (context, _) {
        final submitted = engine.sliderSubmitted;
        final correct = engine.sliderCorrect;
        final value = engine.sliderValue;

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
              const SizedBox(height: 6),
              Text(
                step.hintMessage,
                style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 28),

              // Scale label
              Text(
                step.scaleLabel,
                style: const TextStyle(
                  color: Color(0xFF12A28C),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 12),

              // Zone bar + slider
              _ZoneSlider(
                step: step,
                value: value,
                submitted: submitted,
                correct: correct,
                onChanged: submitted ? null : (v) => engine.updateSlider(v),
              ),
              const SizedBox(height: 8),

              // Min/max labels
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    step.scaleMin.toStringAsFixed(0),
                    style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 11),
                  ),
                  Text(
                    step.scaleMax.toStringAsFixed(0),
                    style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Submit button (hidden after submit)
              if (!submitted)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      engine.submitSlider();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF12A28C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Submit Answer',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),

              // Result feedback
              if (submitted) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: (correct == true
                            ? const Color(0xFF1DE9B6)
                            : const Color(0xFFFFB74D))
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (correct == true
                              ? const Color(0xFF1DE9B6)
                              : const Color(0xFFFFB74D))
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        correct == true
                            ? Icons.check_circle_rounded
                            : Icons.info_outline_rounded,
                        color: correct == true
                            ? const Color(0xFF1DE9B6)
                            : const Color(0xFFFFB74D),
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          correct == true ? step.successMessage : step.successMessage,
                          style: TextStyle(
                            color: correct == true
                                ? const Color(0xFF1DE9B6)
                                : const Color(0xFFFFB74D),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
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

// ─── Zone bar with slider thumb ───────────────────────────────────────────────
class _ZoneSlider extends StatelessWidget {
  final RangeSliderQuizStep step;
  final double value;
  final bool submitted;
  final bool? correct;
  final ValueChanged<double>? onChanged;

  const _ZoneSlider({
    required this.step,
    required this.value,
    required this.submitted,
    required this.correct,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Colored zone bar
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 24,
            child: Stack(
              children: [
                // Zone segments
                Row(
                  children: step.zones.map((z) {
                    final width = (z.max - z.min) / (step.scaleMax - step.scaleMin);
                    return Expanded(
                      flex: (width * 100).round(),
                      child: Container(
                        height: 24,
                        color: z.color.withValues(alpha: 0.25),
                        alignment: Alignment.center,
                        child: Text(
                          z.label,
                          style: TextStyle(
                            color: z.color,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                // Correct zone highlight (after submit)
                if (submitted)
                  Positioned.fill(
                    child: LayoutBuilder(builder: (_, constraints) {
                      final w = constraints.maxWidth;
                      final range = step.scaleMax - step.scaleMin;
                      final left = (step.correctMin - step.scaleMin) / range * w;
                      final width = (step.correctMax - step.correctMin) / range * w;
                      return Stack(
                        children: [
                          Positioned(
                            left: left,
                            top: 0,
                            width: width,
                            bottom: 0,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1DE9B6).withValues(alpha: 0.25),
                                border: Border.all(
                                  color: const Color(0xFF1DE9B6),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
              ],
            ),
          ),
        ),
        // Flutter Slider
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            activeTrackColor: const Color(0xFF12A28C),
            inactiveTrackColor: const Color(0x33FFFFFF),
            thumbColor: submitted
                ? (correct == true ? const Color(0xFF1DE9B6) : const Color(0xFFFFB74D))
                : const Color(0xFF12A28C),
            overlayColor: const Color(0x2212A28C),
          ),
          child: Slider(
            value: value.clamp(step.scaleMin, step.scaleMax),
            min: step.scaleMin,
            max: step.scaleMax,
            onChanged: onChanged,
          ),
        ),
        // Current value indicator
        Center(
          child: Text(
            '${value.toStringAsFixed(0)} / ${step.scaleMax.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Color(0x99FFFFFF),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
