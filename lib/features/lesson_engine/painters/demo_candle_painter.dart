import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/demo_models.dart';

// ─── DemoCandlePainter ────────────────────────────────────────────────────────
// Lightweight CustomPainter for mini candlestick charts inside lesson steps.
// Supports S/R lines, colour-coded annotations, and per-candle tap feedback.

class DemoCandlePainter extends CustomPainter {
  final List<DemoCandle> candles;
  final List<CandleAnnotation> annotations;
  final bool highlightBullish;
  final bool highlightBearish;
  final double? supportLevel;
  final double? resistanceLevel;

  // ST-3 (TapOnChart) state
  final int? tappedIndex;
  final bool? tapCorrect;       // true=green, false=red, null=no feedback
  final bool revealAnnotations; // show revealAnnotations after correct tap

  static const _bgColor = Color(0xFF111925);
  static const _bullishColor = Color(0xFF26A69A);
  static const _bearishColor = Color(0xFFEF5350);
  static const _wickColor = Color(0xFF607D8B);
  static const _gridColor = Color(0x18FFFFFF);
  // ignore: unused_field
  static const _srColor = Color(0xFFFFB74D);
  static const _topPad = 36.0;    // space for annotations above chart
  static const _bottomPad = 8.0;
  static const _leftPad = 4.0;
  static const _rightPad = 8.0;

  const DemoCandlePainter({
    required this.candles,
    this.annotations = const [],
    this.highlightBullish = false,
    this.highlightBearish = false,
    this.supportLevel,
    this.resistanceLevel,
    this.tappedIndex,
    this.tapCorrect,
    this.revealAnnotations = false,
  });

  // Price → Y coordinate
  double _priceToY(double price, double minP, double priceRange, double areaTop, double areaH) {
    if (priceRange == 0) return areaTop + areaH / 2;
    return areaTop + (1.0 - (price - minP) / priceRange) * areaH;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    // ── Layout ──────────────────────────────────────────────────────────────
    final chartW = size.width - _leftPad - _rightPad;
    final chartH = size.height - _topPad - _bottomPad;
    final areaTop = _topPad;

    // ── Price bounds ────────────────────────────────────────────────────────
    double minP = candles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    double maxP = candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    final pad = (maxP - minP) * 0.08;
    minP -= pad;
    maxP += pad;
    final priceRange = maxP - minP;

    // ── Background ──────────────────────────────────────────────────────────
    canvas.drawRect(Offset.zero & size, Paint()..color = _bgColor);

    // ── Grid lines ──────────────────────────────────────────────────────────
    final gridPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 0.5;
    for (int i = 1; i < 4; i++) {
      final y = areaTop + i * chartH / 4;
      canvas.drawLine(
        Offset(_leftPad, y),
        Offset(_leftPad + chartW, y),
        gridPaint,
      );
    }

    // ── S/R lines ───────────────────────────────────────────────────────────
    void drawSR(double price, Color color, String labelText) {
      final y = _priceToY(price, minP, priceRange, areaTop, chartH);
      final paint = Paint()
        ..color = color.withValues(alpha: 0.7)
        ..strokeWidth = 1.0;
      // Dashed line
      double x = _leftPad;
      while (x < _leftPad + chartW) {
        canvas.drawLine(Offset(x, y), Offset(x + 6, y), paint);
        x += 10;
      }
      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: labelText,
          style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(_leftPad + chartW - tp.width - 2, y - tp.height - 1));
    }

    if (supportLevel != null) drawSR(supportLevel!, const Color(0xFF4CAF50), 'Support');
    if (resistanceLevel != null) drawSR(resistanceLevel!, const Color(0xFFEF5350), 'Resistance');

    // ── Candles ─────────────────────────────────────────────────────────────
    final candleSlot = chartW / candles.length;
    final bodyW = candleSlot * 0.55;

