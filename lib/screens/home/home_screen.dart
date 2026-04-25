import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mock_data.dart';
import '../../models/market_index.dart';
import '../../models/quote.dart';
import '../../models/stock_summary.dart';
import '../../providers/watchlist_service_provider.dart';
import '../../services/quote_service.dart';
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
  // 35s gives Yahoo Finance one full 30-second poll cycle to respond
  // before showing the "Quote unavailable" fallback.
  static const _watchlistQuoteTimeout = Duration(seconds: 35);

  // Backend-powered quote services — handles stocks + crypto uniformly.
  final _indexService = BackendQuoteService();
  final _watchlistService = BackendQuoteService();

  StreamSubscription<Map<String, Quote>>? _watchlistSubscription;
  StreamSubscription<Map<String, Quote>>? _indexSubscription;

  Set<String> _symbols = {};
  final Map<String, Quote> _quotes = {};
  final Map<String, Quote> _indexQuotes = {};
  final Map<String, String> _quoteFailures = {};
  final Map<String, Timer> _quoteTimeouts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initIndexQuotes();
    // Watchlist is loaded reactively from Firestore in build() via ref.listen
  }

  // ── Subscribe to live quotes for a given symbol set ──────────────────────────

  void _subscribeToWatchlistQuotes(Set<String> symbols) {
    // Cancel previous subscription.
    _watchlistSubscription?.cancel();
    _watchlistSubscription = null;

    // Stop the loading spinner immediately; skeleton cards fill in as quotes arrive.
    _syncWatchlistResolutionState(symbols);

    if (mounted) {
      setState(() {
        _symbols = symbols;
        _loading = false;
      });
    }

    if (symbols.isEmpty) return;

    // BackendQuoteService handles stocks + crypto uniformly in one batch call.
    _watchlistSubscription = _watchlistService.streamQuotes(symbols).listen(
      _handleResolvedQuotes,
      onError: (_) => _markSymbolsUnavailable(symbols, reason: 'Quote unavailable'),
    );
  }

  void _syncWatchlistResolutionState(Set<String> symbols) {
    final removedSymbols = {
      ..._quotes.keys.where((symbol) => !symbols.contains(symbol)),
      ..._quoteFailures.keys.where((symbol) => !symbols.contains(symbol)),
      ..._quoteTimeouts.keys.where((symbol) => !symbols.contains(symbol)),
    };

    for (final symbol in removedSymbols) {
      _quoteTimeouts.remove(symbol)?.cancel();
      _quotes.remove(symbol);
      _quoteFailures.remove(symbol);
    }

    for (final symbol in symbols) {
      if (_quotes.containsKey(symbol) || _quoteFailures.containsKey(symbol)) {
        continue;
      }
      _startQuoteTimeout(symbol);
    }
  }

  void _startQuoteTimeout(String symbol) {
    _quoteTimeouts.remove(symbol)?.cancel();
    _quoteTimeouts[symbol] = Timer(_watchlistQuoteTimeout, () {
      if (!mounted || !_symbols.contains(symbol) || _quotes.containsKey(symbol)) {
        return;
      }

      setState(() {
        _quoteFailures[symbol] = 'Quote unavailable';
      });
      _quoteTimeouts.remove(symbol)?.cancel();
    });
  }

  void _handleResolvedQuotes(Map<String, Quote> quotes) {
    if (!mounted || quotes.isEmpty) return;

    setState(() {
      _quotes.addAll(quotes);
      for (final symbol in quotes.keys) {
        _quoteFailures.remove(symbol);
        _quoteTimeouts.remove(symbol)?.cancel();
      }
    });
  }

  void _markSymbolsUnavailable(
    Iterable<String> symbols, {
    required String reason,
  }) {
    if (!mounted) return;

    setState(() {
      for (final symbol in symbols) {
        if (!_quotes.containsKey(symbol)) {
          _quoteFailures[symbol] = reason;
        }
        _quoteTimeouts.remove(symbol)?.cancel();
      }
    });
  }

  // ── Live index quotes (SPY, QQQ, BTC, ETH) ─────────────────────────────────

  void _initIndexQuotes() {
    // Fetch all 4 index proxies in a single backend batch call.
    const allIndexSymbols = {
      ..._indexStockSymbols,
      ..._indexCryptoSymbols,
    };
    _indexSubscription = _indexService.streamQuotes(allIndexSymbols).listen(
      (quotes) {
        if (mounted) setState(() => _indexQuotes.addAll(quotes));
      },
    );
  }

  @override
  void dispose() {
    _watchlistSubscription?.cancel();
    _indexSubscription?.cancel();
    for (final timer in _quoteTimeouts.values) {
      timer.cancel();
    }
    _indexService.dispose();
    _watchlistService.dispose();
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

    // React to Firestore watchlist changes — re-subscribe to quote streams.
    ref.listen<AsyncValue<Set<String>>>(watchlistSymbolsProvider, (prev, next) {
      next.whenData((symbols) {
        if (symbols != _symbols) {
          _subscribeToWatchlistQuotes(symbols);
        }
      });
    });

    // Seed on first load when the stream emits before any listen fires.
    final watchlistAsync = ref.watch(watchlistSymbolsProvider);
    if (_symbols.isEmpty && watchlistAsync.valueOrNull != null) {
      final symbols = watchlistAsync.valueOrNull!;
      if (symbols.isNotEmpty &&
          _watchlistSubscription == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _subscribeToWatchlistQuotes(symbols);
        });
      } else if (symbols.isEmpty && _loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _loading = false);
        });
      }
    }

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
        if (_loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (_symbols.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Column(
                children: [
                  Icon(Icons.bookmark_add_outlined, size: 40, color: Colors.white38),
                  const SizedBox(height: 10),
                  Text(
                    'Your watchlist is empty',
                    style: TextStyle(color: Colors.white54, fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap the ♡ on any stock or crypto to add it here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else
          SliverList.builder(
                itemCount: _symbols.length,
                itemBuilder: (context, index) {
                  final symbol = _symbols.elementAt(index);
                  final quote = _quotes[symbol];
                  final failure = _quoteFailures[symbol];

                  if (quote == null && failure == null) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      child: _WatchlistSkeletonCard(symbol: symbol),
                    );
                  }

                  if (quote == null) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      child: _WatchlistUnavailableCard(
                        symbol: symbol,
                        message: failure ?? 'Quote unavailable',
                      ),
                    );
                  }

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

                  // Swipe-to-remove wrapper
                  return Dismissible(
                    key: ValueKey(symbol),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.bookmark_remove_outlined,
                          color: Colors.redAccent, size: 22),
                    ),
                    confirmDismiss: (_) async {
                      final svc = ref.read(watchlistServiceProvider);
                      await svc.removeFromWatchlist(symbol);
                      return true;
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      child: StockCard(stock: liveStock),
                    ),
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

// ── Watchlist skeleton card ────────────────────────────────────────────────────

class _WatchlistUnavailableCard extends StatelessWidget {
  final String symbol;
  final String message;

  const _WatchlistUnavailableCard({
    required this.symbol,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFFFB020).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFFFB020).withValues(alpha: 0.28),
              ),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFFFB020),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  symbol,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'Unavailable',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFFFFB020),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _WatchlistSkeletonCard extends StatefulWidget {
  final String symbol;
  const _WatchlistSkeletonCard({required this.symbol});

  @override
  State<_WatchlistSkeletonCard> createState() => _WatchlistSkeletonCardState();
}

class _WatchlistSkeletonCardState extends State<_WatchlistSkeletonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.35, end: 0.65).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, __) => Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(_opacity.value * 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            // Ticker shimmer
            Container(
              width: 48,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(_opacity.value * 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            // Name shimmer
            Expanded(
              child: Container(
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(_opacity.value * 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Price shimmer
            Container(
              width: 56,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(_opacity.value * 0.25),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
