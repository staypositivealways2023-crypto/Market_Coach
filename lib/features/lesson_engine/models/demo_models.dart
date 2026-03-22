import 'package:flutter/material.dart';

// ─── DemoCandle ───────────────────────────────────────────────────────────────
class DemoCandle {
  final double open;
  final double high;
  final double low;
  final double close;
  final double? volume;

  const DemoCandle({
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume,
  });

  bool get isBullish => close >= open;
}

// ─── CandleAnnotation ─────────────────────────────────────────────────────────
class CandleAnnotation {
  final int index;
  final String label;
  final Color color;
  final bool arrowUp; // true = label+arrow above candle, false = below

  const CandleAnnotation({
    required this.index,
    required this.label,
    required this.color,
    this.arrowUp = true,
  });
}

// ─── IndicatorAnnotation ──────────────────────────────────────────────────────
class IndicatorAnnotation {
  final int index;
  final String label;
  final Color color;

  const IndicatorAnnotation({
    required this.index,
    required this.label,
    required this.color,
  });
}

// ─── MatchItem / MatchTarget ──────────────────────────────────────────────────
class MatchItem {
  final String id;
  final String label;

  const MatchItem({required this.id, required this.label});
}

class MatchTarget {
  final String id;
  final String hint;

  const MatchTarget({required this.id, required this.hint});
}

// ─── RangeZone ────────────────────────────────────────────────────────────────
class RangeZone {
  final double min;
  final double max;
  final Color color;
  final String label;

  const RangeZone({
    required this.min,
    required this.max,
    required this.color,
    required this.label,
  });
}

// ─── IndicatorDemoType ────────────────────────────────────────────────────────
enum IndicatorDemoType { ma, macd, bollinger, macross }
