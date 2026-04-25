import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/candle.dart';
import '../../../widgets/chart/chart_type_selector.dart';
import '../controllers/chart_controller.dart';

class CandlestickPainter extends CustomPainter {
  final ChartController controller;
  final List<double?> rsiValues;
  final List<double?> macdLine;
  final List<double?> signalLine;
  final List<double?> histogram;
  final bool showRSI;
  final bool showMACD;

  static const _bullColor = Color(0xFF26A69A);
  static const _bearColor = Color(0xFFEF5350);
  static const _rsiColor = Color(0xFF4CAF50);   // green RSI line
  static const _macdColor = Color(0xFFFFEB3B);  // yellow MACD line
  static const _signalColor = Color(0xFFEF5350); // red signal line
  static const _rightPad = 52.0; // right margin for Y-axis labels

  CandlestickPainter(
    this.controller, {
    this.rsiValues = const [],
    this.macdLine = const [],
    this.signalLine = const [],
    this.histogram = const [],
    this.showRSI = false,
    this.showMACD = false,
  }) : super(repaint: controller);

  // ─── Layout helpers ───────────────────────────────────────────────

  double _chartH(Size s) {
    if (showRSI && showMACD) return s.height * 0.52;
    if (showRSI || showMACD) return s.height * 0.64;
    return s.height * 0.80;
  }

  double _volH(Size s) {
    if (showRSI && showMACD) return s.height * 0.09;
    if (showRSI || showMACD) return s.height * 0.10;
    return s.height * 0.16;
  }

  double _subH(Size s) {
    if (showRSI && showMACD) return s.height * 0.195;
    return s.height * 0.26;
  }

  double _rsiTop(Size s) => _chartH(s) + _volH(s);
  double _macdTop(Size s) => showRSI ? _rsiTop(s) + _subH(s) : _rsiTop(s);

  // Effective drawing width (excludes right label margin)
  double _drawW(Size s) => s.width - _rightPad;

  double _candleW(Size s) {
    if (controller.viewportWidth == 0) return 8;
    return _drawW(s) / controller.viewportWidth;
  }

  double _indexToX(int i, Size s) =>
      (i - controller.viewportStart + 0.5) * _candleW(s);

  // ─── Main paint ─────────────────────────────────────────────────
  @override
  void paint(Canvas canvas, Size size) {
    if (controller.candles.isEmpty) return;

    final chartH = _chartH(size);
    final (visLow, visHigh) = controller.priceRangeForVisible();
    final priceRange = visHigh - visLow;
    if (priceRange <= 0) return;

    double yForPrice(double price) =>
        chartH - ((price - visLow) / priceRange) * chartH;

    final startIdx = controller.viewportStart
        .floor()
        .clamp(0, controller.candles.length - 1);
    final endIdx =
        controller.viewportEnd.ceil().clamp(0, controller.candles.length);
    final visible = controller.candles.sublist(startIdx, endIdx);
    final cw = _candleW(size);

    // ── Price area ──────────────────────────────────────────────────
    _drawGridlines(canvas, size, chartH, visLow, visHigh, yForPrice);
    _drawVolume(canvas, size, startIdx, visible, cw, chartH);

    if (controller.chartType == ChartType.line ||
        controller.chartType == ChartType.area) {
      _drawLineOrArea(canvas, size, startIdx, visible, cw, chartH, yForPrice);
    } else {
      _drawCandles(canvas, size, startIdx, visible, cw, yForPrice);
    }

    if (controller.showCrosshair) {
      _drawCrosshair(canvas, size, chartH, visLow, visHigh, yForPrice);
    }

    _drawYLabels(canvas, size, chartH, visLow, visHigh, yForPrice);
    _drawXLabels(canvas, size, startIdx, visible, cw, chartH);

    // ── RSI panel ───────────────────────────────────────────────────
    if (showRSI && rsiValues.isNotEmpty) {
      final rsiTop = _rsiTop(size);
      _drawDivider(canvas, size, rsiTop);
      _drawRSIPanel(canvas, size, rsiTop, _subH(size), startIdx, endIdx);
    }

    // ── MACD panel ──────────────────────────────────────────────────
    if (showMACD && macdLine.isNotEmpty) {
      final macdTop = _macdTop(size);
      _drawDivider(canvas, size, macdTop);
      _drawMACDPanel(canvas, size, macdTop, _subH(size), startIdx, endIdx, cw);
    }
  }

