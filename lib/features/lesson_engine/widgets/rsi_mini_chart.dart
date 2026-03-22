import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// ─── Shared mini RSI chart ────────────────────────────────────────────────────
// Lightweight CustomPainter-based RSI chart used in ChartHighlightStep.
// No dependency on the main chart infrastructure.

const _kLineColor = Color(0xFF26A69A);
const _kOverboughtColor = Color(0xFFEF5350);
const _kOversoldColor = Color(0xFF4CAF50);

class RsiMiniChart extends StatelessWidget {
  final List<double> rsiValues; // 0–100
  final bool highlightOverbought;
  final bool highlightOversold;
  final double height;

  const RsiMiniChart({
    super.key,
    required this.rsiValues,
    this.highlightOverbought = false,
    this.highlightOversold = false,
    this.height = 110,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _RsiMiniPainter(
          rsiValues: rsiValues,
          highlightOverbought: highlightOverbought,
          highlightOversold: highlightOversold,
        ),
      ),
    );
  }
}

class _RsiMiniPainter extends CustomPainter {
  final List<double> rsiValues;
  final bool highlightOverbought;
  final bool highlightOversold;

  const _RsiMiniPainter({
    required this.rsiValues,
    required this.highlightOverbought,
    required this.highlightOversold,
  });

  double _y(double rsi, double height) => height * (1.0 - rsi / 100.0);

  @override
  void paint(Canvas canvas, Size size) {
    const rightPad = 32.0;
    final w = size.width - rightPad;
    final h = size.height;

    // Background
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF111925),
    );

    // Zone highlights
    if (highlightOverbought) {
      final rect = Rect.fromLTRB(0, _y(100, h), w, _y(70, h));
      canvas.drawRect(
        rect,
        Paint()..color = _kOverboughtColor.withValues(alpha: 0.12),
      );
    }
    if (highlightOversold) {
      final rect = Rect.fromLTRB(0, _y(30, h), w, _y(0, h));
      canvas.drawRect(
        rect,
        Paint()..color = _kOversoldColor.withValues(alpha: 0.12),
      );
    }

    // Dashed reference lines
    void drawDashed(double rsi, Color color) {
      final y = _y(rsi, h);
      final paint = Paint()
        ..color = color.withValues(alpha: 0.55)
        ..strokeWidth = 0.7;
      double x = 0;
      while (x < w) {
        canvas.drawLine(Offset(x, y), Offset(x + 5, y), paint);
        x += 9;
      }
    }

    drawDashed(70, _kOverboughtColor);
    drawDashed(30, _kOversoldColor);

    // RSI line
    if (rsiValues.length < 2) return;
    final path = Path();
    final step = w / (rsiValues.length - 1);
    for (int i = 0; i < rsiValues.length; i++) {
      final x = i * step;
      final y = _y(rsiValues[i], h);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = _kLineColor
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Y-axis labels (70 and 30)
    void drawLabel(double rsi, Color color) {
      final y = _y(rsi, h);
      final tp = TextPainter(
        text: TextSpan(
          text: rsi.toStringAsFixed(0),
          style: TextStyle(
              color: color.withValues(alpha: 0.8), fontSize: 9),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(w + 4, y - tp.height / 2));
    }

    drawLabel(70, _kOverboughtColor);
    drawLabel(30, _kOversoldColor);
  }

  @override
  bool shouldRepaint(_RsiMiniPainter old) =>
      old.rsiValues != rsiValues ||
      old.highlightOverbought != highlightOverbought ||
      old.highlightOversold != highlightOversold;
}
