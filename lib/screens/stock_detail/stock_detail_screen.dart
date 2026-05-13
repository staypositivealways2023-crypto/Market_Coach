// StockDetailScreen — Phase 2, A1–A6
// MooMoo-style stock detail: price header · TradingView chart · key stats ·
// analyst consensus · news feed · AI analysis card.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/candle.dart';
import '../../models/fundamentals.dart';
import '../../models/market_detail.dart';
import '../../models/signal_analysis.dart';
import '../../models/stock_summary.dart';
import '../../providers/news_provider.dart';
import '../../services/backend_service.dart';
import '../../services/candle_service.dart';
import '../../utils/crypto_helper.dart';
import '../../widgets/chart/tv_chart_widget.dart';
import '../../widgets/fundamentals_card.dart';
import '../../widgets/realtime/price_hero_widget.dart';
import '../../features/chart/widgets/timeframe_selector.dart';
import '../../providers/watchlist_service_provider.dart';
import '../../providers/auth_provider.dart';

// ─── Colours ────────────────────────────────────────────────────────────────
const _kBg      = Color(0xFF0D131A);
const _kCard    = Color(0xFF111925);
const _kGreen   = Color(0xFF26A69A);
const _kRed     = Color(0xFFEF5350);
const _kLabel   = Color(0xFF8A95A3);
const _kAccent  = Color(0xFF12A28C);

// ────────────────────────────────────────────────────────────────────────────

class StockDetailScreen extends ConsumerStatefulWidget {
  final StockSummary stock;

  const StockDetailScreen({super.key, required this.stock});

  @override
  ConsumerState<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends ConsumerState<StockDetailScreen> {
  final _backend = BackendService();
  final _candleService = BinanceCandleService();

  // Chart state
  List<Candle> _candles = [];
  String _timeframe = '1D';
  TvChartType _chartType = TvChartType.candlestick;
  bool _chartLoading = true;

  // Data
  MarketRange? _range;
  FundamentalData? _fundamentals;
  SignalAnalysis? _signal;
  StreamSubscription<List<Candle>>? _candleSub;

  // AI analysis
  bool _aiLoading = false;
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

  // ── Data loading ────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    _loadCandles();
    final results = await Future.wait([
      _backend.getPriceRange(widget.stock.ticker),
      _backend.getFundamentals(widget.stock.ticker),
    ]);
    if (!mounted) return;
    setState(() {
      _range        = results[0] as MarketRange?;
      _fundamentals = results[1] as FundamentalData?;
    });

    // Check watchlist
    final user = ref.read(authStateProvider).value;
    if (user != null) {
      final ws = ref.read(watchlistServiceProvider);
      final inList = await ws.isInWatchlist(widget.stock.ticker);
      if (mounted) setState(() => _inWatchlist = inList);
    }
  }

  Future<void> _loadCandles() async {
    setState(() { _chartLoading = true; _candles = []; });
    _candleSub?.cancel();

    if (isCryptoSymbol(widget.stock.ticker)) {
      final interval = _binanceInterval(_timeframe);
      _candleSub = _candleService
          .streamCandles(widget.stock.ticker, interval: interval)
          .listen((candles) {
        if (mounted) setState(() { _candles = candles; _chartLoading = false; });
      });
    } else {
      // Stocks → backend (Alpha Vantage / Yahoo)
      final interval = _stockInterval(_timeframe);
      final limit    = _stockLimit(_timeframe);
      final raw      = await _backend.getCandles(
        widget.stock.ticker,
        interval: interval,
        limit: limit,
      );
      if (!mounted) return;
      setState(() {
        _candles = raw.map((m) => Candle.fromMap(m)).toList();
        _chartLoading = false;
      });
    }
  }

