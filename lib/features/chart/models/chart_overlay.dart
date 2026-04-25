import 'package:flutter/material.dart';

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

class OverlayData {
  final List<MALine> maLines;
  final BollingerData? bollinger;
  final List<SRLine> srLines;
  final dynamic patterns; // PatternScanResult?

  /// VWAP values aligned 1:1 to candle indices. Null list = no VWAP overlay.
  final List<double?>? vwapLine;

  /// Live price for the horizontal dashed current-price line. Null = hidden.
  final double? currentPriceLine;

  const OverlayData({
    this.maLines = const [],
    this.bollinger,
    this.srLines = const [],
    this.patterns,
    this.vwapLine,
    this.currentPriceLine,
  });
}
