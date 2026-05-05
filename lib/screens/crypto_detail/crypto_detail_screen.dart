// CryptoDetailScreen — Phase 2, B1–B4
// MooMoo-style crypto detail: live price header · TradingView chart ·
// key metrics (mkt cap / vol / supply) · AI analysis card.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/candle.dart';
import '../../models/market_detail.dart';
import '../../models/stock_summary.dart';
import '../../providers/auth_provider.dart';
import '../../providers/news_provider.dart';
import '../../providers/watchlist_service_provider.dart';
import '../../services/backend_service.dart';
import '../../services/candle_service.dart';
import '../../widgets/chart/tv_chart_widget.dart';
import '../../features/chart/widgets/timeframe_selector.dart';
import 'package:url_launcher/url_launcher.dart';

// ─── Colours (same palette) ──────────────────────────────────────────────────
const _kBg     = Color(0xFF0D131A);
const _kCard   = Color(0xFF111925);
const _kGreen  = Color(0xFF26A69A);
const _kRed    = Color(0xFFEF5350);
const _kLabel  = Color(0xFF8A95A3);
const _kAccent = Color(0xFF12A28C);

// ─────────────────────────────────────────────────────────────────────────────

class CryptoDetailScreen extends ConsumerStatefulWidget {
  final StockSummary stock;

  const CryptoDetailScreen({super.key, required this.stock});

  @override
  ConsumerState<CryptoDetailScreen> createState() => _CryptoDetailScreenState();
}

class _CryptoDetailScreenState extends ConsumerState<CryptoDetailScreen> {
  final _backend      = BackendService();
  final _candleService = BinanceCandleService();

  // Live price from Binance candle stream
  double? _livePrice;
  double? _livePricePrev;   // previous tick — used to flash colour
  String _timeframe = '1h'; // default for crypto
  TvChartType _chartType = TvChartType.candlestick;

  List<Candle> _candles = [];
  bool _chartLoading = true;
  StreamSubscription<List<Candle>>? _candleSub;

  MarketRange? _range;

  // AI
  bool  _aiLoading = false;
  String? _aiText;
  String? _aiError;

