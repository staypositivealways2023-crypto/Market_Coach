import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart';
import '../../models/stock_summary.dart';
import '../../services/backend_service.dart';
import '../../widgets/glass_card.dart';
import '../../features/chart/screens/asset_chart_screen.dart';
import 'market_view_all_screen.dart';

// ── Default symbol lists ──────────────────────────────────────────────────────

const _defaultStocks = [
  _AssetMeta('AAPL',  'Apple Inc.',       'Technology',        false),
  _AssetMeta('MSFT',  'Microsoft Corp.',  'Technology',        false),
  _AssetMeta('NVDA',  'NVIDIA Corp.',     'Semiconductors',    false),
  _AssetMeta('GOOGL', 'Alphabet Inc.',    'Internet Services', false),
  _AssetMeta('TSLA',  'Tesla Inc.',       'Consumer Cyclical', false),
  _AssetMeta('AMZN',  'Amazon.com Inc.',  'E-Commerce',        false),
  _AssetMeta('META',  'Meta Platforms',   'Technology',        false),
  _AssetMeta('BRK.B', 'Berkshire Hathaway','Financials',       false),
];

const _defaultCrypto = [
  _AssetMeta('BTC',  'Bitcoin',   'Digital Asset', true),
  _AssetMeta('ETH',  'Ethereum',  'Digital Asset', true),
  _AssetMeta('ADA',  'Cardano',   'Digital Asset', true),
  _AssetMeta('SOL',  'Solana',    'Digital Asset', true),
  _AssetMeta('XRP',  'Ripple',    'Digital Asset', true),
  _AssetMeta('DOGE', 'Dogecoin',  'Digital Asset', true),
];

class _AssetMeta {
  final String ticker;
  final String name;
  final String sector;
  final bool isCrypto;
  const _AssetMeta(this.ticker, this.name, this.sector, this.isCrypto);
}

