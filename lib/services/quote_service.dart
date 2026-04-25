import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/api_config.dart';
import '../models/quote.dart';

abstract class QuoteService {
  Stream<Map<String, Quote>> streamQuotes(Set<String> symbols);
  void dispose();
}

class MockQuoteService implements QuoteService {
  final _random = Random();
  final Map<String, Quote> _baseQuotes = {
    'AAPL': const Quote(symbol: 'AAPL', price: 187.97, changePercent: 0.60),
    'BHP': const Quote(symbol: 'BHP', price: 45.84, changePercent: -0.49),
    'BTC': const Quote(symbol: 'BTC', price: 42148.47, changePercent: -0.39),
  };

  @override
  Stream<Map<String, Quote>> streamQuotes(Set<String> symbols) async* {
    while (true) {
      final quotes = <String, Quote>{};
      for (final symbol in symbols) {
        final base = _baseQuotes[symbol];
        if (base != null) {
          final priceFluctuation = (_random.nextDouble() - 0.5) * 2.0;
          final changeFluctuation = (_random.nextDouble() - 0.5) * 0.5;
          quotes[symbol] = Quote(
            symbol: symbol,
            price: base.price + priceFluctuation,
            changePercent: base.changePercent + changeFluctuation,
          );
        }
      }
      yield quotes;
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  @override
  void dispose() {}
}

/// Polls Yahoo Finance for real stock quotes every 30 seconds.
class YahooQuoteService implements QuoteService {
  static const _baseUrl = 'https://query1.finance.yahoo.com/v7/finance/quote';
  static const _pollInterval = Duration(seconds: 30);
  static const _symbolOverrides = {
    'BRK.B': 'BRK-B',
    'BF.B': 'BF-B',
  };

  StreamController<Map<String, Quote>>? _controller;
  Timer? _timer;
  Set<String> _symbols = {};

  @override
  Stream<Map<String, Quote>> streamQuotes(Set<String> symbols) {
    _symbols = symbols.map(_normalizeSymbol).toSet();
    _controller = StreamController<Map<String, Quote>>.broadcast(
      onListen: () {
        _fetchAndEmit();
        _timer = Timer.periodic(_pollInterval, (_) => _fetchAndEmit());
      },
      onCancel: () {
        _timer?.cancel();
        _timer = null;
      },
    );
    return _controller!.stream;
  }

  Future<void> _fetchAndEmit() async {
    if (_symbols.isEmpty) return;
    try {
      final requestedSymbols = _symbols.toList()..sort();
      final yahooSymbols = requestedSymbols.map(_toYahooSymbol).toSet().toList()
        ..sort();
      dev.log(
        '[YahooQuote] requested=${requestedSymbols.join(',')} '
        'mapped=${yahooSymbols.join(',')}',
        name: 'Quotes',
      );

      final symbolList = yahooSymbols.join(',');
      final uri = Uri.parse(
          '$_baseUrl?symbols=$symbolList&fields=regularMarketPrice,regularMarketChangePercent');
      final response = await http
          .get(uri, headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body);
      final results = body['quoteResponse']?['result'] as List<dynamic>?;
      if (results == null) return;

      final quotes = <String, Quote>{};
      for (final r in results) {
        final yahooSymbol = _normalizeSymbol(r['symbol'] as String? ?? '');
        final price = (r['regularMarketPrice'] as num?)?.toDouble() ?? 0.0;
        final change =
            (r['regularMarketChangePercent'] as num?)?.toDouble() ?? 0.0;
        final appSymbol = _fromYahooSymbol(yahooSymbol);
        if (appSymbol.isNotEmpty && price > 0) {
          quotes[appSymbol] =
              Quote(symbol: appSymbol, price: price, changePercent: change);
        }
      }
      if (quotes.isNotEmpty) {
        dev.log(
          '[YahooQuote] payload=${quotes.entries.map((e) => '${e.key}:${e.value.price.toStringAsFixed(2)}').join(', ')}',
          name: 'Quotes',
        );
        _controller?.add(quotes);
      }
    } catch (_) {
      // Network errors are non-fatal; next poll will retry
    }
  }

  String _normalizeSymbol(String symbol) => symbol.trim().toUpperCase();

  String _toYahooSymbol(String symbol) {
    final normalized = _normalizeSymbol(symbol);
    return _symbolOverrides[normalized] ?? normalized;
  }

  String _fromYahooSymbol(String symbol) {
    final normalized = _normalizeSymbol(symbol);
    for (final entry in _symbolOverrides.entries) {
      if (entry.value == normalized) return entry.key;
    }
    return normalized;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.close();
  }
}

class BinanceQuoteService implements QuoteService {
  static const _baseUrl = 'wss://stream.binance.com:9443/stream';
  static const _symbolMapping = {
    'BTC': 'BTCUSDT',
    'ETH': 'ETHUSDT',
    'SOL': 'SOLUSDT',
    'BNB': 'BNBUSDT',
    'ADA': 'ADAUSDT',
    'XRP': 'XRPUSDT',
    'XLM': 'XLMUSDT',
    'DOGE': 'DOGEUSDT',
  };

  WebSocketChannel? _channel;
  StreamController<Map<String, Quote>>? _controller;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  Set<String> _activeSymbols = {};
  final Map<String, Quote> _quoteCache = {};

  @override
  Stream<Map<String, Quote>> streamQuotes(Set<String> symbols) {
    _activeSymbols = symbols;
    _controller = StreamController<Map<String, Quote>>.broadcast(
      onListen: () => _connect(),
      onCancel: () => _disconnect(),
    );
    return _controller!.stream;
  }

  void _connect() {
    try {
      final binanceSymbols = _activeSymbols
          .where((s) => _symbolMapping.containsKey(s))
          .map((s) => _symbolMapping[s]!.toLowerCase())
          .toList();

      if (binanceSymbols.isEmpty) return;

      final streams = binanceSymbols.map((s) => '$s@ticker').join('/');
      final uri = Uri.parse('$_baseUrl?streams=$streams');

      _channel = WebSocketChannel.connect(uri);
      _reconnectAttempts = 0;

      _channel!.stream.listen(
        (message) {
          try {
            _handleMessage(message);
          } catch (e) {
            // Ignore parse errors
          }
        },
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: false,
      );
    } catch (e) {
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic message) {
    final data = jsonDecode(message as String);

    if (data is Map && data['data'] != null) {
      final ticker = data['data'];
      final binanceSymbol = (ticker['s'] as String).toUpperCase();

      final displaySymbol = _symbolMapping.entries
          .firstWhere(
            (e) => e.value == binanceSymbol,
            orElse: () => const MapEntry('', ''),
          )
          .key;

      if (displaySymbol.isEmpty) return;

      final price = double.tryParse(ticker['c'] ?? '0') ?? 0.0;
      final changePercent = double.tryParse(ticker['P'] ?? '0') ?? 0.0;

      final quote = Quote(
        symbol: displaySymbol,
        price: price,
        changePercent: changePercent,
      );

      _quoteCache[displaySymbol] = quote;
      _controller?.add(Map.from(_quoteCache));
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();

    final delaySeconds = min(pow(2, _reconnectAttempts).toInt(), 30);
    _reconnectAttempts++;

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _disconnect();
      _connect();
    });
  }

  void _disconnect() {
    _channel?.sink.close();
    _channel = null;
    _quoteCache.clear();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _disconnect();
    _controller?.close();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BackendQuoteService — primary data source for all market quotes.
//
// Routes ALL symbols (stocks + crypto) through the Python backend's batch
// endpoint.  The backend fans out to the best available provider:
//   Crypto  → Binance REST (free, reliable)
//   Stocks  → Polygon → Finnhub → Alpha Vantage → yfinance
//
// No Firebase auth required — /api/market/quotes is a public endpoint.
// Response: [{"symbol":"AAPL","price":175.43,"change_percent":1.24}, ...]
// ─────────────────────────────────────────────────────────────────────────────
class BackendQuoteService implements QuoteService {
  static const _pollInterval = Duration(seconds: 30);

  StreamController<Map<String, Quote>>? _controller;
  Timer? _timer;
  Set<String> _symbols = {};

  @override
  Stream<Map<String, Quote>> streamQuotes(Set<String> symbols) {
    _symbols = Set.unmodifiable(symbols);
    _timer?.cancel();
    _controller?.close();
    _controller = StreamController<Map<String, Quote>>.broadcast(
      onListen: () {
        _fetchAndEmit(); // immediate first fetch
        _timer = Timer.periodic(_pollInterval, (_) => _fetchAndEmit());
      },
      onCancel: () {
        _timer?.cancel();
        _timer = null;
      },
    );
    return _controller!.stream;
  }

  Future<void> _fetchAndEmit() async {
    if (_symbols.isEmpty) return;
    try {
      final symbolList = _symbols.join(',');
      final uri = Uri.parse(
        '${APIConfig.backendBaseUrl}/api/market/quotes?symbols=$symbolList',
      );
      dev.log('[BackendQuote] fetching: $symbolList', name: 'Quotes');

      final response =
          await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        dev.log('[BackendQuote] HTTP ${response.statusCode}', name: 'Quotes');
        return;
      }

      final body = jsonDecode(response.body) as List<dynamic>;
      final quotes = <String, Quote>{};
      for (final item in body) {
        final symbol =
            ((item['symbol'] as String?) ?? '').trim().toUpperCase();
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        final changePct =
            (item['change_percent'] as num?)?.toDouble() ?? 0.0;
        if (symbol.isNotEmpty && price > 0) {
          quotes[symbol] =
              Quote(symbol: symbol, price: price, changePercent: changePct);
        }
      }

      if (quotes.isNotEmpty) {
        dev.log(
          '[BackendQuote] ${quotes.length} quotes: '
          '${quotes.entries.map((e) => '${e.key}:\$${e.value.price.toStringAsFixed(2)}').join(', ')}',
          name: 'Quotes',
        );
        _controller?.add(quotes);
      } else {
        dev.log('[BackendQuote] empty response for: $symbolList',
            name: 'Quotes');
      }
    } catch (e) {
      dev.log('[BackendQuote] error: $e', name: 'Quotes');
      // Non-fatal — next poll will retry
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.close();
  }
}
