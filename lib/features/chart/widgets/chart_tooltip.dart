import 'package:flutter/material.dart';
import '../controllers/chart_controller.dart';

class ChartTooltip extends StatelessWidget {
  final ChartController controller;
  final Size chartSize;

  const ChartTooltip({super.key, required this.controller, required this.chartSize});

  @override
  Widget build(BuildContext context) {
    if (!controller.showCrosshair && controller.selectedCandleIndex == null) {
      return const SizedBox.shrink();
    }

    final idx = controller.selectedCandleIndex;
    if (idx == null || idx >= controller.candles.length) {
      return const SizedBox.shrink();
    }

    final candle = controller.candles[idx];
    final x = controller.indexToX(idx, chartSize);
    final y = controller.crosshairPosition.dy;

    // Clamp horizontally so tooltip never overflows
    const tooltipW = 130.0;
    const tooltipH = 92.0;
    double left = x - tooltipW / 2;
    left = left.clamp(4.0, chartSize.width - tooltipW - 4);

    double top = y - tooltipH - 8;
    if (top < 4) top = y + 12;

    return Positioned(
      left: left,
      top: top,
      width: tooltipW,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2435),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF12A28C), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Row('O', candle.open),
            _Row('H', candle.high),
            _Row('L', candle.low),
            _Row('C', candle.close),
            const Divider(height: 6, color: Colors.white12),
            _VolRow(candle.volume),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final double value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ),
          const SizedBox(width: 4),
          Text(
            _fmt(value),
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v < 1.0) return v.toStringAsFixed(4);
    if (v < 10000) return v.toStringAsFixed(2);
    return v.round().toString();
  }
}

class _VolRow extends StatelessWidget {
  final double volume;
  const _VolRow(this.volume);

  @override
  Widget build(BuildContext context) {
    String fmt;
    if (volume >= 1e9) {
      fmt = '${(volume / 1e9).toStringAsFixed(2)}B';
    } else if (volume >= 1e6) {
      fmt = '${(volume / 1e6).toStringAsFixed(2)}M';
    } else if (volume >= 1e3) {
      fmt = '${(volume / 1e3).toStringAsFixed(1)}K';
    } else {
      fmt = volume.toStringAsFixed(0);
    }
    return Row(
      children: [
        const SizedBox(
          width: 12,
          child: Text('V', style: TextStyle(color: Colors.white38, fontSize: 10)),
        ),
        const SizedBox(width: 4),
        Text(fmt, style: const TextStyle(color: Colors.white54, fontSize: 10)),
      ],
    );
  }
}
