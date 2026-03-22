import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/market_detail.dart';
import '../services/backend_service.dart';

final _backend = BackendService();

/// News articles for a specific ticker symbol
final tickerNewsProvider = FutureProvider.family<List<NewsArticleItem>, String>(
  (ref, symbol) async {
    return _backend.getTickerNews(symbol, limit: 15);
  },
);

/// General market news feed
final marketNewsProvider = FutureProvider<List<NewsArticleItem>>(
  (ref) async {
    return _backend.getMarketNews(limit: 20);
  },
);
