import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/demo_models.dart';

// ─── IndicatorDemoPainter ─────────────────────────────────────────────────────
// CustomPainter for a price line + indicator overlay.
// Supports MA, MACD, Bollinger, and MA Crossover modes.

class IndicatorDemoPainter extends CustomPainter {
  final IndicatorDemoType demoType;
  final List<double> priceData;
  final List<double>? line1;       // MA fast / MACD line / Bollinger upper
  final List<double>? line2;       // MA slow / Signal line / Bollinger lower
  final List<double>? line3;       // Bollinger mid
  final List<double>? histogram;   // MACD histogram bars
  final List<IndicatorAnnotation> annotations;

  static const _bgColor = Color(0xFF111925);
  static const _priceColor = Color(0xFF90CAF9);
  static const _line1Color = Color(0xFF26A69A);   // fast MA / MACD / upper BB
  static const _line2Color = Color(0xFFEF9A9A);   // slow MA / signal / lower BB
  static const _line3Color = Color(0xFFB0BEC5);   // mid BB
  static const _bullHistColor = Color(0xFF4CAF50);
  static const _bearHistColor = Color(0xFFEF5350);
  static const _gridColor = Color(0x18FFFFFF);

  const IndicatorDemoPainter({
    required this.demoType,
    required this.priceData,
    this.line1,
    this.line2,
    this.line3,
    this.histogram,
    this.annotations = const [],
  });

  double _toY(double value, double minV, double range, double top, double h) {
    if (range == 0) return top + h / 2;
    return top + (1.0 - (value - minV) / range) * h;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (priceData.isEmpty) return;

    canvas.drawRect(Offset.zero & size, Paint()..color = _bgColor);

    // ── Layout: MACD uses 2-panel split ────────────────────────────────────
    final bool hasMacdPanel = demoType == IndicatorDemoType.macd;
    final double priceH = hasMacdPanel ? size.height * 0.58 : size.height;
    const double leftPad = 4.0;
    const double rightPad = 4.0;
    const double topPad = 8.0;
    final double bottomPad = hasMacdPanel ? 0 : 4.0;
    final double chartW = size.width - leftPad - rightPad;

    // ── Price panel ────────────────────────────────────────────────────────
    final List<List<double>> allPriceSeries = [
      priceData,
      if (line1 != null) line1!,
      if (line2 != null) line2!,
      if (line3 != null) line3!,
    ];
    double minP = allPriceSeries.expand((l) => l).reduce((a, b) => a < b ? a : b);
    double maxP = allPriceSeries.expand((l) => l).reduce((a, b) => a > b ? a : b);
    final pad = (maxP - minP) * 0.08;
    minP -= pad;
    maxP += pad;
    final priceRange = maxP - minP;

    final double pTop = topPad;
    final double pH = priceH - topPad - (hasMacdPanel ? 4.0 : bottomPad);

    // Grid
    final gridPaint = Paint()..color = _gridColor..strokeWidth = 0.5;
    for (int i = 1; i < 3; i++) {
      canvas.drawLine(
        Offset(leftPad, pTop + i * pH / 3),
        Offset(leftPad + chartW, pTop + i * pH / 3),
        gridPaint,
      );
    }

    // Draw a line series
    void drawLine(List<double>? data, Color color, {double strokeWidth = 1.5, bool dashed = false}) {
      if (data == null || data.length < 2) return;
      final step = chartW / (data.length - 1);
      final paint = Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (!dashed) {
        final path = Path();
        for (int i = 0; i < data.length; i++) {
          final x = leftPad + i * step;
          final y = _toY(data[i], minP, priceRange, pTop, pH);
          if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
        }
        canvas.drawPath(path, paint);
      } else {
        for (int i = 0; i < data.length - 1; i++) {
          if (i.isOdd) continue;
          final x1 = leftPad + i * step;
          final y1 = _toY(data[i], minP, priceRange, pTop, pH);
          final x2 = leftPad + (i + 1) * step;
          final y2 = _toY(data[i + 1], minP, priceRange, pTop, pH);
          canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
        }
      }
    }

    // Bollinger band fill
    if (demoType == IndicatorDemoType.bollinger && line1 != null && line2 != null) {
      final len = priceData.length;
      final step = chartW / (len - 1);
      final fillPath = Path();
      for (int i = 0; i < len; i++) {
        final x = leftPad + i * step;
        final y = _toY(line1![i], minP, priceRange, pTop, pH);
        if (i == 0) fillPath.moveTo(x, y); else fillPath.lineTo(x, y);
      }
      for (int i = len - 1; i >= 0; i--) {
        final x = leftPad + i * step;
        final y = _toY(line2![i], minP, priceRange, pTop, pH);
        fillPath.lineTo(x, y);
      }
      fillPath.close();
      canvas.drawPath(fillPath, Paint()..color = _line1Color.withValues(alpha: 0.07)..style = PaintingStyle.fill);
    }

    // Draw indicator lines
    drawLine(line1, _line1Color);
    drawLine(line2, _line2Color);
    drawLine(line3, _line3Color, dashed: true);

    // Price line (on top)
    drawLine(priceData, _priceColor, strokeWidth: 2.0);

    // MA crossover markers
    if (demoType == IndicatorDemoType.macross && line1 != null && line2 != null) {
      final len = line1!.length;
      final step = chartW / (len - 1);
      for (int i = 1; i < len; i++) {
        final crossed = (line1![i - 1] < line2![i - 1] && line1![i] >= line2![i]) ||
            (line1![i - 1] > line2![i - 1] && line1![i] <= line2![i]);
        if (!crossed) continue;
        final x = leftPad + i * step;
        final y = _toY(line1![i], minP, priceRange, pTop, pH);
        final isGolden = line1![i] >= line2![i];
        final color = isGolden ? _line1Color : _line2Color;
        canvas.drawCircle(Offset(x, y), 4, Paint()..color = color);
        // Small label
        final tp = TextPainter(
          text: TextSpan(
            text: isGolden ? '↑' : '↓',
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, y - 18));
      }
    }

    // ── Annotations on price panel ────────────────────────────────────────
    for (final ann in annotations) {
      if (ann.index >= priceData.length) continue;
      final step = chartW / (priceData.length - 1);
      final x = leftPad + ann.index * step;
      final y = _toY(priceData[ann.index], minP, priceRange, pTop, pH);
      canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = ann.color);
      final tp = TextPainter(
        text: TextSpan(
          text: ann.label,
          style: TextStyle(color: ann.color, fontSize: 9, fontWeight: FontWeight.w600),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - 16));
    }