// ── Screen ────────────────────────────────────────────────────────────────────

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  final _backend = BackendService();

  // live quote data: symbol → {price, change_percent}
  Map<String, Map<String, dynamic>> _quotes = {};
  bool _loading = true;

  Timer? _refreshTimer;
  Timer? _coachingTimer;
  final PageController _coachingPageController = PageController();
  int _currentCoachingIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchQuotes();
    // Refresh every 60 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _fetchQuotes());

    _coachingTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_coachingPageController.hasClients) {
        final next = (_currentCoachingIndex + 1) % _coachingMessages.length;
        _coachingPageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _coachingTimer?.cancel();
    _coachingPageController.dispose();
    super.dispose();
  }

  Future<void> _fetchQuotes() async {
    final stockSymbols = _defaultStocks.map((s) => s.ticker).toList();
    final cryptoSymbols = _defaultCrypto.map((s) => s.ticker).toList();

    // Try backend first; fall back to direct APIs if unreachable
    final allSymbols = [...stockSymbols, ...cryptoSymbols];
    var quotes = await _backend.getQuotes(allSymbols);

    if (quotes.isEmpty) {
      final results = await Future.wait([
        _fetchFinnhubStocks(stockSymbols),
        _fetchBinanceCrypto(cryptoSymbols),
      ]);
      quotes = {...results[0], ...results[1]};
    }

    if (mounted) {
      setState(() {
        _quotes = quotes;
        _loading = false;
      });
    }
  }

  // Binance mapping: app symbol → Binance pair
  static const _binanceMap = {
    'BTC': 'BTCUSDT', 'ETH': 'ETHUSDT', 'ADA': 'ADAUSDT',
    'SOL': 'SOLUSDT', 'XRP': 'XRPUSDT', 'DOGE': 'DOGEUSDT',
  };

  /// Fetch crypto quotes from Binance REST (no key, reliable).
  Future<Map<String, Map<String, dynamic>>> _fetchBinanceCrypto(
      List<String> symbols) async {
    try {
      final pairs = symbols
          .where((s) => _binanceMap.containsKey(s))
          .map((s) => '"${_binanceMap[s]!}"')
          .join(',');
      final uri = Uri.parse(
          'https://api.binance.com/api/v3/ticker/24hr?symbols=[$pairs]');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return {};

      final list = jsonDecode(resp.body) as List<dynamic>;
      final reverseMap = {for (final e in _binanceMap.entries) e.value: e.key};
      final quotes = <String, Map<String, dynamic>>{};
      for (final t in list) {
        final pair = t['symbol'] as String;
        final symbol = reverseMap[pair];
        if (symbol == null) continue;
        final price = double.tryParse(t['lastPrice'] as String? ?? '') ?? 0.0;
        final change = double.tryParse(t['priceChangePercent'] as String? ?? '') ?? 0.0;
        if (price > 0) {
          quotes[symbol] = {'symbol': symbol, 'price': price, 'change_percent': change};
        }
      }
      return quotes;
    } catch (_) {
      return {};
    }
  }

  /// Fetch stock quotes from Finnhub (60 req/min free tier).
  Future<Map<String, Map<String, dynamic>>> _fetchFinnhubStocks(
      List<String> symbols) async {
    final quotes = <String, Map<String, dynamic>>{};
    // Parallel requests — Finnhub is one symbol per call
    await Future.wait(symbols.map((symbol) async {
      try {
        final uri = Uri.parse(
            'https://finnhub.io/api/v1/quote?symbol=$symbol'
            '&token=${APIConfig.finnhubKey}');
        final resp = await http.get(uri).timeout(const Duration(seconds: 10));
        if (resp.statusCode != 200) return;
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final price = (data['c'] as num?)?.toDouble() ?? 0.0;
        final change = (data['dp'] as num?)?.toDouble() ?? 0.0;
        if (price > 0) {
          quotes[symbol] = {'symbol': symbol, 'price': price, 'change_percent': change};
        }
      } catch (_) {}
    }));
    return quotes;
  }

  StockSummary _toSummary(_AssetMeta meta) {
    final q = _quotes[meta.ticker];
    return StockSummary(
      ticker: meta.ticker,
      name: meta.name,
      price: (q?['price'] as num?)?.toDouble() ?? 0.0,
      changePercent: (q?['change_percent'] as num?)?.toDouble() ?? 0.0,
      isCrypto: meta.isCrypto,
      sector: meta.sector,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Market'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh quotes',
            onPressed: () {
              setState(() => _loading = true);
              _fetchQuotes();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchQuotes,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Coaching tip
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _CoachingMessageBox(
                    pageController: _coachingPageController,
                    onPageChanged: (i) => setState(() => _currentCoachingIndex = i),
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // Stocks
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Stocks', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => MarketViewAllScreen(
                            assets: _defaultStocks.map(_toSummary).toList(),
                            isCrypto: false,
                          ),
                        )),
                        child: const Text('View All'),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: _AssetCarousel(
                  assets: _defaultStocks.take(3).map(_toSummary).toList(),
                  loading: _loading,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // Crypto
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Crypto', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => MarketViewAllScreen(
                            assets: _defaultCrypto.map(_toSummary).toList(),
                            isCrypto: true,
                          ),
                        )),
                        child: const Text('View All'),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: _AssetCarousel(
                  assets: _defaultCrypto.take(3).map(_toSummary).toList(),
                  loading: _loading,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // Quick Insights
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _QuickMarketInsights(),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Coaching messages ─────────────────────────────────────────────────────────

const List<Map<String, String>> _coachingMessages = [
  {'icon': '💡', 'message': 'Markets move in cycles - focus on learning patterns, not timing.'},
  {'icon': '📊', 'message': 'RSI above 70 often means "overbought" - but understand why first.'},
  {'icon': '🎯', 'message': 'Support & Resistance are key levels where price often reacts.'},
  {'icon': '📈', 'message': 'Volume confirms trends - rising prices with volume are stronger.'},
  {'icon': '⚖️', 'message': 'Position sizing protects your capital - never risk more than 1-2% per trade.'},
  {'icon': '🔍', 'message': 'Always check the macro calendar before trading a micro story.'},
  {'icon': '📉', 'message': 'Pullbacks in uptrends are opportunities - if the story hasn\'t changed.'},
  {'icon': '🛡️', 'message': 'Stop losses go where your idea would be wrong, not just a random percent.'},
  {'icon': '⏰', 'message': 'Patience beats prediction - let setups come to you.'},
  {'icon': '🎓', 'message': 'Every chart tells a story - learn to read supply and demand zones.'},
];

class _CoachingMessageBox extends StatelessWidget {
  final PageController pageController;
  final ValueChanged<int> onPageChanged;
  const _CoachingMessageBox({required this.pageController, required this.onPageChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      color: theme.colorScheme.primary.withValues(alpha: 0.15),
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        height: 80,
        child: PageView.builder(
          controller: pageController,
          onPageChanged: onPageChanged,
          itemCount: _coachingMessages.length,
          itemBuilder: (_, i) {
            final msg = _coachingMessages[i];
            return Row(
              children: [
                Text(msg['icon']!, style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(msg['message']!,
                      style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white, height: 1.4)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Asset Carousel ────────────────────────────────────────────────────────────

class _AssetCarousel extends StatelessWidget {
  final List<StockSummary> assets;
  final bool loading;
  const _AssetCarousel({required this.assets, required this.loading});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: assets.length,
        itemBuilder: (context, i) => _AssetCard(asset: assets[i], loading: loading),
      ),
    );
  }
}

class _AssetCard extends StatelessWidget {
  final StockSummary asset;
  final bool loading;
  const _AssetCard({required this.asset, required this.loading});

  String _sentimentLabel(double change) {
    if (change >= 2.0) return 'Bullish';
    if (change >= 0.5) return 'Mild Bull';
    if (change > -0.5) return 'Neutral';
    if (change > -2.0) return 'Mild Bear';
    return 'Bearish';
  }

  Color _sentimentColor(double change) {
    if (change >= 2.0) return const Color(0xFF22C55E);
    if (change >= 0.5) return const Color(0xFF86EFAC);
    if (change > -0.5) return Colors.white54;
    if (change > -2.0) return const Color(0xFFFCA5A5);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPositive = asset.changePercent >= 0;
    final changeColor = isPositive ? Colors.greenAccent : Colors.redAccent;
    final sentimentColor = _sentimentColor(asset.changePercent);
    final sentimentLabel = _sentimentLabel(asset.changePercent);
    final priceStr = asset.price > 0
        ? '\$${asset.price.toStringAsFixed(asset.price < 1 ? 4 : 2)}'
        : '—';

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GlassCard(
        width: 200,
        padding: const EdgeInsets.all(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AssetChartScreen(stock: asset),
        )),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(asset.ticker,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                if (!loading && asset.price > 0)
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            Text(asset.name,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const Spacer(),
            loading
                ? Container(
                    height: 20, width: 80,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  )
                : Text(priceStr,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            loading
                ? Container(
                    height: 16, width: 60,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  )
                : Row(
                    children: [
                      Icon(isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                          color: changeColor, size: 13),
                      const SizedBox(width: 3),
                      Text(
                        '${isPositive ? '+' : ''}${asset.changePercent.toStringAsFixed(2)}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: changeColor, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: sentimentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: sentimentColor.withValues(alpha: 0.35), width: 0.7),
                        ),
                        child: Text(
                          sentimentLabel,
                          style: TextStyle(
                              color: sentimentColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}

// ── Quick Insights ────────────────────────────────────────────────────────────

class _QuickMarketInsights extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: theme.colorScheme.primary, size: 24),
              const SizedBox(width: 12),
              Text('Quick Market Insights',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          _bullet('Tap any asset card to view live chart, indicators & AI analysis.'),
          const SizedBox(height: 12),
          _bullet('Prices refresh every 60 seconds. Pull down to refresh now.'),
          const SizedBox(height: 12),
          _bullet('AI analysis uses Claude — tap "Analyse Now" inside any stock detail.'),
          const SizedBox(height: 16),
          Text('⚠️ Educational purposes only. Not financial advice.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.white54, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Builder(builder: (context) {
      final theme = Theme.of(context);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.white.withValues(alpha: 0.9), height: 1.5)),
          ),
        ],
      );
    });
  }
}
