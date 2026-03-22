import 'package:flutter/material.dart';
import '../../models/lesson_step.dart';
import '../../painters/demo_candle_painter.dart';

/// ST-1: Passive mini candlestick chart with optional annotations and S/R lines.
class CandlestickDemoWidget extends StatelessWidget {
  final CandlestickDemoStep step;

  const CandlestickDemoWidget({super.key, required this.step});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            step.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          // Description
          Text(
            step.description,
            style: const TextStyle(
              color: Color(0xCCFFFFFF),
              fontSize: 15,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          // Chart
          Container(
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF12A28C).withValues(alpha: 0.2)),
            ),
            clipBehavior: Clip.hardEdge,
            child: CustomPaint(
              size: const Size(double.infinity, 200),
              painter: DemoCandlePainter(
                candles: step.candles,
                annotations: step.annotations,
                highlightBullish: step.highlightBullish,
                highlightBearish: step.highlightBearish,
                supportLevel: step.supportLevel,
                resistanceLevel: step.resistanceLevel,
                revealAnnotations: true,
              ),
            ),
          ),
          // Legend chips
          if (step.highlightBullish || step.highlightBearish) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (step.highlightBullish)
                  _LegendChip(color: const Color(0xFF26A69A), label: 'Bullish'),
                if (step.highlightBullish && step.highlightBearish)
                  const SizedBox(width: 12),
                if (step.highlightBearish)
                  _LegendChip(color: const Color(0xFFEF5350), label: 'Bearish'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