    if (!hasMacdPanel) return;

    // ── MACD sub-panel ────────────────────────────────────────────────────
    if (histogram == null) return;
    final double mTop = priceH + 6;
    final double mH = size.height - mTop - 4;
    final hist = histogram!;

    // Grid line at zero
    final zeroY = mTop + mH / 2;
    canvas.drawLine(Offset(leftPad, zeroY), Offset(leftPad + chartW, zeroY), gridPaint);

    // Histogram
    final double maxAbs = hist.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);
    final hStep = chartW / hist.length;
    final barW = hStep * 0.7;
    for (int i = 0; i < hist.length; i++) {
      final x = leftPad + (i + 0.5) * hStep;
      final normalized = maxAbs == 0 ? 0.0 : hist[i] / maxAbs;
      final barH = (mH / 2 * normalized.abs()).clamp(1.0, mH / 2);
      final y = normalized >= 0 ? zeroY - barH : zeroY;
      canvas.drawRect(
        Rect.fromLTWH(x - barW / 2, y, barW, barH),
        Paint()..color = normalized >= 0 ? _bullHistColor.withValues(alpha: 0.8) : _bearHistColor.withValues(alpha: 0.8),
      );
    }

    // MACD line (line1) and signal (line2) in sub-panel
    void drawMacdLine(List<double>? data, Color color) {
      if (data == null || data.length < 2) return;
      final minV = data.reduce((a, b) => a < b ? a : b) - 0.1;
      final maxV = data.reduce((a, b) => a > b ? a : b) + 0.1;
      final range = maxV - minV;
      final step = chartW / (data.length - 1);
      final paint = Paint()..color = color..strokeWidth = 1.2..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
      final path = Path();
      for (int i = 0; i < data.length; i++) {
        final x = leftPad + i * step;
        final y = _toY(data[i], minV, range, mTop, mH);
        if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }

    drawMacdLine(line1, _line1Color);
    drawMacdLine(line2, _line2Color);

    // "MACD" label
    final labelTp = TextPainter(
      text: const TextSpan(
        text: 'MACD',
        style: TextStyle(color: Color(0x66FFFFFF), fontSize: 8, fontWeight: FontWeight.w600, letterSpacing: 0.5),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    labelTp.paint(canvas, Offset(leftPad + 2, mTop + 2));
  }

  @override
  bool shouldRepaint(IndicatorDemoPainter old) => false;
}
