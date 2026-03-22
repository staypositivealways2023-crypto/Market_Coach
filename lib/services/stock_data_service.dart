/// Stock Data Service - Fetch market data for AI analysis
///
/// Primary source: Python backend (Massive API) — accurate for stocks + crypto
/// Fallback: Yahoo Finance with correct symbol mapping
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

import 'backend_service.dart';

class StockData {
  final String symbol;
  final double currentPrice;
  final double? changePercent;
  final double? dayHigh;
  final double? dayLow;
  final double? fiftyTwoWeekHigh;
  final double? fiftyTwoWeekLow;
  final int? volume;
  final int? avgVolume;
  final double? marketCap;
  final double? peRatio;
  final String? companyName;
  final List<PricePoint> priceHistory;
  final List<NewsHeadline> news;

  StockData({
    required this.symbol,
    required this.currentPrice,
    this.changePercent,
    this.dayHigh,
    this.dayLow,
    this.fiftyTwoWeekHigh,
    this.fiftyTwoWeekLow,
    this.volume,
    this.avgVolume,
    this.marketCap,
    this.peRatio,
    this.companyName,
    this.priceHistory = const [],
    this.news = const [],
  });

  String get priceTrend {
    if (changePercent == null) return 'neutral';
    if (changePercent! > 2) return 'strongly up';
    if (changePercent! > 0) return 'slightly up';
    if (changePercent! < -2) return 'strongly down';
    if (changePercent! < 0) return 'slightly down';
    return 'neutral';
  }

  double? get fiftyTwoWeekPosition {
    if (fiftyTwoWeekHigh == null || fiftyTwoWeekLow == null) return null;
    final range = fiftyTwoWeekHigh! - fiftyTwoWeekLow!;
    if (range == 0) return 50;
    return ((currentPrice - fiftyTwoWeekLow!) / range) * 100;
  }
}

class PricePoint {
  final DateTime date;
  final double price;
  PricePoint(this.date, this.price);
}

class NewsHeadline {
  final String title;
  final String? source;
  final DateTime? publishedAt;
  final String? url;

  NewsHeadline({required this.title, this.source, this.publishedAt, this.url});
}

class StockDataService {
  final _backend = BackendService();

  /// Yahoo Finance symbol format for crypto (BTC → BTC-USD)
  static String _yahooSymbol(String symbol) {
    const cryptos = {
      'BTC',
      'ETH',
      'BNB',
      'SOL',
      'ADA',
      'XRP',
      'DOGE',
      'DOT',
      'AVAX',
      'MATIC',
      'LINK',
      'UNI',
      'LTC',
      'BCH',
      'XLM',
      'ALGO',
      'ATOM',
      'VET',
      'FIL',
      'TRX',
    };
    final upper = symbol.toUpperCase();
    // Already has suffix (BTC-USD, ETH-USDT)
    if (upper.contains('-') || upper.contains('/')) return upper;
    return cryptos.contains(upper) ? '$upper-USD' : upper;
  }

  Future<StockData> fetchStockData(String symbol) async {
    final upper = symbol.toUpperCase();

    // 1. Get accurate price + range from backend (Massive API)
    final range = await _backend.getPriceRange(upper);

    // 2. Get real news from backend
    final newsItems = await _backend.getTickerNews(upper, limit: 5);

    // 3. Get 30-day price history from Yahoo Finance (fallback chain)
    final priceHistory = await _fetchPriceHistory(_yahooSymbol(upper));

    // 4. Resolve current price — backend first, then price history last point
    final currentPrice = (range?.currentPrice ?? 0.0) > 0
        ? range!.currentPrice!
        : priceHistory.isNotEmpty
        ? priceHistory.last.price
        : 0.0;

    if (currentPrice <= 0) {
      throw Exception(
        'Could not retrieve price for $upper. '
        'Check the symbol and ensure the backend is running.',
      );
    }

    // Compute change percent from price history if not in range data
    double? changePercent;
    if (priceHistory.length >= 2) {
      final prev = priceHistory[priceHistory.length - 2].price;
      if (prev > 0) {
        changePercent = (currentPrice - prev) / prev * 100;
      }
    }

    final news = newsItems
        .map(
          (a) => NewsHeadline(
            title: a.title,
            source: a.source,
            publishedAt: DateTime.tryParse(a.publishedAt),
            url: a.url,
          ),
        )
        .toList();

    return StockData(
      symbol: upper,
      currentPrice: currentPrice,
      changePercent: changePercent,
      dayHigh: range?.dayHigh,
      dayLow: range?.dayLow,
      fiftyTwoWeekHigh: range?.yearHigh,
      fiftyTwoWeekLow: range?.yearLow,
      volume: range?.volume,
      priceHistory: priceHistory,
      news: news.isNotEmpty ? news : _fallbackNews(upper),
    );
  }

  Future<List<PricePoint>> _fetchPriceHistory(String yahooSymbol) async {
    try {
      final url = Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/$yahooSymbol'
        '?interval=1d&range=1mo',
      );

      final response = await http
          .get(url, headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final result = data['chart']['result']?[0];
      if (result == null) return [];

      final timestamps = (result['timestamp'] as List?)?.cast<int>() ?? [];
      final closes =
          (result['indicators']['quote'][0]['close'] as List?)
              ?.cast<double?>() ??
          [];

      final history = <PricePoint>[];
      for (var i = 0; i < timestamps.length && i < closes.length; i++) {
        if (closes[i] != null) {
          history.add(
            PricePoint(
              DateTime.fromMillisecondsSinceEpoch(timestamps[i] * 1000),
              closes[i]!,
            ),
          );
        }
      }
      return history;
    } catch (_) {
      return [];
    }
  }

  List<NewsHeadline> _fallbackNews(String symbol) => [
    NewsHeadline(
      title: '$symbol — latest market update',
      source: 'MarketCoach',
      publishedAt: DateTime.now(),
    ),
  ];
}
