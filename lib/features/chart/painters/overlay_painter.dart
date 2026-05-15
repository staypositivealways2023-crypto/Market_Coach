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

    // Draw AI trade-plan levels (stop loss / price targets)
    for (final level in overlays.tradeLevels) {
      _drawTradeLevel(canvas, size, level, yForPrice);
    }

    // Draw VWAP line
    if (overlays.vwapLine != null && overlays.vwapLine!.isNotEmpty) {
      _drawVWAP(canvas, size, startIdx, overlays.vwapLine!, yForPrice);
    }

    // Draw current price horizontal line
    if (overlays.currentPriceLine != null) {
      _drawCurrentPriceLine(canvas, size, overlays.currentPriceLine!, yForPrice);
    }

    // Draw signal markers (buy ▲ / sell ▼) inside the chart clip
    if (overlays.signalMarkers.isNotEmpty) {
      _drawSignalMarkers(canvas, size, startIdx, yForPrice);
    }

    canvas.restore();

    // Draw pattern markers (outside clip for labels)
    _drawPatternMarkers(canvas, size, startIdx, yForPrice);
  }

  // ─── AI trade-plan level lines ──────────────────────────────────────────────

  void _drawTradeLevel(Canvas canvas, Size size, TradeLevel level,
      double Function(double) yForPrice) {
    final y = yForPrice(level.price);
    // Skip if out of visible range
    if (y < 0 || y > _chartH(size)) return;

    final baseAlpha = (level.alpha.clamp(0.0, 1.0) * 255).round();
    final lineColor = level.color.withAlpha((baseAlpha * 0.7).round());

    // Solid line across full draw width
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width - _rightPad, y),
      Paint()
        ..color = lineColor
        ..strokeWidth = 0.9,
    );

    // Left-edge label badge (doesn't collide with right-edge S/R labels)
    final tp = TextPainter(
      text: TextSpan(
        text: level.label,
        style: TextStyle(
          color: level.color.withAlpha(baseAlpha),
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    const pH = 5.0;
    const pV = 2.5;
    final bgRect = Rect.fromLTWH(
      2, y - tp.height / 2 - pV,
      tp.width + pH * 2, tp.height + pV * 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
      Paint()..color = level.color.withAlpha((baseAlpha * 0.18).round()),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
      Paint()
        ..color = level.color.withAlpha((baseAlpha * 0.45).round())
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke,
    );
    tp.paint(canvas, Offset(2 + pH, y - tp.height / 2));

    // Price value to the right of the badge
    final priceTp = TextPainter(
      text: TextSpan(
        text: _fmtPrice(level.price),
        style: TextStyle(
          color: level.color.withAlpha((baseAlpha * 0.8).round()),
          fontSize: 8,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    priceTp.paint(canvas,
        Offset(bgRect.right + 4, y - priceTp.height / 2));
  }

  static String _fmtPrice(double p) {
    if (p >= 10000) return '\$${p.toStringAsFixed(0)}';
    if (p >= 1)     return '\$${p.toStringAsFixed(2)}';
    return '\$${p.toStringAsFixed(4)}';
  }

  // ─── Signal markers (buy ▲ / sell ▼) ───────────────────────────────────────

  void _drawSignalMarkers(Canvas canvas, Size size, int startIdx,
      double Function(double) yForPrice) {
    const buyColor  = Color(0xFF00C896);  // teal-green
    const sellColor = Color(0xFFFF4D6A);  // red
    const arrowH    = 8.0;
    const arrowW    = 7.0;
    const gap       = 5.0; // pixels between candle wick tip and arrow

    final endIdx = controller.viewportEnd.ceil().clamp(0, controller.candles.length);

    for (final marker in overlays.signalMarkers) {
      final idx = marker.candleIndex;
      if (idx < startIdx || idx >= endIdx || idx >= controller.candles.length) continue;

      final candle = controller.candles[idx];
      final x      = controller.indexToX(idx, _drawSize(size));
      final alpha  = (marker.strength.clamp(0.4, 1.0) * 255).round();

      void drawArrow(Path path, Color color) {
        canvas.drawPath(path, Paint()..color = color.withAlpha((alpha * 0.22).round()));
        canvas.drawPath(path, Paint()
          ..color = color.withAlpha(alpha)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke);
      }

      if (marker.isBuy) {
        // ▲ below the candle low — apex closest to candle, base further below
        final apexY = yForPrice(candle.low) + gap;
        final baseY = apexY + arrowH;
        drawArrow(
          Path()
            ..moveTo(x,          apexY)   // apex (pointing up toward candle)
            ..lineTo(x - arrowW, baseY)   // bottom-left
            ..lineTo(x + arrowW, baseY)   // bottom-right
            ..close(),
          buyColor,
        );
      } else {
        // ▼ above the candle high — apex closest to candle, base further above
        final apexY = yForPrice(candle.high) - gap;
        final baseY = apexY - arrowH;
        drawArrow(
          Path()
            ..moveTo(x,          apexY)   // apex (pointing down toward candle)
            ..lineTo(x - arrowW, baseY)   // top-left
            ..lineTo(x + arrowW, baseY)   // top-right
            ..close(),
          sellColor,
        );
      }
    }
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

  // ─── VWAP ──────────────────────────────────────────────────────────────────

  void _drawVWAP(Canvas canvas, Size size, int startIdx, List<double?> vwap,
      double Function(double) yForPrice) {
    const vwapColor = Color(0xFF2196F3);
    final paint = Paint()
      ..color = vwapColor
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final path = Path();
    bool started = false;

    for (int i = 0; i < controller.candles.length; i++) {
      if (i < startIdx) continue;
      if (i >= vwap.length) break;
      final val = vwap[i];
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

    // Latest VWAP label at right edge
    double? lastVal;
    for (int i = min(vwap.length - 1, controller.candles.length - 1);
         i >= startIdx; i--) {
      if (i < vwap.length && vwap[i] != null) {
        lastVal = vwap[i];
        break;
      }
    }
    if (lastVal != null) {
      final y = yForPrice(lastVal);
      final label = lastVal >= 1
          ? 'VWAP ${lastVal.toStringAsFixed(2)}'
          : 'VWAP ${lastVal.toStringAsFixed(4)}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
              color: vwapColor, fontSize: 8, fontWeight: FontWeight.w700),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final bgRect = Rect.fromLTWH(
        size.width - tp.width - 10,
        y - tp.height / 2 - 2,
        tp.width + 6,
        tp.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
        Paint()..color = vwapColor.withValues(alpha: 0.15),
      );
      tp.paint(canvas, Offset(size.width - tp.width - 7, y - tp.height / 2));
    }
  }

  // ─── Current price line ─────────────────────────────────────────────────────

  void _drawCurrentPriceLine(Canvas canvas, Size size, double price,
      double Function(double) yForPrice) {
    const lineColor = Color(0xFF12A28C);
    final y = yForPrice(price);

    // Dashed line
    final paint = Paint()
      ..color = lineColor.withValues(alpha: 0.55)
      ..strokeWidth = 0.8;
    double x = 0;
    const dashLen = 5.0;
    const gapLen = 4.0;
    final maxX = size.width - _rightPad;
    while (x < maxX) {
      final end = (x + dashLen).clamp(0.0, maxX);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dashLen + gapLen;
    }

    // Price label badge
    final label = price >= 1
        ? '\$${price.toStringAsFixed(2)}'
        : '\$${price.toStringAsFixed(4)}';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
            color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    const pH = 4.0;
    const pV = 3.0;
    final bgRect = Rect.fromLTWH(
      size.width - tp.width - pH * 2 - 4,
      y - tp.height / 2 - pV,
      tp.width + pH * 2,
      tp.height + pV * 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
      Paint()..color = lineColor,
    );
    tp.paint(canvas, Offset(size.width - tp.width - pH - 4, y - tp.height / 2));
  }

  // ─── Pattern abbreviations ──────────────────────────────────────────────────

  String _abbreviate(String type) {
    final t = type.toLowerCase();
    if (t.contains('double_top') || t.contains('doubletop')) return 'DT';
    if (t.contains('double_bottom') || t.contains('doublebottom')) return 'DB';
    if (t.contains('head')) return 'HS';
    if (t.contains('triangle')) return 'TR';
    if (t.contains('wedge')) return 'WG';
    if (t.contains('flag')) return 'FL';
    if (t.contains('support')) return 'S';
    if (t.contains('resist')) return 'R';
    return type.isNotEmpty ? type.substring(0, min(2, type.length)).toUpperCase() : '??';
  }

  @override
  bool shouldRepaint(OverlayPainter oldDelegate) =>
      oldDelegate.overlays != overlays ||
      oldDelegate.showRSI != showRSI ||
      oldDelegate.showMACD != showMACD;
}