    for (int i = 0; i < candles.length; i++) {
      final c = candles[i];
      final centerX = _leftPad + (i + 0.5) * candleSlot;
      final yHigh = _priceToY(c.high, minP, priceRange, areaTop, chartH);
      final yLow = _priceToY(c.low, minP, priceRange, areaTop, chartH);
      final yOpen = _priceToY(c.open, minP, priceRange, areaTop, chartH);
      final yClose = _priceToY(c.close, minP, priceRange, areaTop, chartH);

      // Determine candle color
      Color candleColor;
      if (tappedIndex == i) {
        candleColor = tapCorrect == true
            ? const Color(0xFF1DE9B6)
            : tapCorrect == false
                ? const Color(0xFFFF5252)
                : (c.isBullish ? _bullishColor : _bearishColor);
      } else if (highlightBullish && c.isBullish) {
        candleColor = _bullishColor.withValues(alpha: 0.85);
      } else if (highlightBearish && !c.isBullish) {
        candleColor = _bearishColor.withValues(alpha: 0.85);
      } else {
        candleColor = c.isBullish ? _bullishColor : _bearishColor;
      }

      // Glow for tapped candle
      if (tappedIndex == i && tapCorrect != null) {
        final glowPaint = Paint()
          ..color = candleColor.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(centerX, (yHigh + yLow) / 2),
            width: bodyW + 12,
            height: yLow - yHigh + 12,
          ),
          glowPaint,
        );
      }

      // Wick
      final wickPaint = Paint()
        ..color = _wickColor
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(centerX, yHigh), Offset(centerX, yLow), wickPaint);

      // Body
      final bodyTop = (yOpen < yClose) ? yOpen : yClose;
      final bodyBottom = (yOpen < yClose) ? yClose : yOpen;
      final bodyHeight = (bodyBottom - bodyTop).clamp(2.0, double.infinity);
      final bodyPaint = Paint()
        ..color = candleColor
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(centerX - bodyW / 2, bodyTop, bodyW, bodyHeight),
        bodyPaint,
      );
    }

    // ── Annotations ─────────────────────────────────────────────────────────
    final List<CandleAnnotation> effectiveAnnotations = revealAnnotations
        ? annotations
        : annotations.where((a) => a.index < candles.length).toList();

    for (final ann in effectiveAnnotations) {
      if (ann.index >= candles.length) continue;
      final c = candles[ann.index];
      final centerX = _leftPad + (ann.index + 0.5) * candleSlot;
      final yHigh = _priceToY(c.high, minP, priceRange, areaTop, chartH);
      final yLow = _priceToY(c.low, minP, priceRange, areaTop, chartH);

      // Text label
      final tp = TextPainter(
        text: TextSpan(
          text: ann.label,
          style: TextStyle(
            color: ann.color,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();

      if (ann.arrowUp) {
        // Label above chart (in _topPad area)
        final labelY = areaTop - tp.height - 10;
        tp.paint(canvas, Offset(centerX - tp.width / 2, labelY));
        // Arrow line from label to candle top
        final arrowPaint = Paint()
          ..color = ann.color.withValues(alpha: 0.7)
          ..strokeWidth = 1.0;
        canvas.drawLine(
          Offset(centerX, labelY + tp.height + 2),
          Offset(centerX, yHigh - 3),
          arrowPaint,
        );
        // Arrowhead
        canvas.drawLine(Offset(centerX, yHigh - 3), Offset(centerX - 3, yHigh + 4), arrowPaint);
        canvas.drawLine(Offset(centerX, yHigh - 3), Offset(centerX + 3, yHigh + 4), arrowPaint);
      } else {
        // Label below candle
        final labelY = yLow + 6;
        // Arrow from candle bottom down
        final arrowPaint = Paint()
          ..color = ann.color.withValues(alpha: 0.7)
          ..strokeWidth = 1.0;
        canvas.drawLine(
          Offset(centerX, yLow + 3),
          Offset(centerX, labelY - 2),
          arrowPaint,
        );
        tp.paint(canvas, Offset(centerX - tp.width / 2, labelY));
      }
    }
  }

  @override
  bool shouldRepaint(DemoCandlePainter old) {
    return old.tappedIndex != tappedIndex ||
        old.tapCorrect != tapCorrect ||
        old.revealAnnotations != revealAnnotations ||
        old.supportLevel != supportLevel ||
        old.resistanceLevel != resistanceLevel;
  }
}
