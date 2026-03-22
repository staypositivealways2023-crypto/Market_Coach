import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../controllers/chart_controller.dart';

class RsiPainter extends CustomPainter {
  final ChartController controller;
  final List<double?> rsiValues;

  RsiPainter(this.controller, this.rsiValues) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    if (rsiValues.isEmpty) return;

    final bgPaint = Paint()..color = const Color(0xFF0D1117);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Overbought/oversold lines
    final obY = size.height - (70 / 100) * size.height;
    final osY = size.height - (30 / 100) * size.height;

    void drawDashed(Canvas c, double y, Color color) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 0.5;
      double x = 0;
      while (x < size.width) {
        c.drawLine(Offset(x, y), Offset(x + 5, y), paint);
        x += 9;
      }
    }

    drawDashed(canvas, obY, Colors.red.withValues(alpha: 0.5));
    drawDashed(canvas, osY, Colors.green.withValues(alpha: 0.5));

    // RSI line
    final startIdx = controller.viewportStart.floor().clamp(0, controller.candles.length - 1);
    final endIdx = controller.viewportEnd.ceil().clamp(0, controller.candles.length);

    final paint = Paint()
      ..color = Colors.purple
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    bool started = false;

    for (int i = startIdx; i < endIdx; i++) {
      if (i >= rsiValues.length) break;
      final val = rsiValues[i];
      if (val == null) {
        started = false;
        continue;
      }
      final cw = controller.candleWidth(size);
      final x = (i - controller.viewportStart + 0.5) * cw;
      final y = size.height - (val / 100) * size.height;

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);

    // Crosshair
    if (controller.showCrosshair) {
      final crosshairPaint = Paint()
        ..color = Colors.white24
        ..strokeWidth = 0.5;
      canvas.drawLine(
        Offset(controller.crosshairPosition.dx, 0),
        Offset(controller.crosshairPosition.dx, size.height),
        crosshairPaint,
      );
    }

    // Labels
    _drawLabel(canvas, size, obY, '70');
    _drawLabel(canvas, size, osY, '30');

    // Current RSI value
    if (endIdx > startIdx && endIdx <= rsiValues.length) {
      for (int i = endIdx - 1; i >= startIdx; i--) {
        if (i < rsiValues.length && rsiValues[i] != null) {
          final val = rsiValues[i]!;
          final tp = TextPainter(
            text: TextSpan(
              text: val.toStringAsFixed(1),
              style: TextStyle(
                color: val >= 70 ? Colors.red : val <= 30 ? Colors.green : Colors.purple,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: ui.TextDirection.ltr,
          )..layout();
          tp.paint(canvas, const Offset(4, 4));
          break;
        }
      }
    }

    // RSI label
    final labelTp = TextPainter(
      text: const TextSpan(
        text: 'RSI 14',
        style: TextStyle(color: Colors.purple, fontSize: 9, fontWeight: FontWeight.w600),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    labelTp.paint(canvas, Offset(size.width - labelTp.width - 4, 4));
  }

  void _drawLabel(Canvas canvas, Size size, double y, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Color(0x61FFFFFF), fontSize: 8),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width - tp.width - 2, y - tp.height));
  }

  @override
  bool shouldRepaint(RsiPainter oldDelegate) => true;
}

class MacdPainter extends CustomPainter {
  final ChartController controller;
  final List<double?> macdLine;
  final List<double?> signalLine;
  final List<double?> histogram;

  MacdPainter(this.controller, this.macdLine, this.signalLine, this.histogram)
      : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    if (macdLine.isEmpty) return;

    final bgPaint = Paint()..color = const Color(0xFF0D1117);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final startIdx = controller.viewportStart.floor().clamp(0, controller.candles.length - 1);
    final endIdx = controller.viewportEnd.ceil().clamp(0, controller.candles.length);

    // Compute range
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

    final range = (maxVal - minVal);
    if (range == 0) return;

    final padding = range * 0.1;
    final low = minVal - padding;
    final high = maxVal + padding;
    final totalRange = high - low;

    double yForVal(double val) => size.height - ((val - low) / totalRange) * size.height;
    final cw = controller.candleWidth(size);
    final zeroY = yForVal(0);

    // Zero line
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.2)
        ..strokeWidth = 0.5,
    );

    // Histogram bars
    for (int i = startIdx; i < endIdx; i++) {
      if (i >= histogram.length) break;
      final val = histogram[i];
      if (val == null) continue;
      final x = (i - controller.viewportStart + 0.5) * cw;
      final y = yForVal(val);
      final barW = (cw * 0.6).clamp(1.0, double.infinity);
      canvas.drawRect(
        Rect.fromLTRB(x - barW / 2, min(y, zeroY), x + barW / 2, max(y, zeroY)),
        Paint()..color = (val >= 0 ? Colors.green : Colors.red).withValues(alpha: 0.6),
      );
    }

    // MACD line
    _drawLine(canvas, size, startIdx, endIdx, macdLine, Colors.blue, cw, yForVal);
    // Signal line (dashed)
    _drawDashedLine(canvas, size, startIdx, endIdx, signalLine, Colors.orange, cw, yForVal);

    // Crosshair
    if (controller.showCrosshair) {
      canvas.drawLine(
        Offset(controller.crosshairPosition.dx, 0),
        Offset(controller.crosshairPosition.dx, size.height),
        Paint()
          ..color = Colors.white24
          ..strokeWidth = 0.5,
      );
    }

    // Label
    final labelTp = TextPainter(
      text: const TextSpan(
        text: 'MACD 12 26 9',
        style: TextStyle(color: Color(0xFF90CAF9), fontSize: 9, fontWeight: FontWeight.w600),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    labelTp.paint(canvas, Offset(size.width - labelTp.width - 4, 4));
  }

  void _drawLine(
    Canvas canvas,
    Size size,
    int startIdx,
    int endIdx,
    List<double?> values,
    Color color,
    double cw,
    double Function(double) yForVal,
  ) {
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
      final x = (i - controller.viewportStart + 0.5) * cw;
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

  void _drawDashedLine(
    Canvas canvas,
    Size size,
    int startIdx,
    int endIdx,
    List<double?> values,
    Color color,
    double cw,
    double Function(double) yForVal,
  ) {
    // Simple dashed implementation — draw short segments
    double? lastX, lastY;
    int segCount = 0;
    for (int i = startIdx; i < endIdx; i++) {
      if (i >= values.length) break;
      final val = values[i];
      if (val == null) {
        lastX = null;
        lastY = null;
        continue;
      }
      final x = (i - controller.viewportStart + 0.5) * cw;
      final y = yForVal(val);
      if (lastX != null && lastY != null && segCount % 2 == 0) {
        canvas.drawLine(
          Offset(lastX, lastY),
          Offset(x, y),
          Paint()
            ..color = color
            ..strokeWidth = 1.5,
        );
      }
      lastX = x;
      lastY = y;
      segCount++;
    }
  }

  @override
  bool shouldRepaint(MacdPainter oldDelegate) => true;
}
