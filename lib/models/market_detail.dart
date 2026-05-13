import 'package:flutter/material.dart';

/// Models for data returned by the Python backend Phase 2 endpoints

// ── Safe JSON helpers ────────────────────────────────────────────────────────
// These tolerate the backend returning numbers as strings (e.g. Binance fields)
// or returning null/missing fields without throwing.

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    // Handle fractional strings like "12345.678" (Binance coin volume)
    final d = double.tryParse(v);
    return d?.toInt();
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────

class MarketRange {
  final String symbol;
  final double? currentPrice;
  final double? dayHigh;
  final double? dayLow;
  final double? open;
  final double? previousClose;
  final int? volume;
  final double? marketCap;
  final double? yearHigh;
  final double? yearLow;

  const MarketRange({
    required this.symbol,
    this.currentPrice,
    this.dayHigh,
    this.dayLow,
    this.open,
    this.previousClose,
    this.volume,
    this.marketCap,
    this.yearHigh,
    this.yearLow,
  });

  factory MarketRange.fromJson(Map<String, dynamic> json) {
    return MarketRange(
      symbol:        json['symbol'] as String? ?? '',
      currentPrice:  _toDouble(json['current_price']),
      dayHigh:       _toDouble(json['day_high']),
      dayLow:        _toDouble(json['day_low']),
      open:          _toDouble(json['open']),
      previousClose: _toDouble(json['previous_close']),
      volume:        _toInt(json['volume']),
      marketCap:     _toDouble(json['market_cap']),
      yearHigh:      _toDouble(json['year_high']),
      yearLow:       _toDouble(json['year_low']),
    );
  }

  /// Turnover (price × volume) — used as fallback when market cap is unavailable.
  double? get turnover {
    final p = currentPrice;
    final v = volume;
    if (p != null && v != null && v > 0) return p * v;
    return null;
  }
}

class NewsArticleItem {
  final String id;
  final String title;
  final String? description;
  final String url;
  final String source;
  final String publishedAt;
  final List<String> tickers;
  final double sentimentScore;
  final String sentimentLabel;

  const NewsArticleItem({
    required this.id,
    required this.title,
    this.description,
    required this.url,
    required this.source,
    required this.publishedAt,
    required this.tickers,
    required this.sentimentScore,
    required this.sentimentLabel,
  });

  factory NewsArticleItem.fromJson(Map<String, dynamic> json) {
    return NewsArticleItem(
      id:             json['id'] as String? ?? '',
      title:          json['title'] as String? ?? '',
      description:    json['description'] as String?,
      url:            json['url'] as String? ?? '',
      source:         json['source'] as String? ?? '',
      publishedAt:    json['published_at'] as String? ?? '',
      tickers:        (json['tickers'] as List<dynamic>?)?.cast<String>() ?? [],
      sentimentScore: (json['sentiment_score'] as num?)?.toDouble() ?? 0.0,
      sentimentLabel: json['sentiment_label'] as String? ?? 'neutral',
    );
  }

  Color get sentimentColor {
    switch (sentimentLabel) {
      case 'positive': return const Color(0xFF00C896);
      case 'negative': return const Color(0xFFFF4D6A);
      default:         return const Color(0xFF8A8FA0);
    }
  }

  String get formattedDate {
    try {
      final dt = DateTime.parse(publishedAt).toLocal();
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return publishedAt.length > 10 ? publishedAt.substring(0, 10) : publishedAt;
    }
  }

  String get timeAgo {
    try {
      final dt = DateTime.parse(publishedAt).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24)   return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return publishedAt.length > 10 ? publishedAt.substring(0, 10) : publishedAt;
    }
  }
}

class MacroIndicator {
  final String date;
  final double? value;

  const MacroIndicator({required this.date, this.value});

  factory MacroIndicator.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MacroIndicator(date: '', value: null);
    return MacroIndicator(
      date:  json['date'] as String? ?? '',
      value: (json['value'] as num?)?.toDouble(),
    );
  }
}

class MacroOverview {
  final MacroIndicator fedFundsRate;
  final MacroIndicator cpi;
  final MacroIndicator inflationYoy;
  final MacroIndicator yieldCurve;
  final MacroIndicator unemployment;
  final MacroIndicator gdpGrowth;
  final MacroIndicator dxy;

  const MacroOverview({
    required this.fedFundsRate,
    required this.cpi,
    required this.inflationYoy,
    required this.yieldCurve,
    required this.unemployment,
    required this.gdpGrowth,
    required this.dxy,
  });

  factory MacroOverview.fromJson(Map<String, dynamic> json) {
    return MacroOverview(
      fedFundsRate:  MacroIndicator.fromJson(json['fed_funds_rate'] as Map<String, dynamic>?),
      cpi:           MacroIndicator.fromJson(json['cpi'] as Map<String, dynamic>?),
      inflationYoy:  MacroIndicator.fromJson(json['inflation_yoy'] as Map<String, dynamic>?),
      yieldCurve:    MacroIndicator.fromJson(json['yield_curve'] as Map<String, dynamic>?),
      unemployment:  MacroIndicator.fromJson(json['unemployment'] as Map<String, dynamic>?),
      gdpGrowth:     MacroIndicator.fromJson(json['gdp_growth'] as Map<String, dynamic>?),
      dxy:           MacroIndicator.fromJson(json['dxy'] as Map<String, dynamic>?),
    );
  }
}
