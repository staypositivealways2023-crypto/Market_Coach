import 'package:flutter/material.dart';
import '../../models/lesson_step.dart';

class TheoryStepWidget extends StatelessWidget {
  final TheoryStep step;
  const TheoryStepWidget({super.key, required this.step});

  @override
  Widget build(BuildContext context) {
    final accent = step.accentColor ?? const Color(0xFF12A28C);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: Text(
              step.badge,
              style: TextStyle(
                color: accent,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Title
          Text(
            step.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1.2,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 20),
          // Body
          Text(
            step.body,
            style: const TextStyle(
              color: Color(0xB3FFFFFF),
              fontSize: 16,
              height: 1.65,
            ),
          ),
          if (step.callout != null) ...[
            const SizedBox(height: 24),
            _CalloutBox(text: step.callout!, color: accent),
          ],
        ],
      ),
    );
  }
}

class _CalloutBox extends StatelessWidget {
  final String text;
  final Color color;
  const _CalloutBox({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color.withValues(alpha: 0.9),
                fontSize: 14,
                height: 1.55,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
