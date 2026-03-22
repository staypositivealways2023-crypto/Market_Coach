import 'dart:math';
import 'package:flutter/material.dart';
import '../../../models/candle.dart';
import '../../../widgets/chart/chart_type_selector.dart';

class PatternHitTarget {
  final Rect rect;
  final dynamic pattern; // ChartPatternResult
  PatternHitTarget(this.rect, this.pattern);
}

class ChartController extends ChangeNotifier {
  List<Candle> _candles = [];
  double _viewportStart = 0;
  double _viewportEnd = 80;
  int? _selectedCandleIndex;
  bool _showCrosshair = false;
  Offset _crosshairPosition = Offset.zero;
  ChartType _chartType = ChartType.candlestick;
  List<PatternHitTarget> patternHitTargets = [];

  List<Candle> get candles => _candles;
  double get viewportStart => _viewportStart;
  double get viewportEnd => _viewportEnd;
  double get viewportWidth => _viewportEnd - _viewportStart;
  int? get selectedCandleIndex => _selectedCandleIndex;
  bool get showCrosshair => _showCrosshair;
  Offset get crosshairPosition => _crosshairPosition;
  ChartType get chartType => _chartType;

  void setCandles(List<Candle> candles) {
    _candles = candles;
    // Default viewport: last 80 candles
    _viewportEnd = candles.length.toDouble();
    _viewportStart = max(0.0, _viewportEnd - 80.0);
    _selectedCandleIndex = null;
    patternHitTargets = [];
    notifyListeners();
  }

  void setChartType(ChartType type) {
    _chartType = type;
    notifyListeners();
  }

  void pan(double deltaCandles) {
    if (_candles.isEmpty) return;
    final newStart = (_viewportStart - deltaCandles).clamp(0.0, max(0.0, _candles.length - viewportWidth)).toDouble();
    final newEnd = newStart + viewportWidth;
    _viewportStart = newStart;
    _viewportEnd = newEnd;
    notifyListeners();
  }

  void zoom(double scaleFactor, double focalX, Size size) {
    if (_candles.isEmpty) return;
    final focalCandle = _viewportStart + (focalX / size.width) * viewportWidth;
    final newWidth = (viewportWidth / scaleFactor).clamp(10.0, _candles.length.toDouble());
    var newStart = focalCandle - (focalX / size.width) * newWidth;
    newStart = newStart.clamp(0.0, max(0.0, _candles.length.toDouble() - newWidth));
    _viewportStart = newStart;
    _viewportEnd = newStart + newWidth;
    notifyListeners();
  }

  void resetZoom() {
    _viewportEnd = _candles.length.toDouble();
    _viewportStart = max(0.0, _viewportEnd - 80.0);
    notifyListeners();
  }

  void selectCandle(int? index) {
    _selectedCandleIndex = index;
    notifyListeners();
  }

  void showCrosshairAt(Offset position) {
    _showCrosshair = true;
    _crosshairPosition = position;
    // Compute which candle is at this X position — set in painter's coordinate space
    notifyListeners();
  }

  void hideCrosshair() {
    _showCrosshair = false;
    _selectedCandleIndex = null;
    notifyListeners();
  }

  double candleWidth(Size size) {
    if (viewportWidth == 0) return 8;
    return size.width / viewportWidth;
  }

  /// Returns the slice of candles visible in current viewport
  List<Candle> visibleCandles() {
    if (_candles.isEmpty) return [];
    final start = _viewportStart.floor().clamp(0, _candles.length - 1);
    final end = _viewportEnd.ceil().clamp(0, _candles.length);
    return _candles.sublist(start, end);
  }

  /// Returns (low, high) price range for visible candles with 3% padding
  (double, double) priceRangeForVisible() {
    final visible = visibleCandles();
    if (visible.isEmpty) return (0, 1);
    final highs = visible.map((c) => c.high);
    final lows = visible.map((c) => c.low);
    final high = highs.reduce(max) * 1.03;
    final low = lows.reduce(min) * 0.97;
    return (low, high);
  }

  /// Converts a candle index to an X pixel coordinate
  double indexToX(int index, Size size) {
    final cw = candleWidth(size);
    return (index - _viewportStart + 0.5) * cw;
  }

  /// Returns the candle index for a given X pixel coordinate
  int xToIndex(double x, Size size) {
    final cw = candleWidth(size);
    final idx = _viewportStart + (x / cw) - 0.5;
    return idx.round().clamp(0, _candles.length - 1);
  }
}
