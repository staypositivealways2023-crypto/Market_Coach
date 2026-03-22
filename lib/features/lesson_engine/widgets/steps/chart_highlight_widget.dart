import 'package:flutter/material.dart';
import '../../models/lesson_step.dart';
import '../rsi_mini_chart.dart';

class ChartHighlightWidget extends StatelessWidget {
  final ChartHighlightStep step;
  const ChartHighlightWidget({super.key, required this.step});

  @override
  Widget build(BuildContext context) {
    final zoneColor = step.highlightOverbought
        ? const Color(0xFFEF5350)
        : const Color(0xFF4CAF50);
    final zoneLabel =
        step.highlightOverbought ? 'Overbought zone (>70)' : 'Oversold zone (<30)';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: zoneColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: zoneColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              'CHART EXAMPLE',
              style: TextStyle(
                color: zoneColor,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            step.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 20),
          // Mini chart
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF111925),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            clipBehavior: Clip.hardEdge,
            child: Column(
              children: [
                // RSI label bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF26A69A),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('RSI (14)',
                        style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: RsiMiniChart(
                    rsiValues: step.rsiData,
                    highlightOverbought: step.highlightOverbought,
                    highlightOversold: step.highlightOversold,
                    height: 120,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Zone legend
          Row(children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: zoneColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: zoneColor),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              zoneLabel,
              style: TextStyle(
                  color: zoneColor, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ]),
          const SizedBox(height: 20),
          // Description
          Text(
            step.description,
            style: const TextStyle(
              color: Color(0xB3FFFFFF),
              fontSize: 15,
              height: 1.65,
            ),
          ),
        ],
      ),
    );
  }
}
