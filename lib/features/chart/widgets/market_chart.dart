import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../controllers/chart_controller.dart';
import '../models/chart_overlay.dart';
import '../painters/candlestick_painter.dart';
import '../painters/overlay_painter.dart';
import 'chart_tooltip.dart';

/// The main interactive chart widget.
/// Handles pan (1-finger), pinch-zoom (2-finger), mouse-wheel zoom, long-press crosshair.
/// Mouse-wheel zoom claims the pointer signal via [PointerSignalResolver] so the
/// outer [CustomScrollView] doesn't also scroll while the user zooms the chart.
class MarketChart extends StatefulWidget {
  final ChartController controller;
  final OverlayData overlays;
  final double height;
  final void Function(dynamic pattern)? onPatternTap;

  // RSI/MACD data for in-canvas panels
  final List<double?> rsiValues;
  final List<double?> macdLine;
  final List<double?> signalLine;
  final List<double?> histogram;
  final bool showRSI;
  final bool showMACD;

  const MarketChart({
    super.key,
    required this.controller,
    this.overlays = const OverlayData(),
    this.height = 320,
    this.onPatternTap,
    this.rsiValues = const [],
    this.macdLine = const [],
    this.signalLine = const [],
    this.histogram = const [],
    this.showRSI = false,
    this.showMACD = false,
  });

  @override
  State<MarketChart> createState() => _MarketChartState();
}

class _MarketChartState extends State<MarketChart> {
  Size _chartSize = Size.zero;
  Timer? _tooltipTimer;
  bool _showTooltip = false;

  double _lastScale = 1.0;
  Offset? _lastFocalPoint;

  @override
  void dispose() {
    _tooltipTimer?.cancel();
    super.dispose();
  }

  void _onScaleStart(ScaleStartDetails d) {
    _lastScale = 1.0;
    _lastFocalPoint = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_chartSize == Size.zero) return;

    // Pan (single finger horizontal drag)
    if (d.pointerCount == 1 && _lastFocalPoint != null) {
      final deltaX = d.localFocalPoint.dx - _lastFocalPoint!.dx;
      final deltaCandles = deltaX / widget.controller.candleWidth(_chartSize);
      widget.controller.pan(deltaCandles);
    }

    // Pinch zoom (two fingers)
    if (d.pointerCount >= 2) {
      final scaleFactor = d.scale / _lastScale;
      if (scaleFactor != 1.0) {
        widget.controller.zoom(scaleFactor, d.localFocalPoint.dx, _chartSize);
      }
    }

    _lastScale = d.scale;
    _lastFocalPoint = d.localFocalPoint;
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _lastFocalPoint = null;
    _lastScale = 1.0;
  }

  void _onLongPressStart(LongPressStartDetails d) {
    _tooltipTimer?.cancel();
    setState(() => _showTooltip = true);
    _updateCrosshair(d.localPosition);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails d) {
    _updateCrosshair(d.localPosition);
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    widget.controller.hideCrosshair();
    _tooltipTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showTooltip = false);
    });
  }

  void _onTapUp(TapUpDetails d) {
    if (_chartSize == Size.zero) return;
    // Check pattern hit targets
    for (final hit in widget.controller.patternHitTargets) {
      if (hit.rect.contains(d.localPosition)) {
        widget.onPatternTap?.call(hit.pattern);
        return;
      }
    }
    // Select candle + show tooltip briefly
    final idx = widget.controller.xToIndex(d.localPosition.dx, _chartSize);
    widget.controller.selectCandle(idx);
    widget.controller.showCrosshairAt(d.localPosition);
    setState(() => _showTooltip = true);
    _tooltipTimer?.cancel();
    _tooltipTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        widget.controller.hideCrosshair();
        setState(() => _showTooltip = false);
      }
    });
  }

  void _updateCrosshair(Offset localPos) {
    if (_chartSize == Size.zero) return;
    final idx = widget.controller.xToIndex(localPos.dx, _chartSize);
    widget.controller.selectCandle(idx);
    widget.controller.showCrosshairAt(localPos);
    setState(() {});
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && _chartSize != Size.zero) {
      // Claim the event so the outer CustomScrollView doesn't also scroll
      GestureBinding.instance.pointerSignalResolver.register(event, (event) {
        if (event is PointerScrollEvent) {
          final scaleFactor = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
          widget.controller.zoom(scaleFactor, event.localPosition.dx, _chartSize);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Listener(
        onPointerSignal: _onPointerSignal,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          onLongPressStart: _onLongPressStart,
          onLongPressMoveUpdate: _onLongPressMoveUpdate,
          onLongPressEnd: _onLongPressEnd,
          onTapUp: _onTapUp,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, widget.height);
              _chartSize = size;

              return Stack(
                children: [
                  // Layer 1: Candles + volume + RSI + MACD + axes
                  RepaintBoundary(
                    child: CustomPaint(
                      size: size,
                      painter: CandlestickPainter(
                        widget.controller,
                        rsiValues: widget.rsiValues,
                        macdLine: widget.macdLine,
                        signalLine: widget.signalLine,
                        histogram: widget.histogram,
                        showRSI: widget.showRSI,
                        showMACD: widget.showMACD,
                      ),
                    ),
                  ),
                  // Layer 2: Overlays (MA lines, Bollinger, S/R, patterns)
                  RepaintBoundary(
                    child: CustomPaint(
                      size: size,
                      painter: OverlayPainter(
                        widget.controller,
                        widget.overlays,
                        showRSI: widget.showRSI,
                        showMACD: widget.showMACD,
                      ),
                    ),
                  ),
                  // Layer 3: OHLCV Tooltip
                  if (_showTooltip)
                    ChartTooltip(
                      controller: widget.controller,
                      chartSize: size,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
