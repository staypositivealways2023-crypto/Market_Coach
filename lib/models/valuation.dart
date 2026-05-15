import 'package:cloud_firestore/cloud_firestore.dart';

/// Valuation analysis for a stock/symbol
class Valuation {
  final String symbol;
  final DateTime timestamp;

  // Fair value estimates
  final double? fairValueDcf; // Discounted Cash Flow
  final double? fairValuePe; // P/E ratio based
  final double? fairValuePb; // Price-to-Book based
  final double? fairValueAvg; // Average of all methods

  // Valuation status
  final String status; // 'UNDERVALUED', 'FAIRLY_VALUED', 'OVERVALUED'
  final double upsidePercent; // % upside/downside to fair value
  final int confidence; // 0-100 confidence in the valuation

  // Analysis
  final List<String> reasons; // Why this valuation was assigned
  final double? currentPrice;

  const Valuation({
    required this.symbol,
    required this.timestamp,
    this.fairValueDcf,
    this.fairValuePe,
    this.fairValuePb,
    this.fairValueAvg,
    required this.status,
    required this.upsidePercent,
    required this.confidence,
    required this.reasons,
    this.currentPrice,
  });

  factory Valuation.fromMap(Map<String, dynamic> map) {
    return Valuation(
      symbol: map['symbol'] as String? ?? '',
      timestamp: _parseDateTime(map['timestamp']) ?? DateTime.now(),
      fairValueDcf: _parseDouble(map['fair_value_dcf']),
      fairValuePe: _parseDouble(map['fair_value_pe']),
      fairValuePb: _parseDouble(map['fair_value_pb']),
      fairValueAvg: _parseDouble(map['fair_value_avg']),
      status: map['status'] as String? ?? 'FAIRLY_VALUED',
      upsidePercent: _parseDouble(map['upside_percent']) ?? 0.0,
      confidence: map['confidence'] as int? ?? 50,
      reasons: _parseStringList(map['reasons']),
      currentPrice: _parseDouble(map['current_price']),
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

  static List<String> _parseStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  // Computed getters
  bool get isUndervalued => status == 'UNDERVALUED';
  bool get isOvervalued => status == 'OVERVALUED';
  bool get isFairlyValued => status == 'FAIRLY_VALUED';
}
