import 'package:cloud_firestore/cloud_firestore.dart';

class Candle {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  factory Candle.fromMap(Map<String, dynamic> map) {
    return Candle(
      time: _parseDateTime(map['timestamp']) ?? DateTime.now(),
      open: _parseDouble(map['open']) ?? 0.0,
      high: _parseDouble(map['high']) ?? 0.0,
      low: _parseDouble(map['low']) ?? 0.0,
      close: _parseDouble(map['close']) ?? 0.0,
      volume: _parseDouble(map['volume']) ?? 0.0,
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
