import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../controllers/chart_controller.dart';
import '../models/chart_overlay.dart';

class OverlayPainter extends CustomPainter {
  final ChartController controller;
  final OverlayData overlays;
  final bool showRSI;
  final bool showMACD;

  static const _rightPad = 52.0;

  OverlayPainter(this.controller, this.overlays,
      {this.showRSI = false, this.showMACD = false})
      : super(repaint: controller);

  double _chartH(Size s) {
    if (showRSI && showMACD) return s.height * 0.52;
    if (showRSI || showMACD) return s.height * 0.64;
    return s.height * 0.80;
  }

  Size _drawSize(Size s) => Size(s.width - _rightPad, s.height);

  @override
  void paint(Canvas canvas, Size size) {
    if (controller.candles.isEmpty) return;

    final chartH = _chartH(size);
    final (visLow, visHigh) = controller.priceRangeForVisible();
    final priceRange = visHigh - visLow;
    if (priceRange <= 0) return;

    double yForPrice(double price) {
      return chartH - ((price - visLow) / priceRange) * chartH;
    }

    final startIdx = controller.viewportStart.floor().clamp(0, controller.candles.length - 1);
    final chartRect = Rect.fromLTWH(0, 0, size.width, chartH);
    canvas.save();
    canvas.clipRect(chartRect);

    // Draw MA lines
    for (final ma in overlays.maLines) {
      _drawMALine(canvas, size, startIdx, ma, yForPrice);
    }

    // Draw Bollinger bands
    if (overlays.bollinger != null) {
      _drawBollinger(canvas, size, startIdx, overlays.bollinger!, yForPrice, chartH);
    }

    // Draw S/R lines
    for (final sr in overlays.srLines) {
      _drawSRLine(canvas, size, sr, yForPrice);
    }

    canvas.restore();

    // Draw pattern markers (outside clip for labels)
    _drawPatternMarkers(canvas, size, startIdx, yForPrice);
  }

