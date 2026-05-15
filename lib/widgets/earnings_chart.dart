import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../models/fundamentals.dart';
import 'glass_card.dart';

/// Bar chart showing quarterly EPS history (up to 8 quarters).
/// Labels appear under each bar via Syncfusion's CategoryAxis — no manual Row.
class EarningsChart extends StatelessWidget {
  final List<QuarterlyEps> quarters;

  const EarningsChart({super.key, required this.quarters});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    final epsQuarters = quarters.where((q) => q.eps != null).toList()
      ..sort((a, b) => _sortDate(a).compareTo(_sortDate(b)));
    final visible = epsQuarters.length > 8
        ? epsQuarters.sublist(epsQuarters.length - 8)
        : epsQuarters;
    if (visible.isEmpty) return const SizedBox.shrink();

    final points = [
      for (var i = 0; i < visible.length; i++)
        _EpsPoint(
          index: i,
          label: _quarterLabel(visible[i]),
          quarter: visible[i],
        ),
    ];

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title row ────────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.bar_chart, color: primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'Quarterly EPS',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Chart (labels rendered by CategoryAxis) ──────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              // Each bar gets 88 px of width for 5+ bars; fill width for ≤4.
              final chartWidth = visible.length <= 4
                  ? constraints.maxWidth
                  : visible.length * 88.0;

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: SizedBox(
                  // Extra 24 px right padding so the last bar + its data
                  // label are never clipped by the scroll-view edge.
                  width: chartWidth + 24,
                  child: SizedBox(
                    // 220 px = bars (~130) + top data labels (~28)
                    //         + x-axis labels (~36) + breathing room
                    height: 220,
                    child: SfCartesianChart(
                      backgroundColor: Colors.transparent,
                      plotAreaBorderWidth: 0,
                      // left margin leaves room for the Y-axis labels;
                      // right margin gives the last bar room to breathe.
                      margin: const EdgeInsets.fromLTRB(4, 14, 28, 0),
                      primaryXAxis: CategoryAxis(
                        isVisible: true,
                        labelStyle: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                        majorGridLines: const MajorGridLines(width: 0),
                        axisLine: const AxisLine(width: 0),
                        majorTickLines: const MajorTickLines(size: 0),
                        // Reserve 36 px below the plot area for labels.
                        labelsExtent: 36,
                        labelAlignment: LabelAlignment.center,
                        // plotOffset keeps bars away from both edges.
                        plotOffsetStart: 16,
                        plotOffsetEnd: 16,
                      ),
                      primaryYAxis: NumericAxis(
                        labelStyle: const TextStyle(
                          color: Colors.white38,
                          fontSize: 9,
                        ),
                        axisLine: const AxisLine(width: 0),
                        majorTickLines: const MajorTickLines(size: 0),
                        plotOffsetStart: 18,
                        plotOffsetEnd: 10,
                        majorGridLines: MajorGridLines(
                          width: 0.3,
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                        labelFormat: '\${value}',
                        rangePadding: ChartRangePadding.additional,
                      ),
                      series: [
                        ColumnSeries<_EpsPoint, String>(
                          dataSource: points,
                          // X key = the quarter label string.
                          // CategoryAxis shows this string below each bar.
                          xValueMapper: (point, _) => point.label,
                          yValueMapper: (point, _) => point.quarter.eps,
                          pointColorMapper: (point, _) =>
                              (point.quarter.eps ?? 0) >= 0
                                  ? const Color(0xFF00C896)
                                  : const Color(0xFFFF4D6A),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                          width: 0.52,
                          // EPS value floats above each bar.
                          dataLabelMapper: (point, _) =>
                              point.quarter.eps == null
                                  ? ''
                                  : '\$${point.quarter.eps!.toStringAsFixed(2)}',
                          dataLabelSettings: const DataLabelSettings(
                            isVisible: true,
                            textStyle: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                            margin: EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            offset: Offset(0, -4),
                            labelAlignment: ChartDataLabelAlignment.outer,
                            overflowMode: OverflowMode.shift,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  /// Always returns a non-empty string, e.g. "Q1 2024\nMar 31".
  String _quarterLabel(QuarterlyEps q) {
    final raw = q.reportDate.isNotEmpty ? q.reportDate : q.period;
    if (raw.isEmpty) return 'Q?';
    try {
      final d = DateTime.parse(raw);
      final qNum = ((d.month - 1) ~/ 3) + 1;
      return 'Q$qNum ${d.year}\n${_monthDay(d)}';
    } catch (_) {
      // Unparseable string — show it as-is so at least something appears.
      return raw.length > 12 ? raw.substring(0, 12) : raw;
    }
  }

  String _monthDay(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  DateTime _sortDate(QuarterlyEps q) {
    final raw = q.reportDate.isNotEmpty ? q.reportDate : q.period;
    return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
}

class _EpsPoint {
  final int index;
  final String label;
  final QuarterlyEps quarter;

  const _EpsPoint({
    required this.index,
    required this.label,
    required this.quarter,
  });
}