  // ─── Gridlines ──────────────────────────────────────────────────
  void _drawGridlines(Canvas canvas, Size size, double chartH, double visLow,
      double visHigh, double Function(double) yForPrice) {
    final paint = Paint()
      ..color = const Color(0x0FFFFFFF)
      ..strokeWidth = 0.5;
    for (int i = 1; i <= 5; i++) {
      final price = visLow + (visHigh - visLow) * i / 5;
      final y = yForPrice(price);
      canvas.drawLine(Offset(0, y), Offset(_drawW(size), y), paint);
    }
  }

  // ─── Volume ─────────────────────────────────────────────────────
  void _drawVolume(Canvas canvas, Size size, int startIdx, List<Candle> visible,
      double cw, double chartH) {
    if (visible.isEmpty) return;
    final maxVol = visible.map((c) => c.volume).reduce(max);
    if (maxVol <= 0) return;
    final volH = _volH(size);
    final volBottom = chartH + volH;
    for (int i = 0; i < visible.length; i++) {
      final c = visible[i];
      final x = _indexToX(startIdx + i, size);
      final barH = (c.volume / maxVol) * volH;
      final isBull = c.close >= c.open;
      final barW = (cw * 0.7).clamp(1.0, double.infinity);
      canvas.drawRect(
        Rect.fromLTWH(x - barW / 2, volBottom - barH, barW, barH),
        Paint()
          ..color = (isBull ? _bullColor : _bearColor).withValues(alpha: 0.40),
      );
    }
  }

