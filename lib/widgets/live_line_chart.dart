import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/candle.dart';

/// Simple live-updating sparkline.
/// - If [candleStream] is provided: uses candle close prices
/// - Otherwise: random walk demo feed
class LiveLineChart extends StatefulWidget {
  final Color lineColor;
  final int maxPoints;
  final double start;
  final Stream<List<Candle>>? candleStream;
  final String? symbol;
  final bool isLive;

  const LiveLineChart({
    super.key,
    required this.lineColor,
    this.maxPoints = 40,
    this.start = 100,
    this.candleStream,
    this.symbol,
    this.isLive = false,
  });

  @override
  State<LiveLineChart> createState() => _LiveLineChartState();
}

class _LiveLineChartState extends State<LiveLineChart> {
  final _random = Random();
  Timer? _timer;
  List<double> _points = [];
  StreamSubscription<List<Candle>>? _candleSubscription;

  @override
  void initState() {
    super.initState();
    _resetPoints();
    _startDataSource();
  }

  @override
  void didUpdateWidget(covariant LiveLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If stream instance changed (interval changed), re-subscribe
    if (oldWidget.candleStream != widget.candleStream) {
      _stopDataSource();
      _resetPoints();
      _startDataSource();
    }
  }

  void _resetPoints() {
    _points = List.generate(widget.maxPoints ~/ 2, (_) => widget.start);
  }

  void _startDataSource() {
    if (widget.candleStream != null) {
      _candleSubscription = widget.candleStream!.listen((candles) {
        if (!mounted) return;
        if (candles.isEmpty) return;

        setState(() {
          _points = candles.map((c) => c.close).toList();
          if (_points.length > widget.maxPoints) {
            _points = _points.sublist(_points.length - widget.maxPoints);
          }
        });
      });
    } else {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  void _stopDataSource() {
    _timer?.cancel();
    _timer = null;
    _candleSubscription?.cancel();
    _candleSubscription = null;
  }

  void _tick() {
    if (!mounted) return;
    setState(() {
      final last = _points.isNotEmpty ? _points.last : widget.start;
      final next = last + (_random.nextDouble() - 0.5) * 2.2;
      _points.add(next);
      if (_points.length > widget.maxPoints) {
        _points.removeAt(0);
      }
    });
  }

  @override
  void dispose() {
    _stopDataSource();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_points.length < 2) return const SizedBox.shrink();

    final minY = _points.reduce(min);
    final maxY = _points.reduce(max);
    final range = (maxY - minY).abs() < 0.001 ? 1.0 : (maxY - minY);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 140,
          child: CustomPaint(
            painter: _LinePainter(
              points: _points,
              minY: minY,
              range: range,
              color: widget.lineColor,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: widget.lineColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.candleStream != null
              ? (widget.isLive
                  ? 'Live Binance (${widget.symbol}) • \$${_points.last.toStringAsFixed(2)}'
                  : '${widget.symbol ?? ''} • \$${_points.last.toStringAsFixed(2)}')
              : 'Live demo feed • ${_points.last.toStringAsFixed(2)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<double> points;
  final double minY;
  final double range;
  final Color color;

  _LinePainter({
    required this.points,
    required this.minY,
    required this.range,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = size.width * (i / (points.length - 1));
      final normalized = (points[i] - minY) / range;
      final y = size.height - normalized * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final shadow = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, shadow);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) {
    // More correct comparison
    return oldDelegate.points.length != points.length ||
        (oldDelegate.points.isNotEmpty &&
            points.isNotEmpty &&
            oldDelegate.points.last != points.last) ||
        oldDelegate.color != color;
  }
}
