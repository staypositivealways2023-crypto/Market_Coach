import 'package:flutter/material.dart';

/// A single entry or exit signal marker to paint on the candlestick chart.
///
/// [candleIndex] is the absolute index into the candles list.
/// [isBuy] — true = green ▲ below the candle low; false = red ▼ above the high.
/// [strength] — 0.0–1.0, controls marker opacity (strong signal = fully opaque).
class SignalMarker {
  final int candleIndex;
  final bool isBuy;
  final double strength;
  const SignalMarker({
    required this.candleIndex,
    required this.isBuy,
    this.strength = 1.0,
  });
}

class MALine {
  final List<double?> values;
  final Color color;
  final String label;
  MALine({required this.values, required this.color, required this.label});
}

class BollingerData {
  final List<double?> upper;
  final List<double?> lower;
  final List<double?> middle;
  BollingerData({required this.upper, required this.lower, required this.middle});
}

class SRLine {
  final double price;
  final Color color;
  final String label;
  SRLine({required this.price, required this.color, required this.label});
}

/// An AI-derived trade-plan level (stop loss / price target) to overlay on
/// the chart as a solid horizontal line with a left-edge label badge.
/// Kept separate from [SRLine] so painters can style them distinctly.
class TradeLevel {
  final double price;
  final Color color;
  final String label;       // e.g. "SL", "Target", "Bull", "Bear"
  final double alpha;       // 0.0–1.0, controls overall opacity
  const TradeLevel({
    required this.price,
    required this.color,
    required this.label,
    this.alpha = 1.0,
  });
}

class OverlayData {
  final List<MALine> maLines;
  final BollingerData? bollinger;
  final List<SRLine> srLines;
  final dynamic patterns; // PatternScanResult?

  /// VWAP values aligned 1:1 to candle indices. Null list = no VWAP overlay.
  final List<double?>? vwapLine;

  /// Live price for the horizontal dashed current-price line. Null = hidden.
  final double? currentPriceLine;

  /// Buy / sell signal markers derived from RSI + MACD crossovers.
  final List<SignalMarker> signalMarkers;

  /// AI trade-plan levels from RiskAgent (stop loss, targets).
  /// Drawn as solid left-labelled horizontal lines.
  final List<TradeLevel> tradeLevels;

  const OverlayData({
    this.maLines = const [],
    this.bollinger,
    this.srLines = const [],
    this.patterns,
    this.vwapLine,
    this.currentPriceLine,
    this.signalMarkers = const [],
    this.tradeLevels = const [],
  });
}
