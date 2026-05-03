import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated waveform bar visualisation shown when assistant is speaking.
/// [amplitude] (0.0–1.0) scales bar heights in real-time to the audio volume.
class VoiceWaveform extends StatefulWidget {
  final bool active;
  final Color color;
  /// Normalised RMS amplitude from the audio delta stream (0.0–1.0).
  final double amplitude;

  const VoiceWaveform({
    super.key,
    required this.active,
    this.color = const Color(0xFF12A28C),
    this.amplitude = 0.0,
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
              amplitude: widget.amplitude,
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
  /// 0.0–1.0 amplitude to scale bar heights reactively.
  final double amplitude;

  _WaveformPainter({
    required this.progress,
    required this.color,
    this.amplitude = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;

    const barCount = 16;
    final spacing = size.width / barCount;
    // Blend between a min height (idle wave shape) and full amplitude
    final drive = 0.35 + amplitude * 0.65;

    for (int i = 0; i < barCount; i++) {
      final phase = (i / barCount) + progress;
      final height = (math.sin(phase * math.pi * 2) * 0.4 + 0.6) * size.height * drive;
      final x = spacing * i + spacing / 2;
      final y = (size.height - height) / 2;
      canvas.drawLine(Offset(x, y), Offset(x, y + height), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress || old.amplitude != amplitude;
}
