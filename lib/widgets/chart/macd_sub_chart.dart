import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../models/candle.dart';

/// MACD Sub-Chart Widget
/// Displays MACD line, Signal line, and Histogram
class MacdSubChart extends StatelessWidget {
  final List<Candle> candles;
  final List<double?> macdLine;
  final List<double?> signalLine;
  final List<double?> histogram;

  const MacdSubChart({
    super.key,
    required this.candles,
    required this.macdLine,
    required this.signalLine,
    required this.histogram,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Create chart data points
    final macdPoints = <_MacdPoint>[];
    final signalPoints = <_MacdPoint>[];
    final histogramPoints = <_HistogramPoint>[];

    for (int i = 0; i < candles.length; i++) {
      final date = candles[i].time;

      if (macdLine[i] != null) {
        macdPoints.add(_MacdPoint(date, macdLine[i]!));
      }

      if (signalLine[i] != null) {
        signalPoints.add(_MacdPoint(date, signalLine[i]!));
      }

      if (histogram[i] != null) {
        histogramPoints.add(_HistogramPoint(
          date,
          histogram[i]!,
          histogram[i]! >= 0,
        ));
      }
    }

    // Get current values
    final currentMacd = macdPoints.isNotEmpty ? macdPoints.last.value : 0.0;
    final currentSignal = signalPoints.isNotEmpty ? signalPoints.last.value : 0.0;
    final currentHistogram = histogramPoints.isNotEmpty ? histogramPoints.last.value : 0.0;

    return Container(
      height: 150,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.bar_chart,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'MACD (12, 26, 9)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              if (macdPoints.isNotEmpty)
                Row(
                  children: [
                    _buildValue('MACD', currentMacd, const Color(0xFF2196F3)),
                    const SizedBox(width: 8),
                    _buildValue('Signal', currentSignal, const Color(0xFFFF9800)),
                    const SizedBox(width: 8),
                    _buildValue(
                      'Hist',
                      currentHistogram,
                      currentHistogram >= 0 ? Colors.green : Colors.red,
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),

          // MACD Chart
          Expanded(
            child: SfCartesianChart(
              plotAreaBorderWidth: 0,
              margin: const EdgeInsets.all(0),
              primaryXAxis: DateTimeAxis(
                isVisible: false,
                edgeLabelPlacement: EdgeLabelPlacement.shift,
              ),
              primaryYAxis: NumericAxis(
                axisLine: const AxisLine(width: 0),
                majorTickLines: const MajorTickLines(size: 0),
                majorGridLines: MajorGridLines(
                  width: 0.5,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                labelStyle: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                ),
              ),
              annotations: macdPoints.isEmpty ? [] : [
                // Zero line
                CartesianChartAnnotation(
                  widget: Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  coordinateUnit: CoordinateUnit.point,
                  region: AnnotationRegion.plotArea,
                  x: macdPoints.first.date,
                  y: 0,
                ),
              ],
              series: <CartesianSeries>[
                // Histogram (must be first to render behind lines)
                ColumnSeries<_HistogramPoint, DateTime>(
                  dataSource: histogramPoints,
                  xValueMapper: (_HistogramPoint point, _) => point.date,
                  yValueMapper: (_HistogramPoint point, _) => point.value,
                  pointColorMapper: (_HistogramPoint point, _) =>
                      point.isPositive
                          ? Colors.green.withValues(alpha: 0.5)
                          : Colors.red.withValues(alpha: 0.5),
                  width: 0.8,
                  borderWidth: 0,
                  animationDuration: 0,
                ),
                // MACD Line
                SplineSeries<_MacdPoint, DateTime>(
                  dataSource: macdPoints,
                  xValueMapper: (_MacdPoint point, _) => point.date,
                  yValueMapper: (_MacdPoint point, _) => point.value,
                  color: const Color(0xFF2196F3), // Blue
                  width: 2,
                  name: 'MACD',
                  animationDuration: 0,
                ),
                // Signal Line
                SplineSeries<_MacdPoint, DateTime>(
                  dataSource: signalPoints,
                  xValueMapper: (_MacdPoint point, _) => point.date,
                  yValueMapper: (_MacdPoint point, _) => point.value,
                  color: const Color(0xFFFF9800), // Orange
                  width: 2,
                  name: 'Signal',
                  dashArray: const <double>[5, 5],
                  animationDuration: 0,
                ),
              ],
              trackballBehavior: TrackballBehavior(
                enable: true,
                activationMode: ActivationMode.singleTap,
                tooltipSettings: const InteractiveTooltip(
                  enable: true,
                  color: Colors.black87,
                  textStyle: TextStyle(color: Colors.white, fontSize: 11),
                ),
                lineType: TrackballLineType.vertical,
                lineColor: Colors.white.withValues(alpha: 0.3),
                lineWidth: 1,
              ),
              zoomPanBehavior: ZoomPanBehavior(
                enablePinching: true,
                enablePanning: true,
                zoomMode: ZoomMode.x,
              ),
            ),
          ),

          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildLegendItem('MACD', const Color(0xFF2196F3)),
              const SizedBox(width: 12),
              _buildLegendItem('Signal', const Color(0xFFFF9800)),
              const SizedBox(width: 12),
              _buildLegendItem('Histogram', Colors.grey),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildValue(String label, double value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 10,
            color: Colors.white54,
          ),
        ),
        Text(
          value.toStringAsFixed(2),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 2,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: Colors.white54,
          ),
        ),
      ],
    );
  }
}

class _MacdPoint {
  final DateTime date;
  final double value;

  _MacdPoint(this.date, this.value);
}

class _HistogramPoint {
  final DateTime date;
  final double value;
  final bool isPositive;

  _HistogramPoint(this.date, this.value, this.isPositive);
}