  void _drawMALine(Canvas canvas, Size size, int startIdx, MALine ma, double Function(double) yForPrice) {
    final paint = Paint()
      ..color = ma.color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    bool started = false;

    for (int i = 0; i < controller.candles.length; i++) {
      if (i < startIdx) continue;
      final visIdx = i - startIdx;
      if (visIdx >= (controller.viewportEnd - controller.viewportStart).ceil() + 2) break;

      if (i >= ma.values.length) break;
      final val = ma.values[i];
      if (val == null) {
        started = false;
        continue;
      }

      final x = controller.indexToX(i, _drawSize(size));
      final y = yForPrice(val);

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _drawBollinger(Canvas canvas, Size size, int startIdx, BollingerData bb, double Function(double) yForPrice, double chartH) {
    final linePaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    final upperPath = Path();
    final lowerPath = Path();
    bool started = false;

    for (int i = 0; i < controller.candles.length; i++) {
      if (i < startIdx) continue;
      if (i >= bb.upper.length || i >= bb.lower.length) break;

      final upper = bb.upper[i];
      final lower = bb.lower[i];
      if (upper == null || lower == null) {
        started = false;
        continue;
      }

      final x = controller.indexToX(i, _drawSize(size));
      if (!started) {
        upperPath.moveTo(x, yForPrice(upper));
        lowerPath.moveTo(x, yForPrice(lower));
        started = true;
      } else {
        upperPath.lineTo(x, yForPrice(upper));
        lowerPath.lineTo(x, yForPrice(lower));
      }
    }

    // Fill between upper and lower
    final fillPath = Path.from(upperPath);
    // Reverse lower path
    final lowerPoints = <Offset>[];
    for (int i = startIdx; i < min(bb.lower.length, controller.candles.length); i++) {
      final lower = bb.lower[i];
      if (lower == null) continue;
      lowerPoints.add(Offset(controller.indexToX(i, _drawSize(size)), yForPrice(lower)));
    }
    if (lowerPoints.isNotEmpty) {
      fillPath.lineTo(lowerPoints.last.dx, lowerPoints.last.dy);
      for (int i = lowerPoints.length - 2; i >= 0; i--) {
        fillPath.lineTo(lowerPoints[i].dx, lowerPoints[i].dy);
      }
      fillPath.close();
      canvas.drawPath(fillPath, fillPaint);
    }

    canvas.drawPath(upperPath, linePaint);
    canvas.drawPath(lowerPath, linePaint);
  }

  void _drawSRLine(Canvas canvas, Size size, SRLine sr, double Function(double) yForPrice) {
    final y = yForPrice(sr.price);
    final paint = Paint()
      ..color = sr.color
      ..strokeWidth = 1.0;

    // Draw dashed line
    double x = 0;
    const dashLen = 6.0;
    const gapLen = 4.0;
    while (x < size.width - _rightPad - 4) {
      canvas.drawLine(Offset(x, y), Offset(x + dashLen, y), paint);
      x += dashLen + gapLen;
    }

    // Label badge
    final tp = TextPainter(
      text: TextSpan(
        text: sr.label,
        style: TextStyle(color: sr.color, fontSize: 9, fontWeight: FontWeight.w600),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final bgRect = Rect.fromLTWH(
      size.width - tp.width - 12,
      y - tp.height / 2 - 2,
      tp.width + 8,
      tp.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
      Paint()..color = sr.color.withValues(alpha: 0.15),
    );
    tp.paint(canvas, Offset(size.width - tp.width - 8, y - tp.height / 2));
  }

  void _drawPatternMarkers(Canvas canvas, Size size, int startIdx, double Function(double) yForPrice) {
    // Clear existing hit targets
    controller.patternHitTargets.clear();

    final patterns = overlays.patterns;
    if (patterns == null) return;

    // Access patterns list via dynamic
    List<dynamic>? patternList;
    try {
      patternList = patterns.patterns as List<dynamic>;
    } catch (_) {
      return;
    }
    if (patternList.isEmpty) return;

    for (final pat in patternList) {
      try {
        final formedIdx = pat.formedAtIndex as int;
        // Draw at formedAtIndex (most recent)
        if (formedIdx < 0 || formedIdx < startIdx || formedIdx >= controller.candles.length) continue;

        final candle = controller.candles[formedIdx];
        final x = controller.indexToX(formedIdx, _drawSize(size));
        final y = yForPrice(candle.high) - 14;

        // Circle marker
        final circlePaint = Paint()
          ..color = Colors.orangeAccent.withValues(alpha: 0.15)
          ..style = PaintingStyle.fill;
        final borderPaint = Paint()
          ..color = Colors.orangeAccent
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;

        canvas.drawCircle(Offset(x, y), 10, circlePaint);
        canvas.drawCircle(Offset(x, y), 10, borderPaint);

        // Label (2 char abbreviation)
        final abbr = _abbreviate(pat.type as String);
        final tp = TextPainter(
          text: TextSpan(
            text: abbr,
            style: const TextStyle(color: Colors.orangeAccent, fontSize: 7, fontWeight: FontWeight.w700),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));

        // Register hit target
        controller.patternHitTargets.add(
          PatternHitTarget(
            Rect.fromCircle(center: Offset(x, y), radius: 14),
            pat,  // ChartPatternResult stored as dynamic
          ),
        );
      } catch (_) {
        continue;
      }
    }
  }

  String _abbreviate(String type) {
    const abbrevs = {
      'DOUBLE_TOP': 'DT',
      'DOUBLE_BOTTOM': 'DB',
      'HEAD_SHOULDERS': 'HS',
      'INV_HEAD_SHOULDERS': 'IH',
      'ASCENDING_TRIANGLE': 'AT',
      'DESCENDING_TRIANGLE': 'DT',
      'BULL_FLAG': 'BF',
      'BEAR_FLAG': 'BF',
      'DOJI': 'DO',
      'HAMMER': 'HA',
      'ENGULFING': 'EN',
      'MORNING_STAR': 'MS',
      'EVENING_STAR': 'ES',
    };
    for (final entry in abbrevs.entries) {
      if (type.contains(entry.key)) return entry.value;
    }
    return type.substring(0, min(2, type.length));
  }

  @override
  bool shouldRepaint(OverlayPainter oldDelegate) => true;
}
