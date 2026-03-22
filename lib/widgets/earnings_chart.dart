import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../models/fundamentals.dart';
import 'glass_card.dart';

/// Bar chart showing quarterly EPS history (up to 8 quarters).
class EarningsChart extends StatelessWidget {
  final List<QuarterlyEps> quarters;

  const EarningsChart({super.key, required this.quarters});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    final visible = quarters.where((q) => q.eps != null).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart, color: primary, size: 18),
              const SizedBox(width: 8),
              Text('Quarterly EPS',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: SfCartesianChart(
              backgroundColor: Colors.transparent,
              plotAreaBorderWidth: 0,
              margin: EdgeInsets.zero,
              primaryXAxis: CategoryAxis(
                labelStyle: const TextStyle(color: Colors.white54, fontSize: 9),
                axisLine: const AxisLine(width: 0),
                majorTickLines: const MajorTickLines(size: 0),
                majorGridLines: const MajorGridLines(width: 0),
              ),
              primaryYAxis: NumericAxis(
                labelStyle:
                    const TextStyle(color: Colors.white38, fontSize: 9),
                axisLine: const AxisLine(width: 0),
                majorTickLines: const MajorTickLines(size: 0),
                majorGridLines: MajorGridLines(
                    width: 0.3,
                    color: Colors.white.withValues(alpha: 0.08)),
                labelFormat: '\${value}',
              ),
              series: [
                ColumnSeries<QuarterlyEps, String>(
                  dataSource: visible,
                  xValueMapper: (q, _) => q.period,
                  yValueMapper: (q, _) => q.eps,
                  pointColorMapper: (q, _) => (q.eps ?? 0) >= 0
                      ? const Color(0xFF00C896)
                      : const Color(0xFFFF4D6A),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                  width: 0.6,
                  dataLabelSettings: const DataLabelSettings(
                    isVisible: true,
                    textStyle: TextStyle(
                        color: Colors.white70,
                        fontSize: 8,
                        fontWeight: FontWeight.w600),
                    labelAlignment: ChartDataLabelAlignment.top,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
