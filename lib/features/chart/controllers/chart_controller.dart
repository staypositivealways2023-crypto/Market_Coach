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
  static const double _rightPaddingRatio = 0.13;

  List<Candle> _candles = [];
  double _viewportStart = 0;
  double _viewportEnd = 80;
  double _defaultVisibleCandles = 80;
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

  double _rightPaddingCandlesForWidth(double width) {
    if (_candles.isEmpty) return 0;
    return max(4.0, width * _rightPaddingRatio);
  }

  double _maxViewportEndForWidth(double width) {
    return _candles.length + _rightPaddingCandlesForWidth(width);
  }

  void _setDefaultViewport() {
    if (_candles.isEmpty) {
      _viewportStart = 0;
      _viewportEnd = 0;
      return;
    }
    final visibleBars = min(_defaultVisibleCandles, _candles.length.toDouble());
    final rightPad = max(4.0, visibleBars * _rightPaddingRatio);
    _viewportEnd = _candles.length.toDouble() + rightPad;
    _viewportStart = max(0.0, _candles.length.toDouble() - visibleBars);
  }

  double rightPaddingBarsForCurrentViewport() {
    return _rightPaddingCandlesForWidth(viewportWidth);
  }

  bool get canPanLeft => _viewportStart > 0.01;

  void setCandles(List<Candle> candles, {bool resetViewport = false}) {
    final oldLength = _candles.length;
    final hadUserViewport =
        !resetViewport &&
        _candles.isNotEmpty &&
        (_viewportEnd - oldLength).abs() > 0.01;
    final oldStart = _viewportStart;
    final oldEnd = _viewportEnd;
    _candles = candles;

    if (candles.isEmpty) {
      _viewportStart = 0;
      _viewportEnd = 0;
    } else if (hadUserViewport) {
      final maxWidth =
          candles.length + _rightPaddingCandlesForWidth(oldEnd - oldStart);
      final width = (oldEnd - oldStart).clamp(10.0, maxWidth.toDouble());
      final maxStart = max(0.0, _maxViewportEndForWidth(width) - width);
      _viewportStart = oldStart.clamp(0.0, maxStart).toDouble();
      _viewportEnd = _viewportStart + width;
    } else {
      // Default viewport: latest readable slice plus right-side future space.
      _setDefaultViewport();
    }
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
    final maxStart = max(
      0.0,
      _maxViewportEndForWidth(viewportWidth) - viewportWidth,
    );
    final newStart = (_viewportStart - deltaCandles)
        .clamp(0.0, maxStart)
        .toDouble();
    final newEnd = newStart + viewportWidth;
    _viewportStart = newStart;
    _viewportEnd = newEnd;
    notifyListeners();
  }

  void zoom(double scaleFactor, double focalX, Size size) {
    if (_candles.isEmpty) return;
    final focalCandle = _viewportStart + (focalX / size.width) * viewportWidth;
    final maxWidth =
        _candles.length.toDouble() +
        _rightPaddingCandlesForWidth(_candles.length.toDouble());
    final newWidth = (viewportWidth / scaleFactor).clamp(10.0, maxWidth);
    var newStart = focalCandle - (focalX / size.width) * newWidth;
    newStart = newStart.clamp(
      0.0,
      max(0.0, _maxViewportEndForWidth(newWidth) - newWidth),
    );
    _viewportStart = newStart;
    _viewportEnd = newStart + newWidth;
    notifyListeners();
  }

  void resetZoom() {
    _setDefaultViewport();
    notifyListeners();
  }

  void setDefaultVisibleCandles(int count) {
    _defaultVisibleCandles = count.clamp(20, 140).toDouble();
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

  /// Returns (low, high) price range for visible candles with proportional padding.
  (double, double) priceRangeForVisible() {
    final visible = visibleCandles();
    if (visible.isEmpty) return (0, 1);
    final highs = visible.map((c) => c.high);
    final lows = visible.map((c) => c.low);
    final rawHigh = highs.reduce(max);
    final rawLow = lows.reduce(min);
    final range = rawHigh - rawLow;
    if (range <= 0) {
      final pad = max(rawHigh.abs() * 0.005, 0.01);
      return (rawLow - pad, rawHigh + pad);
    }
    final pad = range * 0.08;
    return (rawLow - pad, rawHigh + pad);
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