  // Watchlist
  bool _inWatchlist = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _candleSub?.cancel();
    super.dispose();
  }

  // ── Loading ──────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    _subscribeCandles();
    final r = await _backend.getPriceRange(widget.stock.ticker);
    if (mounted) setState(() => _range = r);

    // Watchlist check
    final user = ref.read(authStateProvider).value;
    if (user != null) {
      final ws = ref.read(watchlistServiceProvider);
      final inList = await ws.isInWatchlist(widget.stock.ticker);
      if (mounted) setState(() => _inWatchlist = inList);
    }
  }

  void _subscribeCandles() {
    setState(() { _chartLoading = true; _candles = []; });
    _candleSub?.cancel();
    final interval = _binanceInterval(_timeframe);
    _candleSub = _candleService
        .streamCandles(widget.stock.ticker, interval: interval)
        .listen((candles) {
      if (!mounted) return;
      setState(() {
        _candles = candles;
        _chartLoading = false;
        if (candles.isNotEmpty) {
          final newPrice = candles.last.close;
          if (_livePrice != null && newPrice != _livePrice) {
            _livePricePrev = _livePrice;
          }
          _livePrice = newPrice;
        }
      });
    });
  }

  Future<void> _loadAI() async {
    if (_aiLoading) return;
    setState(() { _aiLoading = true; _aiError = null; });
    try {
      final result = await _backend.analyseStock(widget.stock.ticker, interval: '1h');
      if (mounted) setState(() { _aiText = result?.analysis; _aiLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _aiError = e.toString(); _aiLoading = false; });
    }
  }

  Future<void> _toggleWatchlist() async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;
    final ws = ref.read(watchlistServiceProvider);
    if (_inWatchlist) {
      await ws.removeFromWatchlist(widget.stock.ticker);
    } else {
      await ws.addToWatchlist(widget.stock.ticker);
    }
    if (mounted) setState(() => _inWatchlist = !_inWatchlist);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _binanceInterval(String tf) {
    switch (tf) {
      case '1m':  return '1m';
      case '5m':  return '5m';
      case '15m': return '15m';
      case '30m': return '30m';
      case '1h':  return '1h';
      case '2h':  return '2h';
      case '4h':  return '4h';
      case '12h': return '12h';
      default:    return '1d';
    }
  }

  String _fmtPrice(double? v) {
    if (v == null) return '—';
    if (v >= 10000) return NumberFormat('#,##0').format(v);
    if (v >= 1)     return v.toStringAsFixed(2);
    if (v >= 0.01)  return v.toStringAsFixed(4);
    return v.toStringAsFixed(8);
  }

  String _fmtLarge(double? v) {
    if (v == null) return '—';
    if (v >= 1e12) return '\$${(v / 1e12).toStringAsFixed(2)}T';
    if (v >= 1e9)  return '\$${(v / 1e9).toStringAsFixed(2)}B';
    if (v >= 1e6)  return '\$${(v / 1e6).toStringAsFixed(2)}M';
    return '\$${v.toStringAsFixed(2)}';
  }

  String _fmtVol(int? v) {
    if (v == null) return '—';
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(2)}B';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(0)}K';
    return v.toString();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final price      = _livePrice ?? widget.stock.price;
    final changePct  = widget.stock.changePercent;
    final isPositive = changePct >= 0;

    // Flash colour: green if price ticked up, red if down
    Color priceColor = Colors.white;
    if (_livePricePrev != null && _livePrice != null) {
      priceColor = _livePrice! >= _livePricePrev! ? _kGreen : _kRed;
    }

    return Scaffold(
      backgroundColor: _kBg,
      body: CustomScrollView(
        slivers: [
          // ─ AppBar ────────────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: _kBg,
            pinned: true,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Row(
              children: [
                _cryptoIcon(widget.stock.ticker),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.stock.ticker,
                      style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white,
                      ),
                    ),
                    Text(
                      widget.stock.name,
                      style: const TextStyle(fontSize: 10, color: _kLabel),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _inWatchlist ? Icons.bookmark : Icons.bookmark_border,
                  color: _inWatchlist ? _kAccent : Colors.white54,
                ),
                onPressed: _toggleWatchlist,
              ),
              const SizedBox(width: 8),
            ],
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ─ B1 Live Price Header ───────────────────────────────
                _buildPriceHeader(price, changePct, isPositive, priceColor),

                const SizedBox(height: 4),

                // ─ B2 Chart ───────────────────────────────────────────
                _buildChartSection(),

                const SizedBox(height: 16),

                // ─ B3 Key Metrics ─────────────────────────────────────
                _buildKeyMetrics(),

                const SizedBox(height: 16),

                // News
                _buildNewsSection(),

                const SizedBox(height: 16),

                // ─ B4 AI Analysis ─────────────────────────────────────
                _buildAiCard(),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── B1 Price Header ─────────────────────────────────────────────────────

  Widget _buildPriceHeader(
      double price, double changePct, bool isPositive, Color priceColor) {
    final absChange = _range?.previousClose != null
        ? price - _range!.previousClose!
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Live price
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: priceColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            child: Text('\$${_fmtPrice(price)}'),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isPositive ? _kGreen : _kRed).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${isPositive ? '+' : ''}${changePct.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: isPositive ? _kGreen : _kRed,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              if (absChange != null) ...[
                const SizedBox(width: 8),
                Text(
                  '${absChange >= 0 ? '+' : ''}\$${_fmtPrice(absChange.abs())}  today',
                  style: TextStyle(
                    color: absChange >= 0 ? _kGreen : _kRed,
                    fontSize: 12,
                  ),
                ),
              ],
              const Spacer(),
              // Live indicator
              if (_candleSub != null)
                Row(
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: const BoxDecoration(
                        color: _kGreen, shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('LIVE',
                        style: TextStyle(color: _kGreen, fontSize: 9,
                            fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cryptoIcon(String ticker) {
    final colors = {
      'BTC': const Color(0xFFF7931A),
      'ETH': const Color(0xFF627EEA),
      'SOL': const Color(0xFF9945FF),
      'BNB': const Color(0xFFF3BA2F),
      'XRP': const Color(0xFF00AAE4),
      'ADA': const Color(0xFF0033AD),
      'DOGE': const Color(0xFFC2A633),
    };
    final c = colors[ticker.toUpperCase()] ?? _kAccent;
    return Container(
      width: 30, height: 30,
      decoration: BoxDecoration(color: c.withOpacity(0.15), shape: BoxShape.circle),
      child: Center(
        child: Text(
          ticker.length >= 2 ? ticker[0] : ticker,
          style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 14),
        ),
      ),
    );
  }

  // ─── B2 Chart ────────────────────────────────────────────────────────────

  Widget _buildChartSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _typeBtn(TvChartType.candlestick, Icons.candlestick_chart, 'Candles'),
              const SizedBox(width: 8),
              _typeBtn(TvChartType.line, Icons.show_chart, 'Line'),
              const SizedBox(width: 8),
              _typeBtn(TvChartType.area, Icons.area_chart, 'Area'),
            ],
          ),
        ),
        const SizedBox(height: 8),

        _chartLoading && _candles.isEmpty
            ? Container(
                height: 320, color: _kCard,
                child: const Center(
                  child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2),
                ),
              )
            : TvChartWidget(
                candles: _candles,
                chartType: _chartType,
                height: 320,
              ),

        const SizedBox(height: 8),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TimeframeSelector(
            selectedTimeframe: _timeframe,
            onChanged: (tf) {
              if (tf == _timeframe) return;
              setState(() => _timeframe = tf);
              _subscribeCandles();
            },
            isCrypto: true,
          ),
        ),
      ],
    );
  }

  Widget _typeBtn(TvChartType type, IconData icon, String label) {
    final sel = _chartType == type;
    return GestureDetector(
      onTap: () => setState(() => _chartType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: sel ? _kAccent.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: sel ? _kAccent : Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: sel ? _kAccent : _kLabel),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                  fontSize: 11, color: sel ? _kAccent : _kLabel,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                )),
          ],
        ),
      ),
    );
  }

  // ─── B3 Key Metrics ───────────────────────────────────────────────────────

  Widget _buildKeyMetrics() {
    final r = _range;
    final metrics = <_Metric>[
      _Metric('Market Cap',    _fmtLarge(r?.marketCap ?? widget.stock.marketCap),
          Icons.pie_chart_outline),
      _Metric('24h Volume',    _fmtVol(r?.volume), Icons.bar_chart),
      _Metric('24h High',      r?.dayHigh  != null ? '\$${_fmtPrice(r!.dayHigh!)}' : '—',
          Icons.arrow_upward),
      _Metric('24h Low',       r?.dayLow   != null ? '\$${_fmtPrice(r!.dayLow!)}' : '—',
          Icons.arrow_downward),
      _Metric('52W High',      r?.yearHigh != null ? '\$${_fmtPrice(r!.yearHigh!)}' : '—',
          Icons.trending_up),
      _Metric('52W Low',       r?.yearLow  != null ? '\$${_fmtPrice(r!.yearLow!)}' : '—',
          Icons.trending_down),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: _kCard, borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Text('KEY METRICS',
                  style: TextStyle(color: _kLabel, fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            ),
            ...metrics.map((m) => _metricRow(m)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _metricRow(_Metric m) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
    child: Row(
      children: [
        Icon(m.icon, size: 14, color: _kLabel),
        const SizedBox(width: 10),
        Text(m.label, style: const TextStyle(color: _kLabel, fontSize: 12)),
        const Spacer(),
        Text(m.value,
            style: const TextStyle(color: Colors.white, fontSize: 13,
                fontWeight: FontWeight.w600)),
      ],
    ),
  );

  // ─── News ─────────────────────────────────────────────────────────────────

  Widget _buildNewsSection() {
    final newsAsync = ref.watch(tickerNewsProvider(widget.stock.ticker));
    return newsAsync.when(
      loading: () => const SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2)),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (articles) {
        if (articles.isEmpty) return const SizedBox.shrink();
        final shown = articles.take(4).toList();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('NEWS',
                  style: TextStyle(color: _kLabel, fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 10),
              ...shown.map((a) => _newsCard(a)),
            ],
          ),
        );
      },
    );
  }

  Widget _newsCard(NewsArticleItem a) {
    final sentColor = a.sentimentScore > 0.1
        ? _kGreen
        : a.sentimentScore < -0.1 ? _kRed : _kLabel;
    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(a.url);
        if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: sentColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(a.sentimentLabel.toUpperCase(),
                      style: TextStyle(color: sentColor, fontSize: 9,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Text(a.source, style: const TextStyle(color: _kLabel, fontSize: 10)),
                const Spacer(),
                Text(a.formattedDate, style: const TextStyle(color: _kLabel, fontSize: 10)),
              ],
            ),
            const SizedBox(height: 6),
            Text(a.title,
                style: const TextStyle(color: Colors.white, fontSize: 13,
                    fontWeight: FontWeight.w500, height: 1.4),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  // ─── B4 AI Analysis ──────────────────────────────────────────────────────

  Widget _buildAiCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kAccent.withOpacity(0.25)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: _kAccent.withOpacity(0.15), shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome, size: 14, color: _kAccent),
                ),
                const SizedBox(width: 10),
                const Text('AI ANALYSIS',
                    style: TextStyle(color: Colors.white, fontSize: 13,
                        fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                const Spacer(),
                if (_aiText != null)
                  GestureDetector(
                    onTap: _loadAI,
                    child: const Icon(Icons.refresh, size: 16, color: _kLabel),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (_aiLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: _kAccent, strokeWidth: 2),
                      SizedBox(height: 10),
                      Text('Analysing with Claude…',
                          style: TextStyle(color: _kLabel, fontSize: 12)),
                    ],
                  ),
                ),
              )
            else if (_aiError != null)
              Text('Error: $_aiError',
                  style: const TextStyle(color: _kRed, fontSize: 12))
            else if (_aiText != null)
              MarkdownBody(
                data: _aiText!,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                  h2: const TextStyle(color: Colors.white, fontSize: 14,
                      fontWeight: FontWeight.w700),
                  strong: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w700),
                ),
              )
            else
              Column(
                children: [
                  const Text(
                    'Get Claude\'s AI read on this crypto — momentum, sentiment, key levels, and scenario targets.',
                    style: TextStyle(color: _kLabel, fontSize: 12, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _loadAI,
                      icon: const Icon(Icons.auto_awesome, size: 15),
                      label: const Text('Analyse Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
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

// ─── Metric model ────────────────────────────────────────────────────────────

class _Metric {
  final String label;
  final String value;
  final IconData icon;
  const _Metric(this.label, this.value, this.icon);
}
