import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../models/stock_summary.dart';
import '../../services/backend_service.dart';
import '../../widgets/glass_card.dart';
import '../../features/chart/screens/asset_chart_screen.dart';
import 'market_view_all_screen.dart';

// ── Default symbol lists ──────────────────────────────────────────────────────

const _defaultStocks = [
  // Tech
  _AssetMeta('AAPL',  'Apple Inc.',         'Tech',        false),
  _AssetMeta('MSFT',  'Microsoft Corp.',    'Tech',        false),
  _AssetMeta('GOOGL', 'Alphabet Inc.',      'Tech',        false),
  _AssetMeta('META',  'Meta Platforms',     'Tech',        false),
  // AI
  _AssetMeta('NVDA',  'NVIDIA Corp.',       'AI',          false),
  _AssetMeta('AMD',   'Advanced Micro Dev.','AI',          false),
  _AssetMeta('PLTR',  'Palantir Tech.',     'AI',          false),
  // EV
  _AssetMeta('TSLA',  'Tesla Inc.',         'EV',          false),
  _AssetMeta('RIVN',  'Rivian Automotive',  'EV',          false),
  // Energy
  _AssetMeta('XOM',   'Exxon Mobil Corp.', 'Energy',      false),
  _AssetMeta('CVX',   'Chevron Corp.',      'Energy',      false),
  // Finance
  _AssetMeta('BRK.B', 'Berkshire Hathaway','Finance',     false),
  _AssetMeta('JPM',   'JPMorgan Chase',     'Finance',     false),
  _AssetMeta('GS',    'Goldman Sachs',      'Finance',     false),
  // Healthcare
  _AssetMeta('JNJ',   'Johnson & Johnson',  'Healthcare',  false),
  _AssetMeta('PFE',   'Pfizer Inc.',        'Healthcare',  false),
  // ETFs
  _AssetMeta('SPY',   'S&P 500 ETF',        'ETF',         false),
  _AssetMeta('QQQ',   'Nasdaq-100 ETF',     'ETF',         false),
  _AssetMeta('ARKK',  'ARK Innovation ETF', 'ETF',         false),
  // E-commerce
  _AssetMeta('AMZN',  'Amazon.com Inc.',    'Tech',        false),
];

const _defaultCrypto = [
  _AssetMeta('BTC',  'Bitcoin',   'Crypto', true),
  _AssetMeta('ETH',  'Ethereum',  'Crypto', true),
  _AssetMeta('SOL',  'Solana',    'Crypto', true),
  _AssetMeta('ADA',  'Cardano',   'Crypto', true),
  _AssetMeta('XRP',  'Ripple',    'Crypto', true),
  _AssetMeta('DOGE', 'Dogecoin',  'Crypto', true),
];

// ── Category definitions ──────────────────────────────────────────────────────

class _Category {
  final String label;
  final String emoji;
  final List<String> symbols;
  const _Category({required this.label, required this.emoji, required this.symbols});
}

const _allAssets = [..._defaultStocks, ..._defaultCrypto];

