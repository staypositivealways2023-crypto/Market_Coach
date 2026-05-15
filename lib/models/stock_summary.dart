class StockSummary {
  final String ticker;
  final String name;
  final double price;
  final double changePercent;
  final bool isCrypto;
  final double? volume;
  final double? marketCap;
  final Map<String, String>? fundamentals;
  final List<String>? technicalHighlights;
  final String? sector;
  final String? industry;

  const StockSummary({
    required this.ticker,
    required this.name,
    required this.price,
    required this.changePercent,
    this.isCrypto = false,
    this.volume,
    this.marketCap,
    this.fundamentals,
    this.technicalHighlights,
    this.sector,
    this.industry,
  });

  bool get isPositive => changePercent >= 0;

  StockSummary copyWith({
    String? ticker,
    String? name,
    double? price,
    double? changePercent,
    bool? isCrypto,
    double? volume,
    double? marketCap,
    Map<String, String>? fundamentals,
    List<String>? technicalHighlights,
    String? sector,
    String? industry,
  }) {
    return StockSummary(
      ticker: ticker ?? this.ticker,
      name: name ?? this.name,
      price: price ?? this.price,
      changePercent: changePercent ?? this.changePercent,
      isCrypto: isCrypto ?? this.isCrypto,
      volume: volume ?? this.volume,
      marketCap: marketCap ?? this.marketCap,
      fundamentals: fundamentals ?? this.fundamentals,
      technicalHighlights: technicalHighlights ?? this.technicalHighlights,
      sector: sector ?? this.sector,
      industry: industry ?? this.industry,
    );
  }

  factory StockSummary.fromMap(Map<String, dynamic> map) {
    final ticker = map['ticker'] as String? ?? map['symbol'] as String? ?? '';
    return StockSummary(
      ticker: ticker,
      name: map['name'] as String? ?? ticker,  // Use ticker as fallback name
      price: _parseDouble(map['price']) ?? 0.0,
      changePercent: _parseDouble(map['change_percent']) ?? 0.0,
      isCrypto: map['is_crypto'] as bool? ?? false,
      volume: _parseDouble(map['volume']),
      marketCap: _parseDouble(map['market_cap'] ?? map['marketCap']),
      fundamentals: map['fundamentals'] != null
          ? Map<String, String>.from(map['fundamentals'] as Map)
          : null,
      technicalHighlights: map['technical_highlights'] != null
          ? List<String>.from(map['technical_highlights'] as List)
          : null,
      sector: map['sector'] as String?,
      industry: map['industry'] as String?,
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
