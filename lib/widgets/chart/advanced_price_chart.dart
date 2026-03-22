import 'dart:math';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

import '../../models/candle.dart';
import '../../models/signal_analysis.dart';
import '../../services/technical_analysis_service.dart';
import 'chart_type_selector.dart';
import 'advanced_indicator_settings.dart';

class AdvancedPriceChart extends StatefulWidget {
  final List<Candle> candles;
  final ChartType chartType;
  final TrackballBehavior trackballBehavior;
  final MAType maType;
  final bool showBollingerBands;
  final SRType srType;
  final PatternScanResult? patterns;
  final void Function(ChartPatternResult)? onPatternTap;

  const AdvancedPriceChart({
    super.key,
    required this.candles,
    required this.chartType,
    required this.trackballBehavior,
    this.maType = MAType.sma,
    this.showBollingerBands = false,
    this.srType = SRType.none,
    this.patterns,
    this.onPatternTap,
  });

  @override
  State<AdvancedPriceChart> createState() => _AdvancedPriceChartState();
}

class _AdvancedPriceChartState extends State<AdvancedPriceChart> {
  late final ZoomPanBehavior _zoomPanBehavior;
  Candle? _hoveredCandle;

  static const _bullColor = Color(0xFF26A69A); // TradingView green
  static const _bearColor = Color(0xFFEF5350); // TradingView red

  // Tracks pattern count so we can re-key the chart when patterns arrive
  int _patternGeneration = 0;

  @override
  void initState() {
    super.initState();
    _zoomPanBehavior = ZoomPanBehavior(
      enablePinching: true,
      enablePanning: true,
      enableDoubleTapZooming: true,
      enableMouseWheelZooming: true,
      enableSelectionZooming: true,
      zoomMode: ZoomMode.x,
    );
  }