  Future<void> _loadAI() async {
    if (_aiLoading) return;
    setState(() { _aiLoading = true; _aiError = null; });
    try {
      // Use the same interval as the currently selected chart timeframe so
      // AI indicators match what the user sees (not stale daily values).
      final interval = _stockInterval(_timeframe);
      final result = await _backend.analyseStock(
        widget.stock.ticker,
        interval: interval,
      );
      if (mounted) {
        setState(() {
          _aiText    = result?.analysis;
          _aiLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _aiError = e.toString(); _aiLoading = false; });
    }
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

  String _stockInterval(String tf) {
    switch (tf) {
      case '1m':  return '1m';
      case '5m':  return '5m';
      case '15m': return '15m';
      case '30m': return '30m';
      case '1h':  return '1h';
      case '4h':  return '4h';
      case '1D':  return '1d';
      case '1W':  return '1wk';
      case '1M': case '3M': case '6M': return '1mo';
      case '1Y': case '5Y': return '1mo';
      default:    return '1d';
    }
  }

  int _stockLimit(String tf) {
    switch (tf) {
      case '1m':  return 120;
      case '5m':  return 288;
      case '15m': return 192;
      case '30m': return 96;
      case '1h':  return 168;
      case '4h':  return 180;
      case '1D':  return 200;
      case '1W':  return 104;
      case '1M':  return 30;
      case '3M':  return 90;
      case '6M':  return 180;
      case '1Y':  return 365;
      case '5Y':  return 260;
      default:    return 200;
    }
  }

  String _fmt(double? v, {int dp = 2}) {
    if (v == null) return '—';
    if (v >= 1e12) return '\$${(v / 1e12).toStringAsFixed(1)}T';
    if (v >= 1e9)  return '\$${(v / 1e9).toStringAsFixed(2)}B';
    if (v >= 1e6)  return '\$${(v / 1e6).toStringAsFixed(2)}M';
    return v.toStringAsFixed(dp);
  }

  String _fmtVol(int? v) {
    if (v == null) return '—';
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(2)}B';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(0)}K';
    return v.toString();
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

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isPositive = widget.stock.changePercent >= 0;

    return Scaffold(
      backgroundColor: _kBg,
      body: CustomScrollView(
        slivers: [
          // ─ App Bar ────────────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: _kBg,
            pinned: true,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.stock.ticker,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                if (widget.stock.name.isNotEmpty &&
                    widget.stock.name != widget.stock.ticker)
                  Text(
                    widget.stock.name,
                    style: const TextStyle(fontSize: 11, color: _kLabel),
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
                tooltip: _inWatchlist ? 'Remove from watchlist' : 'Add to watchlist',
              ),
              const SizedBox(width: 8),
            ],
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ─ A1 Price Hero ─────────────────────────────────────────
                PriceHeroWidget(
                  stock: widget.stock,
                  marketRange: _range,
                ),

                const SizedBox(height: 4),

                // ─ A2 Chart ──────────────────────────────────────────────
                _buildChartSection(),

                const SizedBox(height: 16),

                // ─ A3 Key Stats Bar ───────────────────────────────────────
                _buildKeyStats(),

                const SizedBox(height: 16),

                // ─ A4 Fundamentals / Analyst panel ───────────────────────
                if (_fundamentals != null && !_fundamentals!.isCrypto)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: FundamentalsCard(data: _fundamentals!),
                  ),

                const SizedBox(height: 16),

                // ─ A5 News feed ───────────────────────────────────────────
                _buildNewsSection(),

                const SizedBox(height: 16),

                // ─ A6 AI Analysis card ────────────────────────────────────
                _buildAiCard(),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── A2 Chart section ───────────────────────────────────────────────────

  Widget _buildChartSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Chart type toggle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _chartTypeBtn(TvChartType.candlestick, Icons.candlestick_chart, 'Candles'),
              const SizedBox(width: 8),
              _chartTypeBtn(TvChartType.line, Icons.show_chart, 'Line'),
              const SizedBox(width: 8),
              _chartTypeBtn(TvChartType.area, Icons.area_chart, 'Area'),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Chart — show loading shimmer or TV chart
        _chartLoading && _candles.isEmpty
            ? Container(
                height: 320,
                color: _kCard,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: _kAccent, strokeWidth: 2),
                      SizedBox(height: 12),
                      Text('Loading chart…', style: TextStyle(color: _kLabel, fontSize: 12)),
                    ],
                  ),
                ),
              )
            : TvChartWidget(
                candles: _candles,
                chartType: _chartType,
                timeframe: _timeframe,
                height: 320,
              ),

        const SizedBox(height: 8),

        // Timeframe selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TimeframeSelector(
            selectedTimeframe: _timeframe,
            onChanged: (tf) {
              if (tf == _timeframe) return;
              setState(() => _timeframe = tf);
              _loadCandles();
            },
            isCrypto: isCryptoSymbol(widget.stock.ticker),
          ),
        ),
      ],
    );
  }

  Widget _chartTypeBtn(TvChartType type, IconData icon, String label) {
    final selected = _chartType == type;
    return GestureDetector(
      onTap: () => setState(() => _chartType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? _kAccent.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? _kAccent : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: selected ? _kAccent : _kLabel),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: selected ? _kAccent : _kLabel,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── A3 Key Stats ───────────────────────────────────────────────────────

  Widget _buildKeyStats() {
    final r  = _range;
    final fd = _fundamentals;

    final stats = <_Stat>[
      _Stat('Open',       r?.open    != null ? '\$${r!.open!.toStringAsFixed(2)}' : '—'),
      _Stat('Prev Close', r?.previousClose != null ? '\$${r!.previousClose!.toStringAsFixed(2)}' : '—'),
      _Stat('Day High',   r?.dayHigh  != null ? '\$${r!.dayHigh!.toStringAsFixed(2)}' : '—'),
      _Stat('Day Low',    r?.dayLow   != null ? '\$${r!.dayLow!.toStringAsFixed(2)}' : '—'),
      _Stat('52W High',   r?.yearHigh != null ? '\$${r!.yearHigh!.toStringAsFixed(2)}' : '—'),
      _Stat('52W Low',    r?.yearLow  != null ? '\$${r!.yearLow!.toStringAsFixed(2)}' : '—'),
      // Volume: prefer direct field, fallback to turnover computation
      _Stat('Volume',     r?.volume != null ? _fmtVol(r!.volume) : _fmt(r?.turnover)),
      // Market cap: prefer backend range field, then StockSummary, then turnover
      _Stat('Mkt Cap',    _fmt(r?.marketCap ?? widget.stock.marketCap ?? r?.turnover)),
      if (fd != null && !fd.isCrypto) ...[
        _Stat('P/E',      fd.pe?.toStringAsFixed(1) ?? '—'),
        _Stat('EPS (TTM)', fd.ttmEps?.toStringAsFixed(2) ?? '—'),
        _Stat('Gross Mgn', fd.grossMargin != null
            ? '${(fd.grossMargin! * 100).toStringAsFixed(1)}%' : '—'),
        _Stat('Net Mgn',   fd.netMargin != null
            ? '${(fd.netMargin! * 100).toStringAsFixed(1)}%' : '—'),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'KEY STATS',
                style: TextStyle(
                  color: _kLabel,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 3.0,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: stats.length,
              itemBuilder: (_, i) => _statTile(stats[i]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(_Stat s) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: _kBg.withOpacity(0.6),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(s.label, style: const TextStyle(color: _kLabel, fontSize: 11)),
        Text(s.value,
            style: const TextStyle(color: Colors.white, fontSize: 12,
                fontWeight: FontWeight.w600)),
      ],
    ),
  );

  // ─── A5 News feed ───────────────────────────────────────────────────────

  Widget _buildNewsSection() {
    final newsAsync = ref.watch(tickerNewsProvider(widget.stock.ticker));
    return newsAsync.when(
      loading: () => const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2)),
      ),
      error: (e, _) => const SizedBox.shrink(),
      data: (articles) {
        if (articles.isEmpty) return const SizedBox.shrink();
        final shown = articles.take(5).toList();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'NEWS',
                style: TextStyle(
                  color: _kLabel, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 0.8,
                ),
              ),
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
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(10),
        ),
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
                  child: Text(
                    a.sentimentLabel.toUpperCase(),
                    style: TextStyle(color: sentColor, fontSize: 9, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                Text(a.source, style: const TextStyle(color: _kLabel, fontSize: 10)),
                const Spacer(),
                Text(a.formattedDate, style: const TextStyle(color: _kLabel, fontSize: 10)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              a.title,
              style: const TextStyle(color: Colors.white, fontSize: 13,
                  fontWeight: FontWeight.w500, height: 1.4),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (a.description != null && a.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                a.description!,
                style: const TextStyle(color: _kLabel, fontSize: 11, height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── A6 AI Analysis card ────────────────────────────────────────────────

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
                    color: _kAccent.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome, size: 14, color: _kAccent),
                ),
                const SizedBox(width: 10),
                const Text(
                  'AI ANALYSIS',
                  style: TextStyle(color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w700, letterSpacing: 0.5),
                ),
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
                  p:      const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                  h2:     const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                  h3:     const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  code:   const TextStyle(color: _kAccent, fontFamily: 'monospace', fontSize: 12),
                  blockquoteDecoration: BoxDecoration(
                    border: Border(left: BorderSide(color: _kAccent, width: 3)),
                  ),
                ),
              )
            else
              Column(
                children: [
                  const Text(
                    'Get Claude\'s full AI analysis of this stock — technicals, fundamentals, sentiment and scenarios.',
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

// ─── Simple stat model ──────────────────────────────────────────────────────

class _Stat {
  final String label;
  final String value;
  const _Stat(this.label, this.value);
}
