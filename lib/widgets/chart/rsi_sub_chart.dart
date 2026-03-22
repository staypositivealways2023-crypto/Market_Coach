import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../models/candle.dart';

/// RSI Sub-Chart Widget
/// Displays RSI (Relative Strength Index) values with overbought/oversold zones
class RsiSubChart extends StatelessWidget {
  final List<Candle> candles;
  final List<double?> rsiValues;

  const RsiSubChart({
    super.key,
    required this.candles,
    required this.rsiValues,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Create chart data points
    final dataPoints = <_RsiPoint>[];
    for (int i = 0; i < candles.length; i++) {
      if (rsiValues[i] != null) {
        dataPoints.add(_RsiPoint(candles[i].time, rsiValues[i]!));
      }
    }

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
                Icons.show_chart,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'RSI (14)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              if (dataPoints.isNotEmpty)
                Text(
                  dataPoints.last.rsi.toStringAsFixed(1),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: _getRsiColor(dataPoints.last.rsi),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // RSI Chart
          Expanded(
            child: SfCartesianChart(
              plotAreaBorderWidth: 0,
              margin: const EdgeInsets.all(0),
              primaryXAxis: DateTimeAxis(
                isVisible: false,
                edgeLabelPlacement: EdgeLabelPlacement.shift,
              ),
              primaryYAxis: NumericAxis(
                minimum: 0,
                maximum: 100,
                interval: 20,
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
              annotations: dataPoints.isEmpty
                  ? []
                  : [
                      // Overbought line (70)
                      CartesianChartAnnotation(
                        widget: Container(
                          height: 1,
                          color: Colors.red.withValues(alpha: 0.5),
                        ),
                        coordinateUnit: CoordinateUnit.point,
                        region: AnnotationRegion.plotArea,
                        x: dataPoints.first.date,
                        y: 70,
                      ),
                      // Oversold line (30)
                      CartesianChartAnnotation(
                        widget: Container(
                          height: 1,
                          color: Colors.green.withValues(alpha: 0.5),
                        ),
                        coordinateUnit: CoordinateUnit.point,
                        region: AnnotationRegion.plotArea,
                        x: dataPoints.first.date,
                        y: 30,
                      ),
                    ],
              series: <CartesianSeries>[
                SplineSeries<_RsiPoint, DateTime>(
                  dataSource: dataPoints,
                  xValueMapper: (_RsiPoint point, _) => point.date,
                  yValueMapper: (_RsiPoint point, _) => point.rsi,
                  color: const Color(0xFF9C27B0), // Purple
                  width: 2,
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
              _buildLegendItem('Overbought', Colors.red, '> 70'),
              const SizedBox(width: 12),
              _buildLegendItem('Oversold', Colors.green, '< 30'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 2,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$label $value',
          style: const TextStyle(fontSize: 9, color: Colors.white54),
        ),
      ],
    );
  }

  Color _getRsiColor(double rsi) {
    if (rsi >= 70) return Colors.red;
    if (rsi <= 30) return Colors.green;
    return Colors.orange;
  }
}

class _RsiPoint {
  final DateTime date;
  final double rsi;

  _RsiPoint(this.date, this.rsi);
}