  @override
  void didUpdateWidget(AdvancedPriceChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When patterns arrive or change, bump generation so SfCartesianChart
    // gets a new key and fully re-renders its annotation layer.
    final oldCount = oldWidget.patterns?.patterns.length ?? 0;
    final newCount = widget.patterns?.patterns.length ?? 0;
    final oldSR = oldWidget.patterns?.supportResistance.length ?? 0;
    final newSR = widget.patterns?.supportResistance.length ?? 0;
    if (oldCount != newCount || oldSR != newSR) {
      setState(() => _patternGeneration++);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.candles.isEmpty) {
      return Container(
        height: 400,
        color: const Color(0xFF0D1117),
        alignment: Alignment.center,
        child: const Text('No data available', style: TextStyle(color: Colors.white38)),
      );
    }

    // Technical indicators
    final sma20 = (widget.maType == MAType.sma || widget.maType == MAType.both)
        ? TechnicalAnalysisService.calculateSMA(widget.candles, 20) : null;
    final sma50 = (widget.maType == MAType.sma || widget.maType == MAType.both)
        ? TechnicalAnalysisService.calculateSMA(widget.candles, 50) : null;
    final sma200 = (widget.maType == MAType.sma || widget.maType == MAType.both) && widget.candles.length >= 200
        ? TechnicalAnalysisService.calculateSMA(widget.candles, 200) : null;
    final ema12 = (widget.maType == MAType.ema || widget.maType == MAType.both)
        ? TechnicalAnalysisService.calculateEMA(widget.candles, 12) : null;
    final ema26 = (widget.maType == MAType.ema || widget.maType == MAType.both)
        ? TechnicalAnalysisService.calculateEMA(widget.candles, 26) : null;
    final ema50 = (widget.maType == MAType.ema || widget.maType == MAType.both)
        ? TechnicalAnalysisService.calculateEMA(widget.candles, 50) : null;
    final bollingerBands = widget.showBollingerBands
        ? TechnicalAnalysisService.calculateBollingerBands(widget.candles) : null;

    double? support, resistance;
    Map<String, double>? pivotPoints, fibonacciLevels;
    switch (widget.srType) {
      case SRType.simple:
        support = TechnicalAnalysisService.calculateSupport(widget.candles);
        resistance = TechnicalAnalysisService.calculateResistance(widget.candles);
        break;
      case SRType.pivot:
        pivotPoints = TechnicalAnalysisService.calculatePivotPoints(widget.candles);
        break;
      case SRType.fibonacci:
        fibonacciLevels = TechnicalAnalysisService.calculateFibonacci(widget.candles);
        break;
      case SRType.none:
        break;
    }

    // X-axis smart intervals
    final duration = widget.candles.last.time.difference(widget.candles.first.time);
    DateTimeIntervalType xIntervalType;
    DateFormat xLabelFormat;
    double xInterval;
    if (duration.inDays <= 3) {
      xIntervalType = DateTimeIntervalType.hours;
      xLabelFormat = DateFormat('HH:mm');
      xInterval = 4;
    } else if (duration.inDays <= 90) {
      xIntervalType = DateTimeIntervalType.days;
      xLabelFormat = DateFormat('MMM dd');
      xInterval = max(7, (duration.inDays / 6).ceilToDouble());
    } else if (duration.inDays <= 400) {
      xIntervalType = DateTimeIntervalType.months;
      xLabelFormat = DateFormat('MMM');
      xInterval = 1;
    } else {
      xIntervalType = DateTimeIntervalType.months;
      xLabelFormat = DateFormat("MMM ''yy");
      xInterval = 3;
    }

    final maxPrice = widget.candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    final yNumberFormat = maxPrice >= 10000 ? NumberFormat('#,##0') : NumberFormat('#,##0.##');

    final totalCandles = widget.candles.length;
    // Show 80 candles by default — gives thicker bodies without looking cramped
    const targetVisible = 80;
    final xZoomFactor = totalCandles > targetVisible ? targetVisible / totalCandles : 1.0;
    final xZoomPosition = 1.0 - xZoomFactor;

    // Volume axis max — push bars to bottom 20% of chart
    final maxVolume = widget.candles.map((c) => c.volume).reduce((a, b) => a > b ? a : b);

    final displayCandle = _hoveredCandle ?? widget.candles.last;
    final isUp = displayCandle.close >= displayCandle.open;
    final ohlcColor = isUp ? _bullColor : _bearColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // OHLCV info header
        Container(
          color: const Color(0xFF0D1117),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Row(
            children: [
              _ohlcLabel('O', _fmt(displayCandle.open, maxPrice), ohlcColor),
              const SizedBox(width: 10),
              _ohlcLabel('H', _fmt(displayCandle.high, maxPrice), ohlcColor),
              const SizedBox(width: 10),
              _ohlcLabel('L', _fmt(displayCandle.low, maxPrice), ohlcColor),
              const SizedBox(width: 10),
              _ohlcLabel('C', _fmt(displayCandle.close, maxPrice), ohlcColor),
              const SizedBox(width: 10),
              if (displayCandle.volume > 0)
                _ohlcLabel('V', _fmtVol(displayCandle.volume), Colors.white38),
            ],
          ),
        ),

        // Main chart
        SizedBox(
          height: 380,
          child: SfCartesianChart(
            key: ValueKey('chart_$_patternGeneration'),
            backgroundColor: const Color(0xFF0D1117),
            plotAreaBorderWidth: 0,
            plotAreaBorderColor: Colors.transparent,
            onTrackballPositionChanging: (TrackballArgs args) {
              final idx = args.chartPointInfo.dataPointIndex;
              if (idx != null && idx >= 0 && idx < widget.candles.length) {
                if (mounted) setState(() => _hoveredCandle = widget.candles[idx]);
              }
            },
            axes: <ChartAxis>[
              NumericAxis(
                name: 'volumeAxis',
                isVisible: false,
                maximum: maxVolume > 0 ? maxVolume * 5 : 1,
              ),
            ],
            primaryXAxis: DateTimeAxis(
              majorGridLines: MajorGridLines(width: 0.5, color: Colors.white.withValues(alpha: 0.06)),
              minorGridLines: const MinorGridLines(width: 0),
              axisLine: const AxisLine(width: 0),
              labelStyle: const TextStyle(color: Colors.white38, fontSize: 10),
              dateFormat: xLabelFormat,
              intervalType: xIntervalType,
              interval: xInterval,
              edgeLabelPlacement: EdgeLabelPlacement.shift,
              enableAutoIntervalOnZooming: true,
              initialZoomFactor: xZoomFactor,
              initialZoomPosition: xZoomPosition,
            ),
            primaryYAxis: NumericAxis(
              majorGridLines: MajorGridLines(width: 0.5, color: Colors.white.withValues(alpha: 0.06)),
              minorGridLines: const MinorGridLines(width: 0),
              axisLine: const AxisLine(width: 0),
              labelStyle: const TextStyle(color: Colors.white38, fontSize: 10),
              opposedPosition: true,
              desiredIntervals: 5,
              numberFormat: yNumberFormat,
              edgeLabelPlacement: EdgeLabelPlacement.shift,
              enableAutoIntervalOnZooming: true,
            ),
            trackballBehavior: widget.trackballBehavior,
            zoomPanBehavior: _zoomPanBehavior,
            series: <CartesianSeries>[
              // Volume bars (behind candles, secondary axis)
              if (maxVolume > 0)
                ColumnSeries<Candle, DateTime>(
                  dataSource: widget.candles,
                  xValueMapper: (c, _) => c.time,
                  yValueMapper: (c, _) => c.volume,
                  yAxisName: 'volumeAxis',
                  pointColorMapper: (c, _) => c.close >= c.open
                      ? _bullColor.withValues(alpha: 0.25)
                      : _bearColor.withValues(alpha: 0.25),
                  borderWidth: 0,
                  spacing: 0.1,
                  name: 'Volume',
                ),

              // Bollinger bands
              if (bollingerBands != null) ...[
                SplineAreaSeries<_BollingerPoint, DateTime>(
                  dataSource: _getBollingerPoints(bollingerBands['upper']!),
                  xValueMapper: (_BollingerPoint p, _) => p.time,
                  yValueMapper: (_BollingerPoint p, _) => p.value,
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderColor: Colors.blue.withValues(alpha: 0.3),
                  borderWidth: 1,
                  markerSettings: const MarkerSettings(isVisible: false),
                ),
                SplineAreaSeries<_BollingerPoint, DateTime>(
                  dataSource: _getBollingerPoints(bollingerBands['lower']!),
                  xValueMapper: (_BollingerPoint p, _) => p.time,
                  yValueMapper: (_BollingerPoint p, _) => p.value,
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderColor: Colors.blue.withValues(alpha: 0.3),
                  borderWidth: 1,
                  markerSettings: const MarkerSettings(isVisible: false),
                ),
              ],

              // Price chart
              ..._buildPriceChart(widget.chartType),

              // Moving averages
              if (sma20 != null)
                SplineSeries<_MAPoint, DateTime>(dataSource: _getMAPoints(sma20, 'SMA 20'), xValueMapper: (p, _) => p.time, yValueMapper: (p, _) => p.value, color: const Color(0xFFFFEB3B), width: 1.5, name: 'SMA 20', markerSettings: const MarkerSettings(isVisible: false)),
              if (sma50 != null)
                SplineSeries<_MAPoint, DateTime>(dataSource: _getMAPoints(sma50, 'SMA 50'), xValueMapper: (p, _) => p.time, yValueMapper: (p, _) => p.value, color: const Color(0xFFFF9800), width: 1.5, name: 'SMA 50', markerSettings: const MarkerSettings(isVisible: false)),
              if (sma200 != null)
                SplineSeries<_MAPoint, DateTime>(dataSource: _getMAPoints(sma200, 'SMA 200'), xValueMapper: (p, _) => p.time, yValueMapper: (p, _) => p.value, color: const Color(0xFFE91E63), width: 1.5, name: 'SMA 200', markerSettings: const MarkerSettings(isVisible: false)),
              if (ema12 != null)
                SplineSeries<_MAPoint, DateTime>(dataSource: _getMAPoints(ema12, 'EMA 12'), xValueMapper: (p, _) => p.time, yValueMapper: (p, _) => p.value, color: const Color(0xFF00BCD4), width: 1.5, name: 'EMA 12', markerSettings: const MarkerSettings(isVisible: false)),
              if (ema26 != null)
                SplineSeries<_MAPoint, DateTime>(dataSource: _getMAPoints(ema26, 'EMA 26'), xValueMapper: (p, _) => p.time, yValueMapper: (p, _) => p.value, color: const Color(0xFF9C27B0), width: 1.5, name: 'EMA 26', markerSettings: const MarkerSettings(isVisible: false)),
              if (ema50 != null)
                SplineSeries<_MAPoint, DateTime>(dataSource: _getMAPoints(ema50, 'EMA 50'), xValueMapper: (p, _) => p.time, yValueMapper: (p, _) => p.value, color: const Color(0xFF4CAF50), width: 1.5, name: 'EMA 50', markerSettings: const MarkerSettings(isVisible: false)),
            ],
            annotations: <CartesianChartAnnotation>[
              if (support != null) ..._srAnnotation(support, Colors.green, 'S', widget.candles),
              if (resistance != null) ..._srAnnotation(resistance, Colors.red, 'R', widget.candles),
              ...?_buildPivotAnnotations(pivotPoints),
              ...?_buildFibonacciAnnotations(fibonacciLevels),
              ..._buildPatternAnnotations(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ohlcLabel(String key, String value, Color valueColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$key ', style: const TextStyle(color: Colors.white38, fontSize: 10)),
        Text(value, style: TextStyle(color: valueColor, fontSize: 10, fontWeight: FontWeight.w600)),
      ],
    );
  }

  String _fmt(double v, double maxPrice) {
    if (maxPrice >= 10000) return NumberFormat('#,##0').format(v);
    if (v < 1) return v.toStringAsFixed(4);
    return v.toStringAsFixed(2);
  }

  String _fmtVol(double v) {
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(1)}B';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  List<CartesianChartAnnotation> _srAnnotation(double level, Color color, String label, List<Candle> candles) {
    return [
      CartesianChartAnnotation(
        widget: Container(height: 1, color: color.withValues(alpha: 0.6)),
        coordinateUnit: CoordinateUnit.point,
        region: AnnotationRegion.plotArea,
        x: candles.first.time,
        y: level,
      ),
      CartesianChartAnnotation(
        widget: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(3)),
          child: Text('$label \$${level.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
        ),
        coordinateUnit: CoordinateUnit.point,
        region: AnnotationRegion.plotArea,
        x: candles.last.time,
        y: level,
        horizontalAlignment: ChartAlignment.far,
      ),
    ];
  }

  List<CartesianChartAnnotation>? _buildPivotAnnotations(Map<String, double>? pivots) {
    if (pivots == null || widget.candles.isEmpty) return null;
    final annotations = <CartesianChartAnnotation>[];
    final colors = {'r2': Colors.red[700]!, 'r1': Colors.red[400]!, 'pivot': Colors.orange, 's1': Colors.green[400]!, 's2': Colors.green[700]!};
    pivots.forEach((key, value) {
      final color = colors[key] ?? Colors.grey;
      annotations.add(CartesianChartAnnotation(widget: Container(height: 1, color: color.withValues(alpha: 0.6)), coordinateUnit: CoordinateUnit.point, region: AnnotationRegion.plotArea, x: widget.candles.first.time, y: value));
      annotations.add(CartesianChartAnnotation(
        widget: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: color.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(3)), child: Text('${key.toUpperCase()}: \$${value.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
        coordinateUnit: CoordinateUnit.point, region: AnnotationRegion.plotArea, x: widget.candles.last.time, y: value, horizontalAlignment: ChartAlignment.far,
      ));
    });
    return annotations;
  }

  List<CartesianChartAnnotation>? _buildFibonacciAnnotations(Map<String, double>? fibs) {
    if (fibs == null || widget.candles.isEmpty) return null;
    final annotations = <CartesianChartAnnotation>[];
    final color = Colors.purple;
    fibs.forEach((key, value) {
      annotations.add(CartesianChartAnnotation(widget: Container(height: 1, color: color.withValues(alpha: 0.5)), coordinateUnit: CoordinateUnit.point, region: AnnotationRegion.plotArea, x: widget.candles.first.time, y: value));
      annotations.add(CartesianChartAnnotation(
        widget: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: color.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(3)), child: Text('$key: \$${value.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
        coordinateUnit: CoordinateUnit.point, region: AnnotationRegion.plotArea, x: widget.candles.last.time, y: value, horizontalAlignment: ChartAlignment.far,
      ));
    });
    return annotations;
  }

  List<CartesianChartAnnotation> _buildPatternAnnotations() {
    final result = widget.patterns;
    if (result == null || result.patterns.isEmpty || widget.candles.isEmpty) return [];

    final annotations = <CartesianChartAnnotation>[];
    final maxPrice = widget.candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    final minPrice = widget.candles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final priceRange = maxPrice - minPrice;
    final offset = priceRange * 0.04; // 4% above candle high

    for (final pat in result.patterns) {
      // Resolve candle index
      int idx = pat.formedAtIndex;
      if (idx < 0 || idx >= widget.candles.length) idx = widget.candles.length - 1;
      final candle = widget.candles[idx];
      final y = candle.high + offset;

      final isBull = pat.signal == 'BULLISH';
      final isBear = pat.signal == 'BEARISH';
      final color = isBull
          ? const Color(0xFF12A28C)
          : isBear
              ? const Color(0xFFEF5350)
              : Colors.white54;

      // Short label: first letters of each word
      final abbrev = pat.displayName
          .split(' ')
          .map((w) => w.isNotEmpty ? w[0] : '')
          .join('');

      annotations.add(CartesianChartAnnotation(
        coordinateUnit: CoordinateUnit.point,
        region: AnnotationRegion.plotArea,
        x: candle.time,
        y: y,
        widget: GestureDetector(
          onTap: () => widget.onPatternTap?.call(pat),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Lightning bolt marker
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.7), width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  isBull ? '⚡' : isBear ? '⚠' : '◆',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 2),
              // Abbreviation label
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  abbrev,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ));
    }

    // S/R level lines from backend (top 3)
    for (final sr in result.supportResistance.take(3)) {
      final srColor = sr.type == 'SUPPORT'
          ? const Color(0xFF12A28C).withValues(alpha: 0.5)
          : const Color(0xFFEF5350).withValues(alpha: 0.5);
      annotations.add(CartesianChartAnnotation(
        coordinateUnit: CoordinateUnit.point,
        region: AnnotationRegion.plotArea,
        x: widget.candles.first.time,
        y: sr.price,
        widget: Container(height: 1, color: srColor),
      ));
      annotations.add(CartesianChartAnnotation(
        coordinateUnit: CoordinateUnit.point,
        region: AnnotationRegion.plotArea,
        x: widget.candles.last.time,
        y: sr.price,
        horizontalAlignment: ChartAlignment.far,
        widget: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: srColor,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            '${sr.type == 'SUPPORT' ? 'S' : 'R'} \$${sr.price.toStringAsFixed(sr.price >= 100 ? 2 : 4)}',
            style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700),
          ),
        ),
      ));
    }

    return annotations;
  }

  List<CartesianSeries> _buildPriceChart(ChartType type) {
    switch (type) {
      case ChartType.candlestick:
        return [
          CandleSeries<Candle, DateTime>(
            dataSource: widget.candles,
            xValueMapper: (c, _) => c.time,
            lowValueMapper: (c, _) => c.low,
            highValueMapper: (c, _) => c.high,
            openValueMapper: (c, _) => c.open,
            closeValueMapper: (c, _) => c.close,
            bullColor: _bullColor,
            bearColor: _bearColor,
            enableSolidCandles: true,
            spacing: 0.05,
            name: 'Price',
          ),
        ];
      case ChartType.line:
        return [
          FastLineSeries<Candle, DateTime>(
            dataSource: widget.candles,
            xValueMapper: (c, _) => c.time,
            yValueMapper: (c, _) => c.close,
            color: const Color(0xFF26A69A),
            width: 2,
            name: 'Price',
          ),
        ];
      case ChartType.bar:
        return [
          HiloOpenCloseSeries<Candle, DateTime>(
            dataSource: widget.candles,
            xValueMapper: (c, _) => c.time,
            highValueMapper: (c, _) => c.high,
            lowValueMapper: (c, _) => c.low,
            openValueMapper: (c, _) => c.open,
            closeValueMapper: (c, _) => c.close,
            bullColor: _bullColor,
            bearColor: _bearColor,
            name: 'Price',
          ),
        ];
      case ChartType.area:
        return [
          SplineAreaSeries<Candle, DateTime>(
            dataSource: widget.candles,
            xValueMapper: (c, _) => c.time,
            yValueMapper: (c, _) => c.close,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [const Color(0xFF26A69A).withValues(alpha: 0.4), const Color(0xFF26A69A).withValues(alpha: 0.02)],
            ),
            borderColor: const Color(0xFF26A69A),
            borderWidth: 2,
            name: 'Price',
            markerSettings: const MarkerSettings(isVisible: false),
          ),
        ];
    }
  }

  List<_MAPoint> _getMAPoints(List<double?> maValues, String name) {
    final points = <_MAPoint>[];
    for (int i = 0; i < widget.candles.length; i++) {
      if (maValues[i] != null) points.add(_MAPoint(time: widget.candles[i].time, value: maValues[i]!, name: name));
    }
    return points;
  }

  List<_BollingerPoint> _getBollingerPoints(List<double?> values) {
    final points = <_BollingerPoint>[];
    for (int i = 0; i < widget.candles.length; i++) {
      if (values[i] != null) points.add(_BollingerPoint(time: widget.candles[i].time, value: values[i]!));
    }
    return points;
  }
}

class _MAPoint {
  final DateTime time;
  final double value;
  final String name;

  _MAPoint({required this.time, required this.value, required this.name});
}

class _BollingerPoint {
  final DateTime time;
  final double value;

  _BollingerPoint({required this.time, required this.value});
}
