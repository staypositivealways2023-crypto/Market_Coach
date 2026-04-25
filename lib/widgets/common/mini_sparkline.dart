import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Tiny sparkline chart for watchlist rows and market pulse tiles.
///
/// Renders a smoothed line with an optional gradient fill underneath.
/// The color is derived from the first-to-last delta so the glyph communicates
/// direction at a glance without needing a label.
class MiniSparkline extends StatelessWidget {
  final List<double> values;
  final Color? color;
  final bool filled;
  final double strokeWidth;
  final Size size;

  const MiniSparkline({
    super.key,
    required this.values,
    this.color,
    this.filled = true,
    this.strokeWidth = 1.6,
    this.size = const Size(72, 32),
  });

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox.fromSize(size: size);
    }

    final auto = values.last >= values.first
        ? AppColors.bullish
        : AppColors.bearish;
    final c = color ?? auto;

    return CustomPaint(
      size: size,
      painter: _SparklinePainter(values, c, strokeWidth, filled),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double strokeWidth;
  final bool filled;

  _SparklinePainter(this.values, this.color, this.strokeWidth, this.filled);

  @override
  void paint(Canvas canvas, Size size) {
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);

    // Convert values to normalized (0..1) then to canvas coords.
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final norm = (values[i] - minV) / range;
      final y = size.height - (norm * (size.height - strokeWidth)) -
          (strokeWidth / 2);
      points.add(Offset(x, y));
    }

    // Smooth line via catmull-rom style midpoints.
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
      linePath.quadraticBezierTo(p1.dx, p1.dy, mid.dx, mid.dy);
    }
    linePath.lineTo(points.last.dx, points.last.dy);

    if (filled) {
      final fillPath = Path.from(linePath)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.28), color.withOpacity(0.0)],
        ).createShader(Offset.zero & size);
      canvas.drawPath(fillPath, fillPaint);
    }

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values != values ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.filled != filled;
}
