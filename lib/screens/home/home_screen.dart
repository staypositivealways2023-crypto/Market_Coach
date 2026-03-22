import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mock_data.dart';
import '../../data/watchlist_repository.dart';
import '../../models/market_index.dart';
import '../../models/quote.dart';
import '../../models/stock_summary.dart';
import '../../services/quote_service.dart';
import '../../utils/crypto_helper.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/iq_score_card.dart';
import '../learn/learn_screen.dart';
import '../profile/profile_screen.dart';
import '../../features/chart/screens/asset_chart_screen.dart';

// ── Ticker symbols used as live index proxies ──────────────────────────────────
const _indexStockSymbols = {'SPY', 'QQQ'};
const _indexCryptoSymbols = {'BTC', 'ETH'};

const _indexNames = {
  'SPY': 'S&P 500',
  'QQQ': 'NASDAQ',
  'BTC': 'Bitcoin',
  'ETH': 'Ethereum',
};

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late WatchlistRepository _repository;
  final _yahooService = YahooQuoteService();
  final _binanceService = BinanceQuoteService();

  StreamSubscription<Map<String, Quote>>? _stockSubscription;
  StreamSubscription<Map<String, Quote>>? _binanceSubscription;
  StreamSubscription<Map<String, Quote>>? _indexStockSubscription;
  StreamSubscription<Map<String, Quote>>? _indexCryptoSubscription;

  Set<String> _symbols = {};
  final Map<String, Quote> _quotes = {};
  final Map<String, Quote> _indexQuotes = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initWatchlist();
    _initIndexQuotes();
  }

  // ── Watchlist quotes ────────────────────────────────────────────────────────

  Future<void> _initWatchlist() async {
    _repository = await WatchlistRepository.create();
    final symbols = await _repository.getWatchlist();

    if (symbols.isEmpty) {
      await _repository.addSymbol('AAPL');
      await _repository.addSymbol('BHP');
      await _repository.addSymbol('BTC');
      _symbols = {'AAPL', 'BHP', 'BTC'};
    } else {
      _symbols = symbols;
    }

    final cryptoSymbols = _symbols.where((s) => isCryptoSymbol(s)).toSet();
    final stockSymbols = _symbols.where((s) => !isCryptoSymbol(s)).toSet();

    if (cryptoSymbols.isNotEmpty) {
      _binanceSubscription =
          _binanceService.streamQuotes(cryptoSymbols).listen((quotes) {
        if (mounted) setState(() { _quotes.addAll(quotes); _loading = false; });
      });
    }
    if (stockSymbols.isNotEmpty) {
      _stockSubscription =
          _yahooService.streamQuotes(stockSymbols).listen((quotes) {
        if (mounted) setState(() { _quotes.addAll(quotes); _loading = false; });
      });
    }
    if (stockSymbols.isEmpty && cryptoSymbols.isNotEmpty) {
      setState(() => _loading = false);
    }
  }

  // ── Live index quotes (SPY, QQQ, BTC, ETH) ─────────────────────────────────

  void _initIndexQuotes() {
    _indexStockSubscription =
        _yahooService.streamQuotes(_indexStockSymbols).listen((quotes) {
      if (mounted) setState(() => _indexQuotes.addAll(quotes));
    });
    _indexCryptoSubscription =
        _binanceService.streamQuotes(_indexCryptoSymbols).listen((quotes) {
      if (mounted) setState(() => _indexQuotes.addAll(quotes));
    });
  }

  @override
  void dispose() {
    _stockSubscription?.cancel();
    _binanceSubscription?.cancel();
    _indexStockSubscription?.cancel();
    _indexCryptoSubscription?.cancel();
    _yahooService.dispose();
    _binanceService.dispose();
    super.dispose();
  }

  // ── Build live MarketIndex list from index quotes ───────────────────────────

  List<MarketIndex> _buildIndexList() {
    final tickers = ['SPY', 'QQQ', 'BTC', 'ETH'];
    final result = <MarketIndex>[];
    for (final t in tickers) {
      final q = _indexQuotes[t];
      if (q != null && q.price > 0) {
        result.add(MarketIndex(
          name: _indexNames[t] ?? t,
          ticker: t,
          value: q.price,
          changePercent: q.changePercent,
        ));
      }
    }
    // Fall back to mock data for any missing entries
    if (result.isEmpty) return [...mockIndices, ...mockCryptoIndices];
    return result;
  }

  // ── Derived sentiment from live index quotes ────────────────────────────────

  String _sentimentLabel(double change) {
    if (change > 1.0) return 'Bullish';
    if (change > 0.2) return 'Leaning Bullish';
    if (change < -1.0) return 'Bearish';
    if (change < -0.2) return 'Leaning Bearish';
    return 'Neutral';
  }

  Color _sentimentColor(double change) {
    if (change > 0.2) return Colors.green[400]!;
    if (change < -0.2) return Colors.red[400]!;
    return Colors.amber[400]!;
  }

  String _volatilityLabel(List<MarketIndex> indices) {
    final maxChange = indices.fold<double>(
        0, (m, idx) => idx.changePercent.abs() > m ? idx.changePercent.abs() : m);
    if (maxChange > 2.5) return 'High — stay cautious, size down';
    if (maxChange > 1.2) return 'Medium — balanced approach';
    return 'Low — steady environment';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Live index data (falls back to mock if not yet loaded)
    final liveMarkets = _buildIndexList();
    final stockIndices =
        liveMarkets.where((m) => m.ticker == 'SPY' || m.ticker == 'QQQ').toList();
    final cryptoIndices =
        liveMarkets.where((m) => m.ticker == 'BTC' || m.ticker == 'ETH').toList();
    final stockChange = _averageChange(
        stockIndices.isEmpty ? mockIndices : stockIndices);
    final cryptoChange = _averageChange(
        cryptoIndices.isEmpty ? mockCryptoIndices : cryptoIndices);

    // Greeting — use Firebase auth display name
    final user = FirebaseAuth.instance.currentUser;
    final firstName = _extractFirstName(user);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LiveMarketsStrip(
                  markets: liveMarkets,
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _MarketOverviewCard(
                        title: 'Stocks overview',
                        change: stockChange,
                        accentColor: colorScheme.primary,
                        toneLabel: _sentimentLabel(stockChange),
                        toneColor: _sentimentColor(stockChange),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MarketOverviewCard(
                        title: 'Crypto overview',
                        change: cryptoChange,
                        accentColor: Colors.deepPurple,
                        toneLabel: _sentimentLabel(cryptoChange),
                        toneColor: _sentimentColor(cryptoChange),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hi, $firstName',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Here's your market coach for today.",
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.account_circle_outlined,
                          color: Colors.white54, size: 28),
                      tooltip: 'Profile',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const ProfileScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const IQScoreCard(),
                const SizedBox(height: 20),
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Market overview',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.info_outline, size: 18, color: Colors.white54),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text('Overall sentiment:', style: theme.textTheme.bodyMedium),
                          const SizedBox(width: 8),
                          Text(
                            _sentimentLabel(_averageChange(liveMarkets)),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: _sentimentColor(_averageChange(liveMarkets)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Volatility: ${_volatilityLabel(liveMarkets)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Your watchlist',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        _loading
            ? const SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator()),
              )
            : SliverList.builder(
                itemCount: _symbols.length,
                itemBuilder: (context, index) {
                  final symbol = _symbols.elementAt(index);
                  final quote = _quotes[symbol];
                  if (quote == null) return const SizedBox.shrink();

                  final mockStock = mockWatchlist.firstWhere(
                    (s) => s.ticker == symbol,
                    orElse: () => StockSummary(
                      ticker: symbol,
                      name: symbol,
                      price: quote.price,
                      changePercent: quote.changePercent,
                    ),
                  );

                  final liveStock = StockSummary(
                    ticker: symbol,
                    name: mockStock.name,
                    price: quote.price,
                    changePercent: quote.changePercent,
                    isCrypto: mockStock.isCrypto,
                    sector: mockStock.sector,
                    industry: mockStock.industry,
                    fundamentals: mockStock.fundamentals,
                    technicalHighlights: mockStock.technicalHighlights,
                  );

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    child: StockCard(stock: liveStock),
                  );
                },
              ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: const TodayLessonCard(),
          ),
        ),
      ],
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

String _extractFirstName(User? user) {
  if (user == null) return 'there';
  if (user.displayName != null && user.displayName!.isNotEmpty) {
    return user.displayName!.split(' ').first;
  }
  if (user.email != null && user.email!.isNotEmpty) {
    return user.email!.split('@').first;
  }
  return 'there';
}

double _averageChange(List<MarketIndex> markets) {
  if (markets.isEmpty) return 0;
  final total = markets.fold<double>(0, (sum, item) => sum + item.changePercent);
  return total / markets.length;
}

double _normalizedChange(double changePercent) =>
    ((changePercent + 4) / 8).clamp(0.0, 1.0);

// ── Widgets ────────────────────────────────────────────────────────────────────

class _LiveMarketsStrip extends StatelessWidget {
  final List<MarketIndex> markets;
  final ColorScheme colorScheme;

  const _LiveMarketsStrip({required this.markets, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 126,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemBuilder: (context, index) {
          final market = markets[index];
          final changeColor =
              market.isPositive ? Colors.green[600]! : Colors.red[600]!;
          return _LiveMarketCard(
            market: market,
            changeColor: changeColor,
            accent: colorScheme.primary,
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemCount: markets.length,
      ),
    );
  }
}

class _LiveMarketCard extends StatelessWidget {
  final MarketIndex market;
  final Color changeColor;
  final Color accent;

  const _LiveMarketCard({
    required this.market,
    required this.changeColor,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      width: 180,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: changeColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: changeColor.withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 1)
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text('Live',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: accent, fontWeight: FontWeight.w600)),
              const Spacer(),
              Icon(Icons.show_chart, size: 16, color: accent),
            ],
          ),
          const SizedBox(height: 10),
          Text(market.ticker,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(market.name,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  market.value >= 10000
                      ? '\$${(market.value / 1000).toStringAsFixed(1)}K'
                      : '\$${market.value.toStringAsFixed(market.value < 10 ? 4 : 2)}',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${market.isPositive ? '+' : ''}${market.changePercent.toStringAsFixed(2)}%',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: changeColor, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MarketOverviewCard extends StatelessWidget {
  final String title;
  final double change;
  final Color accentColor;
  final String toneLabel;
  final Color toneColor;

  const _MarketOverviewCard({
    required this.title,
    required this.change,
    required this.accentColor,
    required this.toneLabel,
    required this.toneColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changeColor = change >= 0 ? Colors.green[600]! : Colors.red[600]!;
    final normalized = _normalizedChange(change);

    return GlassCard(
      color: accentColor.withValues(alpha: 0.15),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(toneLabel,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: toneColor, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _ChangeBar(normalizedValue: normalized, fillColor: changeColor),
          const SizedBox(height: 8),
          Text(
            '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}% today',
            style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600, color: changeColor),
          ),
        ],
      ),
    );
  }
}

class _ChangeBar extends StatelessWidget {
  final double normalizedValue;
  final Color fillColor;

  const _ChangeBar({required this.normalizedValue, required this.fillColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(
                colors: [
                  Colors.red.withValues(alpha: 0.3),
                  Colors.amber.withValues(alpha: 0.4),
                  Colors.green.withValues(alpha: 0.3),
                ],
              ),
            ),
          ),
          FractionallySizedBox(
            widthFactor: normalizedValue,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: fillColor.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stock watchlist card ───────────────────────────────────────────────────────

class StockCard extends StatelessWidget {
  final StockSummary stock;

  const StockCard({super.key, required this.stock});

  String _sentimentLabel(double change) {
    if (change > 1.5) return 'Bullish';
    if (change > 0.3) return 'Mild Up';
    if (change < -1.5) return 'Bearish';
    if (change < -0.3) return 'Mild Down';
    return 'Neutral';
  }

  Color _sentimentColor(double change) {
    if (change > 0.3) return const Color(0xFF22C55E);
    if (change < -0.3) return const Color(0xFFEF4444);
    return const Color(0xFFF59E0B);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changeColor =
        stock.isPositive ? Colors.green[600] : Colors.red[600];
    final sentiment = _sentimentLabel(stock.changePercent);
    final sentimentColor = _sentimentColor(stock.changePercent);

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AssetChartScreen(stock: stock),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      stock.ticker,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    // Sentiment chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: sentimentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                            color: sentimentColor.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        sentiment,
                        style: TextStyle(
                          color: sentimentColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  stock.name,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${stock.price.toStringAsFixed(stock.price < 1 ? 4 : 2)}',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                '${stock.isPositive ? '+' : ''}${stock.changePercent.toStringAsFixed(2)}%',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: changeColor, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class TodayLessonCard extends StatelessWidget {
  const TodayLessonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GlassCard(
      color: colorScheme.primary,
      padding: const EdgeInsets.all(18),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const LearnScreen())),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Learning Centre',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.white70)),
                const SizedBox(height: 6),
                Text(
                  'Browse lessons & build your edge',
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.school_outlined,
                          size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        'Beginner · Intermediate · Advanced',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Colors.white24),
            child: const Icon(Icons.arrow_forward, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
