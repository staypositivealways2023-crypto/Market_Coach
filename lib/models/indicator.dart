import 'package:cloud_firestore/cloud_firestore.dart';

/// Technical indicators for a stock/symbol
class Indicator {
  final String symbol;
  final DateTime timestamp;

  // Moving Averages
  final double? sma20;
  final double? sma50;
  final double? sma200;
  final double? ema12;
  final double? ema26;

  // Momentum Indicators
  final double? rsi;
  final double? macd;
  final double? macdSignal;
  final double? macdHistogram;

  // Volatility
  final double? bollingerUpper;
  final double? bollingerMiddle;
  final double? bollingerLower;
  final double? atr;

  // Volume
  final double? volumeSma;
  final double? obv; // On-balance volume

  // Trend
  final double? adx; // Average Directional Index

  // Signals (nested object)
  final IndicatorSignals? signals;

  const Indicator({
    required this.symbol,
    required this.timestamp,
    this.sma20,
    this.sma50,
    this.sma200,
    this.ema12,
    this.ema26,
    this.rsi,
    this.macd,
    this.macdSignal,
    this.macdHistogram,
    this.bollingerUpper,
    this.bollingerMiddle,
    this.bollingerLower,
    this.atr,
    this.volumeSma,
    this.obv,
    this.adx,
    this.signals,
  });

  factory Indicator.fromMap(Map<String, dynamic> map) {
    return Indicator(
      symbol: map['symbol'] as String? ?? '',
      timestamp: _parseDateTime(map['timestamp']) ?? DateTime.now(),
      sma20: _parseDouble(map['sma_20']),
      sma50: _parseDouble(map['sma_50']),
      sma200: _parseDouble(map['sma_200']),
      ema12: _parseDouble(map['ema_12']),
      ema26: _parseDouble(map['ema_26']),
      rsi: _parseDouble(map['rsi']),
      macd: _parseDouble(map['macd']),
      macdSignal: _parseDouble(map['macd_signal']),
      macdHistogram: _parseDouble(map['macd_histogram']),
      bollingerUpper: _parseDouble(map['bollinger_upper']),
      bollingerMiddle: _parseDouble(map['bollinger_middle']),
      bollingerLower: _parseDouble(map['bollinger_lower']),
      atr: _parseDouble(map['atr']),
      volumeSma: _parseDouble(map['volume_sma']),
      obv: _parseDouble(map['obv']),
      adx: _parseDouble(map['adx']),
      signals: map['signals'] != null
          ? IndicatorSignals.fromMap(map['signals'] as Map<String, dynamic>)
          : null,
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

/// Trading signals derived from technical indicators
class IndicatorSignals {
  final String trend; // 'BULLISH', 'BEARISH', 'NEUTRAL'
  final String rsiSignal; // 'OVERBOUGHT', 'OVERSOLD', 'NEUTRAL'
  final String macdSignal; // 'BUY', 'SELL', 'NEUTRAL'
  final String movingAverageCross; // 'GOLDEN_CROSS', 'DEATH_CROSS', 'NEUTRAL'
  final int strength; // 0-100 overall signal strength

  const IndicatorSignals({
    required this.trend,
    required this.rsiSignal,
    required this.macdSignal,
    required this.movingAverageCross,
    required this.strength,
  });

  factory IndicatorSignals.fromMap(Map<String, dynamic> map) {
    return IndicatorSignals(
      trend: map['trend'] as String? ?? 'NEUTRAL',
      rsiSignal: map['rsi_signal'] as String? ?? 'NEUTRAL',
      macdSignal: map['macd_signal'] as String? ?? 'NEUTRAL',
      movingAverageCross: map['moving_average_cross'] as String? ?? 'NEUTRAL',
      strength: map['strength'] as int? ?? 50,
    );
  }

  bool get isBullish => trend == 'BULLISH';
  bool get isBearish => trend == 'BEARISH';
  bool get isOverbought => rsiSignal == 'OVERBOUGHT';
  bool get isOversold => rsiSignal == 'OVERSOLD';
}