  // ─── Candles ────────────────────────────────────────────────────
  void _drawCandles(Canvas canvas, Size size, int startIdx, List<Candle> visible,
      double cw, double Function(double) yForPrice) {
    final wickPaint = Paint()..strokeWidth = 1;
    final bodyPaint = Paint();
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, _drawW(size), _chartH(size)));
    for (int i = 0; i < visible.length; i++) {
      final c = visible[i];
      final x = _indexToX(startIdx + i, size);
      final isBull = c.close >= c.open;
      final color = isBull ? _bullColor : _bearColor;
      wickPaint.color = color;
      bodyPaint.color = color;
      canvas.drawLine(
          Offset(x, yForPrice(c.high)), Offset(x, yForPrice(c.low)), wickPaint);
      final bodyTop = yForPrice(max(c.open, c.close));
      var bodyBottom = yForPrice(min(c.open, c.close));
      if (bodyBottom - bodyTop < 1) bodyBottom = bodyTop + 1;
      final halfW = (cw * 0.4).clamp(1.0, 8.0);
      canvas.drawRect(
          Rect.fromLTRB(x - halfW, bodyTop, x + halfW, bodyBottom), bodyPaint);
    }
    canvas.restore();
  }

  // ─── Line / Area ────────────────────────────────────────────────
  void _drawLineOrArea(Canvas canvas, Size size, int startIdx, List<Candle> visible,
      double cw, double chartH, double Function(double) yForPrice) {
    if (visible.isEmpty) return;
    final path = Path();
    bool started = false;
    for (int i = 0; i < visible.length; i++) {
      final x = _indexToX(startIdx + i, size);
      final y = yForPrice(visible[i].close);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, _drawW(size), chartH));
    if (controller.chartType == ChartType.area) {
      final areaPath = Path.from(path);
      areaPath.lineTo(_indexToX(startIdx + visible.length - 1, size), chartH);
      areaPath.lineTo(_indexToX(startIdx, size), chartH);
      areaPath.close();
      canvas.drawPath(
        areaPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _bullColor.withValues(alpha: 0.3),
              _bullColor.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromLTWH(0, 0, _drawW(size), chartH))
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = _bullColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    canvas.restore();
  }

  // ─── Crosshair ──────────────────────────────────────────────────
  void _drawCrosshair(Canvas canvas, Size size, double chartH, double visLow,
      double visHigh, double Function(double) yForPrice) {
    final pos = controller.crosshairPosition;
    if (pos == Offset.zero) return;
    final paint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 0.5;
    // Vertical line spans entire chart (all panels)
    canvas.drawLine(Offset(pos.dx, 0), Offset(pos.dx, size.height), paint);
    // Horizontal line only in price area
    if (pos.dy <= chartH) {
      canvas.drawLine(Offset(0, pos.dy), Offset(_drawW(size), pos.dy), paint);
      final priceRange = visHigh - visLow;
      if (priceRange > 0) {
        final price = visHigh - (pos.dy / chartH) * priceRange;
        _drawPriceLabel(canvas, size, pos.dy, price);
      }
    }
  }

  void _drawPriceLabel(Canvas canvas, Size size, double y, double price) {
    final text = _formatPrice(price);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
            color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final bgRect = Rect.fromLTWH(
        size.width - tp.width - 10, y - tp.height / 2 - 2, tp.width + 8, tp.height + 4);
    canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
        Paint()..color = const Color(0xFF12A28C));
    tp.paint(canvas, Offset(size.width - tp.width - 6, y - tp.height / 2));
  }

  // ─── Y-axis labels ──────────────────────────────────────────────
  void _drawYLabels(Canvas canvas, Size size, double chartH, double visLow,
      double visHigh, double Function(double) yForPrice) {
    final priceRange = visHigh - visLow;
    for (int i = 0; i <= 5; i++) {
      final price = visLow + priceRange * i / 5;
      final y = yForPrice(price);
      if (y < 0 || y > chartH) continue;
      final tp = TextPainter(
        text: TextSpan(
            text: _formatPrice(price),
            style: const TextStyle(color: Color(0x61FFFFFF), fontSize: 9)),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(_drawW(size) + 3, y - tp.height));
    }
  }

  // ─── X-axis labels ──────────────────────────────────────────────
  void _drawXLabels(Canvas canvas, Size size, int startIdx, List<Candle> visible,
      double cw, double chartH) {
    if (visible.isEmpty) return;
    final duration = visible.last.time.difference(visible.first.time);
    String Function(DateTime) fmt;
    if (duration.inDays > 365) {
      fmt = (d) => DateFormat('MMM yy').format(d);
    } else if (duration.inDays > 30) {
      fmt = (d) => DateFormat('MMM d').format(d);
    } else if (duration.inDays > 1) {
      fmt = (d) => DateFormat('MM/dd').format(d);
    } else {
      fmt = (d) => DateFormat('HH:mm').format(d);
    }
    final labelEvery = max(1, (80 / cw).round());
    for (int i = 0; i < visible.length; i += labelEvery) {
      final x = _indexToX(startIdx + i, size);
      if (x < 0 || x > _drawW(size)) continue;
      final tp = TextPainter(
        text: TextSpan(
            text: fmt(visible[i].time),
            style: const TextStyle(color: Color(0x61FFFFFF), fontSize: 9)),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      // Place just above the vol/indicator divider
      tp.paint(canvas, Offset(x - tp.width / 2, chartH - tp.height - 2));
    }
  }

  // ─── Divider ────────────────────────────────────────────────────
  void _drawDivider(Canvas canvas, Size size, double y) {
    canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = Colors.white12
          ..strokeWidth = 0.5);
  }

  // ─── RSI Panel ──────────────────────────────────────────────────
  void _drawRSIPanel(Canvas canvas, Size size, double top, double panelH,
      int startIdx, int endIdx) {
    canvas.drawRect(
        Rect.fromLTWH(0, top, size.width, panelH),
        Paint()..color = const Color(0xFF0D1117));

    void drawRefLine(double rsiVal, Color color) {
      final y = top + panelH - (rsiVal / 100) * panelH;
      final paint = Paint()
        ..color = color.withValues(alpha: 0.5)
        ..strokeWidth = 0.5;
      double x = 0;
      while (x < _drawW(size)) {
        canvas.drawLine(Offset(x, y), Offset(x + 5, y), paint);
        x += 9;
      }
      final tp = TextPainter(
        text: TextSpan(
            text: rsiVal.toStringAsFixed(0),
            style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 8)),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(_drawW(size) + 3, y - tp.height / 2));
    }

    drawRefLine(70, Colors.redAccent);
    drawRefLine(30, Colors.greenAccent);

    // RSI line (green)
    final path = Path();
    bool started = false;
    for (int i = startIdx; i < endIdx; i++) {
      if (i >= rsiValues.length) break;
      final val = rsiValues[i];
      if (val == null) {
        started = false;
        continue;
      }
      final x = _indexToX(i, size);
      final y = top + panelH - (val / 100) * panelH;
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, top, _drawW(size), panelH));
    canvas.drawPath(
        path,
        Paint()
          ..color = _rsiColor
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke);
    canvas.restore();

    // Crosshair sync
    if (controller.showCrosshair) {
      canvas.drawLine(
          Offset(controller.crosshairPosition.dx, top),
          Offset(controller.crosshairPosition.dx, top + panelH),
          Paint()
            ..color = Colors.white24
            ..strokeWidth = 0.5);
    }

    // Current value label
    for (int i = endIdx - 1; i >= startIdx; i--) {
      if (i < rsiValues.length && rsiValues[i] != null) {
        final val = rsiValues[i]!;
        final labelColor =
            val >= 70 ? Colors.redAccent : val <= 30 ? Colors.greenAccent : _rsiColor;
        final tp = TextPainter(
          text: TextSpan(
              text: 'RSI ${val.toStringAsFixed(1)}',
              style: TextStyle(
                  color: labelColor, fontSize: 9, fontWeight: FontWeight.w600)),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(4, top + 4));
        break;
      }
    }
  }

  // ─── MACD Panel ─────────────────────────────────────────────────
  void _drawMACDPanel(Canvas canvas, Size size, double top, double panelH,
      int startIdx, int endIdx, double cw) {
    canvas.drawRect(
        Rect.fromLTWH(0, top, size.width, panelH),
        Paint()..color = const Color(0xFF0D1117));

    if (macdLine.isEmpty) return;

    // Compute value range for this viewport
    double minVal = 0, maxVal = 0;
    for (int i = startIdx; i < endIdx; i++) {
      if (i < macdLine.length && macdLine[i] != null) {
        minVal = min(minVal, macdLine[i]!);
        maxVal = max(maxVal, macdLine[i]!);
      }
      if (i < signalLine.length && signalLine[i] != null) {
        minVal = min(minVal, signalLine[i]!);
        maxVal = max(maxVal, signalLine[i]!);
      }
      if (i < histogram.length && histogram[i] != null) {
        minVal = min(minVal, histogram[i]!);
        maxVal = max(maxVal, histogram[i]!);
      }
    }
    final range = maxVal - minVal;
    if (range == 0) return;

    final pad = range * 0.1;
    final low = minVal - pad;
    final high = maxVal + pad;
    final totalRange = high - low;

    double yForVal(double val) =>
        top + panelH - ((val - low) / totalRange) * panelH;
    final zeroY = yForVal(0);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, top, _drawW(size), panelH));

    // Zero line
    canvas.drawLine(
        Offset(0, zeroY),
        Offset(_drawW(size), zeroY),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.2)
          ..strokeWidth = 0.5);

    // Histogram bars (bull/bear colors)
    for (int i = startIdx; i < endIdx; i++) {
      if (i >= histogram.length) break;
      final val = histogram[i];
      if (val == null) continue;
      final x = _indexToX(i, size);
      final y = yForVal(val);
      final barW = (cw * 0.6).clamp(1.0, double.infinity);
      canvas.drawRect(
          Rect.fromLTRB(x - barW / 2, min(y, zeroY), x + barW / 2, max(y, zeroY)),
          Paint()
            ..color = (val >= 0 ? _bullColor : _bearColor).withValues(alpha: 0.6));
    }

    // MACD line (yellow)
    _drawPanelLine(canvas, size, startIdx, endIdx, macdLine, _macdColor, yForVal);
    // Signal line (red)
    _drawPanelLine(canvas, size, startIdx, endIdx, signalLine, _signalColor, yForVal);

    canvas.restore();

    // Crosshair sync
    if (controller.showCrosshair) {
      canvas.drawLine(
          Offset(controller.crosshairPosition.dx, top),
          Offset(controller.crosshairPosition.dx, top + panelH),
          Paint()
            ..color = Colors.white24
            ..strokeWidth = 0.5);
    }

    // Label
    final tp = TextPainter(
      text: const TextSpan(
          text: 'MACD 12 26 9',
          style: TextStyle(
              color: Color(0xFFFFEB3B), fontSize: 9, fontWeight: FontWeight.w600)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(4, top + 4));
  }

  void _drawPanelLine(Canvas canvas, Size size, int startIdx, int endIdx,
      List<double?> values, Color color, double Function(double) yForVal) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path();
    bool started = false;
    for (int i = startIdx; i < endIdx; i++) {
      if (i >= values.length) break;
      final val = values[i];
      if (val == null) {
        started = false;
        continue;
      }
      final x = _indexToX(i, size);
      final y = yForVal(val);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  // ─── Helpers ────────────────────────────────────────────────────
  String _formatPrice(double price) {
    if (price < 1.0) return price.toStringAsFixed(4);
    if (price < 10000) return price.toStringAsFixed(2);
    return NumberFormat('#,##0', 'en_US').format(price.round());
  }

  @override
  bool shouldRepaint(CandlestickPainter oldDelegate) => true;
}
