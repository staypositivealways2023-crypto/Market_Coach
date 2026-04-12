import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Simple animated waveform bar visualisation shown when assistant is speaking.
class VoiceWaveform extends StatefulWidget {
  final bool active;
  final Color color;

  const VoiceWaveform({
    super.key,
    required this.active,
    this.color = const Color(0xFF12A28C),
  });

  @override
  State<VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<VoiceWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();

    return SizedBox(
      height: 40,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _WaveformPainter(
              progress: _controller.value,
              color: widget.color,
            ),
          );
        },
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color color;

  _WaveformPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;

    const barCount = 16;
    final spacing = size.width / barCount;

    for (int i = 0; i < barCount; i++) {
      final phase = (i / barCount) + progress;
      final height = (math.sin(phase * math.pi * 2) * 0.4 + 0.6) * size.height;
      final x = spacing * i + spacing / 2;
      final y = (size.height - height) / 2;
      canvas.drawLine(Offset(x, y), Offset(x, y + height), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => old.progress != progress;
}
