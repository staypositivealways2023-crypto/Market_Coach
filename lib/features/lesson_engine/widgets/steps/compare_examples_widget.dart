import 'package:flutter/material.dart';
import '../../models/lesson_step.dart';
import '../rsi_zone_bar.dart';

class CompareExamplesWidget extends StatelessWidget {
  final CompareExamplesStep step;
  const CompareExamplesWidget({super.key, required this.step});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white12),
            ),
            child: const Text(
              'COMPARE',
              style: TextStyle(
                color: Colors.white54,
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
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 28),
          // Side by side cards
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _ExampleCard(card: step.left)),
                const SizedBox(width: 12),
                Expanded(child: _ExampleCard(card: step.right)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Mini gauges side by side
          Row(children: [
            Expanded(child: _MiniGauge(value: step.left.rsiValue, color: step.left.color)),
            const SizedBox(width: 12),
            Expanded(child: _MiniGauge(value: step.right.rsiValue, color: step.right.color)),
          ]),
        ],
      ),
    );
  }
}

class _ExampleCard extends StatelessWidget {
  final CompareCard card;
  const _ExampleCard({required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card.color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: card.color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card.label,
            style: TextStyle(
              color: card.color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'RSI ${card.rsiValue.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            card.scenario,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const Spacer(),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: card.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              card.interpretation,
              style: TextStyle(
                color: card.color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniGauge extends StatelessWidget {
  final double value;
  final Color color;
  const _MiniGauge({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return RsiZoneBar(indicatorValue: value);
  }
}