const _categories = [
  _Category(label: 'Tech',       emoji: '💻', symbols: ['AAPL','MSFT','GOOGL','META','AMZN']),
  _Category(label: 'AI',         emoji: '🤖', symbols: ['NVDA','AMD','PLTR','MSFT','GOOGL']),
  _Category(label: 'EV',         emoji: '⚡', symbols: ['TSLA','RIVN']),
  _Category(label: 'Energy',     emoji: '🛢️', symbols: ['XOM','CVX']),
  _Category(label: 'Finance',    emoji: '🏦', symbols: ['BRK.B','JPM','GS']),
  _Category(label: 'Healthcare', emoji: '💊', symbols: ['JNJ','PFE']),
  _Category(label: 'Crypto',     emoji: '₿',  symbols: ['BTC','ETH','SOL','ADA','XRP','DOGE']),
  _Category(label: 'ETFs',       emoji: '📦', symbols: ['SPY','QQQ','ARKK']),
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

  // category browsing
  String? _selectedCategory; // null = show all carousels

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
    final allSymbols = _allAssets.map((s) => s.ticker).toList();
    var quotes = await _backend.getQuotes(allSymbols);

    // Fall back to Binance for any crypto the backend missed
    final cryptoSymbols = _defaultCrypto.map((s) => s.ticker).toList();
    final missingCrypto = cryptoSymbols
        .where((s) => !quotes.containsKey(s.toUpperCase()))
        .toList();
    if (missingCrypto.isNotEmpty) {
      final binanceQuotes = await _fetchBinanceCrypto(missingCrypto);
      quotes = {...quotes, ...binanceQuotes};
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

  List<_AssetMeta> get _categoryAssets {
    if (_selectedCategory == null) return _allAssets.toList();
    final cat = _categories.firstWhere(
      (c) => c.label == _selectedCategory,
      orElse: () => const _Category(label: '', emoji: '', symbols: []),
    );
    return _allAssets.where((a) => cat.symbols.contains(a.ticker)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showCarousels = _selectedCategory == null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        title: const Text('Markets',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
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
              // ── Coaching tip ────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _CoachingMessageBox(
                    pageController: _coachingPageController,
                    onPageChanged: (i) => setState(() => _currentCoachingIndex = i),
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // ── Category chips ───────────────────────────────────────────────
              SliverToBoxAdapter(
                child: _CategoryChips(
                  selected: _selectedCategory,
                  onSelected: (cat) => setState(() {
                    _selectedCategory = (_selectedCategory == cat) ? null : cat;
                  }),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // ── Category filtered list OR default carousels ─────────────────
              if (!showCarousels) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        Text(
                          _selectedCategory ?? '',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            '${_categoryAssets.length} assets',
                            style: const TextStyle(
                              fontSize: 11, color: Color(0xFF06B6D4), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final asset = _categoryAssets[i];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: _AssetRow(asset: _toSummary(asset), loading: _loading),
                      );
                    },
                    childCount: _categoryAssets.length,
                  ),
                ),
              ] else ...[
                // Stocks carousel section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Stocks',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700, color: Colors.white)),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => MarketViewAllScreen(
                              assets: _defaultStocks.map(_toSummary).toList(),
                              isCrypto: false,
                            ),
                          )),
                          child: const Text('See all',
                              style: TextStyle(color: Color(0xFF06B6D4), fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _AssetCarousel(
                    assets: _defaultStocks.take(5).map(_toSummary).toList(),
                    loading: _loading,
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 16)),

                // Crypto carousel section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Crypto',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700, color: Colors.white)),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => MarketViewAllScreen(
                              assets: _defaultCrypto.map(_toSummary).toList(),
                              isCrypto: true,
                            ),
                          )),
                          child: const Text('See all',
                              style: TextStyle(color: Color(0xFF06B6D4), fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _AssetCarousel(
                    assets: _defaultCrypto.map(_toSummary).toList(),
                    loading: _loading,
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 20)),

                // Quick Insights
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _QuickMarketInsights(),
                  ),
                ),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Category Chips ─────────────────────────────────────────────────────────────

class _CategoryChips extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelected;
  const _CategoryChips({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const BouncingScrollPhysics(),
        itemCount: _categories.length,
        itemBuilder: (context, i) {
          final cat = _categories[i];
          final isSelected = selected == cat.label;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: () => onSelected(cat.label),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? const LinearGradient(
                            colors: [Color(0xFF06B6D4), Color(0xFF0891B2)],
                          )
                        : null,
                    color: isSelected ? null : const Color(0xFF111925),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? Colors.transparent
                          : const Color(0xFF1E2D3D),
                    ),
                    boxShadow: isSelected
                        ? [
                            const BoxShadow(
                              color: Color(0x4006B6D4),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(cat.emoji, style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 5),
                      Text(
                        cat.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : Colors.white60,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Asset Row (for category filter list view) ─────────────────────────────────

class _AssetRow extends StatelessWidget {
  final StockSummary asset;
  final bool loading;
  const _AssetRow({required this.asset, required this.loading});

  @override
  Widget build(BuildContext context) {
    final isPositive = asset.changePercent >= 0;
    final changeColor = isPositive ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    final priceStr = asset.price > 0
        ? '\$${asset.price.toStringAsFixed(asset.price < 1 ? 4 : 2)}'
        : '—';

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AssetChartScreen(stock: asset)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1520),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1A2535), width: 0.5),
        ),
        child: Row(
          children: [
            // Icon/ticker badge
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: asset.isCrypto
                      ? [const Color(0xFFF59E0B), const Color(0xFFD97706)]
                      : [const Color(0xFF06B6D4), const Color(0xFF0891B2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                asset.ticker.length <= 3 ? asset.ticker : asset.ticker.substring(0, 3),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Name + sector
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.ticker,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    asset.name,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Price + change
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                loading
                    ? Container(
                        width: 64, height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white10, borderRadius: BorderRadius.circular(4)),
                      )
                    : Text(
                        priceStr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                const SizedBox(height: 4),
                loading
                    ? Container(
                        width: 44, height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white10, borderRadius: BorderRadius.circular(4)),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: changeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: changeColor.withValues(alpha: 0.3), width: 0.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                              color: changeColor, size: 10),
                            const SizedBox(width: 2),
                            Text(
                              '${isPositive ? '+' : ''}${asset.changePercent.toStringAsFixed(2)}%',
                              style: TextStyle(
                                color: changeColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
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
