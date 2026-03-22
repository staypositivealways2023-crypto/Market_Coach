import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/lesson_step.dart';
import '../../engine/lesson_engine.dart';
import '../rsi_zone_bar.dart';

class TapToIdentifyWidget extends StatelessWidget {
  final TapToIdentifyStep step;
  final LessonEngine engine;

  const TapToIdentifyWidget(
      {super.key, required this.step, required this.engine});

  @override
  Widget build(BuildContext context) {
    final tapped = engine.tappedZoneId;
    final correct = engine.tapCorrect;

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
              'YOUR TURN',
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
            step.instruction,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap the correct zone below.',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 36),
          // Interactive RSI zone bar
          RsiZoneBar(
            interactive: tapped == null || correct != true,
            tappedZone: tapped,
            tapCorrect: correct,
            onTap: (zoneId) {
              HapticFeedback.lightImpact();
              engine.tapZone(zoneId);
            },
          ),
          const SizedBox(height: 32),
          // Feedback area
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildFeedback(tapped, correct),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedback(String? tapped, bool? correct) {
    if (tapped == null) {
      return const SizedBox.shrink(key: ValueKey('none'));
    }
    if (correct == true) {
      return _FeedbackCard(
        key: const ValueKey('correct'),
        icon: Icons.check_circle_outline,
        color: const Color(0xFF4CAF50),
        title: 'Correct!',
        body: step.successMessage,
      );
    }
    return _FeedbackCard(
      key: const ValueKey('incorrect'),
      icon: Icons.close,
      color: Colors.redAccent,
      title: 'Not quite — try again.',
      body: 'Look for the zone on the right side of the bar.',
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  const _FeedbackCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(
                        color: Color(0xB3FFFFFF), fontSize: 13, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
