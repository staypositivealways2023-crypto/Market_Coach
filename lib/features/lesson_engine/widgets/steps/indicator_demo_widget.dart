import 'package:flutter/material.dart';
import '../../models/lesson_step.dart';
import '../../models/demo_models.dart';
import '../../painters/indicator_demo_painter.dart';

/// ST-2: Price line with one indicator overlay (MA, MACD, Bollinger). Read-only.
class IndicatorDemoWidget extends StatelessWidget {
  final IndicatorDemoStep step;

  const IndicatorDemoWidget({super.key, required this.step});

  @override
  Widget build(BuildContext context) {
    final height = step.demoType == IndicatorDemoType.macd ? 240.0 : 200.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Text(
            step.description,
            style: const TextStyle(
              color: Color(0xCCFFFFFF),
              fontSize: 15,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF12A28C).withValues(alpha: 0.2)),
            ),
            clipBehavior: Clip.hardEdge,
            child: CustomPaint(
              size: Size(double.infinity, height),
              painter: IndicatorDemoPainter(
                demoType: step.demoType,
                priceData: step.priceData,
                line1: step.line1,
                line2: step.line2,
                line3: step.line3,
                histogram: step.histogram,
                annotations: step.annotations,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildLegend(),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    final items = <_LegendItem>[];
    items.add(const _LegendItem(color: Color(0xFF90CAF9), label: 'Price'));
    switch (step.demoType) {
      case IndicatorDemoType.ma:
      case IndicatorDemoType.macross:
        if (step.line1 != null) items.add(const _LegendItem(color: Color(0xFF26A69A), label: 'Fast MA'));
        if (step.line2 != null) items.add(const _LegendItem(color: Color(0xFFEF9A9A), label: 'Slow MA'));
      case IndicatorDemoType.bollinger:
        if (step.line1 != null) items.add(const _LegendItem(color: Color(0xFF26A69A), label: 'Upper Band'));
        if (step.line2 != null) items.add(const _LegendItem(color: Color(0xFFEF9A9A), label: 'Lower Band'));
        if (step.line3 != null) items.add(const _LegendItem(color: Color(0xFFB0BEC5), label: 'Mid (SMA)'));
      case IndicatorDemoType.macd:
        if (step.line1 != null) items.add(const _LegendItem(color: Color(0xFF26A69A), label: 'MACD'));
        if (step.line2 != null) items.add(const _LegendItem(color: Color(0xFFEF9A9A), label: 'Signal'));
    }

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: items.map((item) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 20, height: 2, color: item.color),
          const SizedBox(width: 5),
          Text(item.label, style: TextStyle(color: item.color.withValues(alpha: 0.85), fontSize: 11)),
        ],
      )).toList(),
    );
  }
}

class _LegendItem {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});
}
