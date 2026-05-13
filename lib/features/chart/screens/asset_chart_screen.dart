// ignore_for_file: library_private_types_in_public_api
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/candle.dart';
import '../../../models/quote.dart';
import '../../../models/stock_summary.dart';
import '../../../models/enhanced_ai_analysis.dart';
import '../../../models/fundamentals.dart';
import '../../../models/market_detail.dart';
import '../../../models/holding.dart';
import '../../../models/paper_account.dart';
import '../../../models/signal_analysis.dart';
import '../../../services/candle_service.dart';
import '../../../services/quote_service.dart';
import '../../../services/technical_analysis_service.dart';
import '../../../services/backend_service.dart';
import '../../../utils/crypto_helper.dart';
import '../../../widgets/coaching_nudge_card.dart';
import '../../../widgets/guest_gate.dart';
import '../../../providers/auth_provider.dart';
import '../../lesson_engine/lessons/lesson_registry.dart';
import '../../lesson_engine/screens/guided_lesson_screen.dart';
import '../../../widgets/glass_card.dart';
import '../../../widgets/macro_card.dart';
import '../../../widgets/chart/advanced_indicator_settings.dart';
import '../../../widgets/chart/chart_type_selector.dart';
import '../../../widgets/educational_bottom_sheet.dart';
import '../../../widgets/earnings_chart.dart';
import '../../../widgets/fundamentals_card.dart';
import '../../../providers/analysis_provider.dart';
import '../../../providers/portfolio_provider.dart';
import '../../../providers/paper_trading_provider.dart';
import '../../../providers/watchlist_service_provider.dart';
import '../../../screens/analysis/_enhanced_analysis_display.dart';
import '../controllers/chart_controller.dart';
import '../models/chart_overlay.dart';
import '../widgets/market_chart.dart';
import '../widgets/timeframe_selector.dart';
import '../widgets/chart_toolbar.dart';
import '../../../widgets/crew_analysis_sheet.dart';
import '../../../widgets/realtime/price_hero_widget.dart';
import '../../../widgets/realtime/market_position_widget.dart';
import '../../../widgets/realtime/money_flow_widget.dart';
import '../../../widgets/realtime/order_book_widget.dart';
import '../../../widgets/realtime/options_card_widget.dart';
// Phase 5 — realtime Riverpod providers
import '../../../providers/realtime_providers.dart';
import '../../../models/market_flow.dart';
// Phase 8 — Analyst Graph integration
import '../../../models/analyst_response.dart';
import '../../../services/analyst_graph_service.dart';
import '../../../widgets/cot_thinking_card.dart';
import 'package:audioplayers/audioplayers.dart';
// Phase 4 — Probabilistic Engine
import '../../../models/probabilistic_data.dart';
import '../../../widgets/probabilistic_card.dart';
// Phase 8 — Subscription gating + usage analytics
import '../../../providers/subscription_provider.dart';
import '../../../providers/usage_analytics_provider.dart';
import '../../../services/usage_analytics_service.dart';
import '../../../widgets/subscription_gate.dart';

/// Drop-in replacement for StockDetailScreenEnhanced using native CustomPainter charts.
class AssetChartScreen extends ConsumerStatefulWidget {
  final StockSummary stock;
  final bool initialShowRSI;
  final bool initialShowMACD;

  const AssetChartScreen({
    super.key,
    required this.stock,
    this.initialShowRSI = true,   // RSI visible by default
    this.initialShowMACD = false,
  });

  @override
  ConsumerState<AssetChartScreen> createState() => _AssetChartScreenState();
}

class _AssetChartScreenState extends ConsumerState<AssetChartScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final _candleService = BinanceCandleService();
  final _quoteService = BinanceQuoteService();
  final _backendService = BackendService();
  final _chartController = ChartController();

  StreamSubscription<List<Candle>>? _candleSubscription;
  StreamSubscription<Map<String, Quote>>? _quoteSubscription;
  Timer? _stockQuoteTimer;
  // Phase 5 — backend WS price stream
  StreamSubscription<PriceTick>? _priceStreamSub;

  // ── Candles ────────────────────────────────────────────────────────────────
  // _candles    — display slice shown by the chart (e.g. 7 bars for "1W")
  // _allCandles — warmup + display (indicator computation runs on this)
  // Indicators are computed once when candles change and cached here so
  // build() never recomputes them on every frame.
  static const int _kWarmupBars = 50; // extra bars fetched purely for indicator warmup

  List<Candle> _candles = [];
  List<Candle> _allCandles = [];   // warmup + display
  List<double?> _rsiValues  = [];  // aligned to _candles
  Map<String, List<double?>> _macdData = {};  // aligned to _candles

  Quote? _liveQuote;
  // Phase 5 — backend CMF / money flow data
  MoneyFlowData? _moneyFlowData;
  bool _hasError = false;
  bool _isLoading = false;
  String? _errorMessage;

  // Chart controls
  ChartType _chartType = ChartType.candlestick;
  String _timeframe = '1D';
  late bool _showRSI;
  late bool _showMACD;

  // Indicator settings
  MAType _maType = MAType.none;
  bool _showBollingerBands = false;
  bool _showVWAP = false;
  SRType _srType = SRType.none;
  SubChartType _subChartType = SubChartType.rsi;

  // Backend data
  MarketRange? _marketRange;
  FundamentalData? _fundamentals;

  // Signal Engine
  SignalAnalysis? _signalAnalysis;
  bool _signalLoading = true;

  // Macro overview (Phase A)
  MacroOverview? _macroOverview;

  // AI Analysis
  bool _analysisRequested = false;

  // Portfolio
  bool _inPortfolio = false;

  // Chart gesture lock — prevents the parent CustomScrollView from stealing
  // horizontal pan events while the user is interacting with the chart.
  bool _chartInteracting = false;
  final ScrollController _technicalScrollController = ScrollController();

  // ── Phase 4: Probabilistic Engine ─────────────────────────────────────────
  ProbabilisticData? _probabilisticData;

  // ── Phase 8: Analyst Graph (DeepSeek-R1 + LangGraph) ──────────────────────
  final _analystService = AnalystGraphService();
  AnalystResponse? _analystResult;
  bool _analystLoading = false;
  String? _analystError;
  // Audio player for Cartesia TTS output
  final _audioPlayer = AudioPlayer();
  bool _audioPlaying = false;

  double get _chartHeight {
    if (_showRSI && _showMACD) return 500;
    if (_showRSI || _showMACD) return 430;
    return 340;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _showRSI = widget.initialShowRSI;
    _showMACD = widget.initialShowMACD;
    // Keep subChartType in sync with initial show flags
    if (_showRSI) _subChartType = SubChartType.rsi;
    if (_showMACD) _subChartType = SubChartType.macd;
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fetchSignalAnalysis();
        _checkPortfolio();
        _fetchMacroOverview();
        _fetchProbabilistic();
      }
    });
  }

  void _loadData() {
    if (isCryptoSymbol(widget.stock.ticker)) {
      _subscribeToCandles();
      _subscribeToQuotes();
    } else {
      _fetchStockCandles();
    }
    _fetchMarketRange();
    if (!widget.stock.isCrypto) {
      _fetchFundamentals();
      _startStockQuotePolling();
    }
    // Phase 5 — backend WS price stream (stocks: replaces 30s poll;
    // crypto: supplements Binance candle stream with a lightweight tick).
    _subscribeToBackendPriceStream();
    // Phase 5 — fetch CMF / money flow from backend
    _fetchMoneyFlow();
  }

  void _subscribeToBackendPriceStream() {
    _priceStreamSub?.cancel();
    // Listen to the Riverpod StreamProvider's underlying stream.
    _priceStreamSub = ref
        // ignore: deprecated_member_use
        .read(priceStreamProvider(widget.stock.ticker).stream)
        .listen((tick) {
      if (!mounted) return;
      // Only update if the tick represents a meaningful price change.
      if (tick.price > 0 &&
          (_liveQuote == null ||
              (tick.price - _liveQuote!.price).abs() /
                      (_liveQuote!.price > 0 ? _liveQuote!.price : 1) >
                  0.00001)) {
        setState(() => _liveQuote = Quote(
              symbol: widget.stock.ticker,
              price: tick.price,
              changePercent: tick.changePct,
            ));
      }
    }, onError: (_) {/* stream closed — degrade silently */});
  }

  Future<void> _fetchMoneyFlow() async {
    final data = await ref
        .read(moneyFlowProvider(widget.stock.ticker).future);
    if (mounted && data != null) {
      setState(() => _moneyFlowData = data);
    }
  }

  Future<void> _fetchMarketRange() async {
    final range = await _backendService.getPriceRange(widget.stock.ticker);
    if (mounted && range != null) setState(() => _marketRange = range);
  }

  Future<void> _fetchFundamentals() async {
    final data = await _backendService.getFundamentals(widget.stock.ticker);
    if (mounted && data != null) setState(() => _fundamentals = data);
  }

  void _startStockQuotePolling() {
    _stockQuoteTimer?.cancel();
    _pollStockQuote(); // immediate first fetch
    _stockQuoteTimer = Timer.periodic(const Duration(seconds: 30), (_) => _pollStockQuote());
  }

  Future<void> _pollStockQuote() async {
    if (!mounted) return;
    try {
      final data = await _backendService.getQuote(widget.stock.ticker);
      if (mounted && data != null) {
        final price = (data['price'] as num?)?.toDouble();
        final changePct = (data['change_percent'] as num?)?.toDouble();
        if (price != null) {
          setState(() => _liveQuote = Quote(
            symbol: widget.stock.ticker,
            price: price,
            changePercent: changePct ?? 0.0,
          ));
        }
      }
    } catch (_) {}
  }


  Future<void> _fetchMacroOverview() async {
    final data = await _backendService.getMacroOverview();
    if (mounted && data != null) setState(() => _macroOverview = data);
  }

  Future<void> _checkPortfolio() async {
    final service = ref.read(portfolioServiceProvider);
    if (service == null) return;
    final h = await service.getHolding(widget.stock.ticker);
    if (mounted) setState(() => _inPortfolio = h != null);
  }

  /// Maps the chart timeframe to a backend-compatible candle interval.
  /// The signal engine uses the same resolution the user is viewing so
  /// indicators and scenarios are never stale relative to the chart.
  String _backendInterval() {
    if (isCryptoSymbol(widget.stock.ticker)) {
      // Crypto: map short-term frames to minute/hour intervals
      switch (_timeframe) {
        case '1m':  return '1m';
        case '5m':  return '5m';
        case '15m': return '15m';
        case '30m': return '30m';
        case '1h':  return '1h';
        case '2h':  return '2h';
        case '4h':  return '4h';
        case '12h': return '12h';
        case '1D':  return '15m';  // 96 15-min bars = 1 day view
        case '1W':  return '4h';   // 42 4h bars = 1 week view
        case '4W':  return '4h';   // 168 4h bars = 4 week view
        case '1M':  return '1d';
        case '3M':  return '1d';
        case '6M':  return '1d';
        case '1Y':  return '1d';
        case '5Y':  return '1w';
        default:    return '1d';
      }
    } else {
      // Stocks: Alpha Vantage/Yahoo intervals
      switch (_timeframe) {
        case '1m':  return '1m';
        case '5m':  return '5m';
        case '15m': return '15m';
        case '30m': return '30m';
        case '1h':  return '1h';
        case '4h':  return '4h';
        case '1W': case '4W': case '1M': case '3M': case '6M': return '1d';
        case '1Y': case '5Y': return '1wk';
        default:    return '1d';
      }
    }
  }

  Future<void> _fetchSignalAnalysis() async {
    if (!mounted) return;
    setState(() { _signalLoading = true; _signalAnalysis = null; });
    final interval = _backendInterval();
    if (kDebugMode) {
      debugPrint('[AssetChart] fetchSignalAnalysis: ${widget.stock.ticker} '
          'chart_tf=$_timeframe backend_interval=$interval');
    }
    final result = await _backendService.analyseStock(
        widget.stock.ticker, interval: interval);
    if (mounted) setState(() { _signalAnalysis = result; _signalLoading = false; });
  }

  Future<void> _fetchProbabilistic() async {
    if (!mounted) return;
    try {
      final raw = await _backendService.getProbabilistic(widget.stock.ticker);
      if (raw != null && mounted) {
        setState(() => _probabilisticData = ProbabilisticData.fromJson(raw));
        ref.read(usageAnalyticsProvider)?.logFeatureUsed(UsageFeature.probabilistic);
      }
    } catch (_) {
      // Non-fatal — card simply stays hidden
    }
  }

  // Returns (binanceInterval, fetchLimit, displayBars) for crypto timeframes.
  // fetchLimit = displayBars + _kWarmupBars so indicators have enough history.
  ({String interval, int display}) _cryptoCandleParams() {
    switch (_timeframe) {
      case '1m':  return (interval: '1m',  display: 120);
      case '5m':  return (interval: '5m',  display: 288);
      case '15m': return (interval: '15m', display: 192);
      case '30m': return (interval: '30m', display: 96);
      case '1h':  return (interval: '1h',  display: 168);
      case '2h':  return (interval: '2h',  display: 168);
      case '4h':  return (interval: '4h',  display: 180);
      case '12h': return (interval: '12h', display: 60);
      // Date-range views: use daily/weekly candles with a sensible bar count
      case '1D':  return (interval: '15m', display: 96);   // 24h at 15m = 96 bars (denser)
      case '1W':  return (interval: '4h',  display: 42);   // 7d of 4h
      case '4W':  return (interval: '4h',  display: 168);  // 28d of 4h
      case '1M':  return (interval: '1d',  display: 30);
      case '3M':  return (interval: '1d',  display: 90);
      case '6M':  return (interval: '1d',  display: 180);
      case '1Y':  return (interval: '1d',  display: 365);
      case '5Y':  return (interval: '1w',  display: 260);
      default:    return (interval: '1d',  display: 365);
    }
  }

  // ── Indicator computation ─────────────────────────────────────────────────
  /// Recompute RSI + MACD from [all] candles (warmup + display) and cache
  /// only the display-aligned slice.  Call this whenever _candles changes.
  void _computeIndicators(List<Candle> all, List<Candle> display) {
    if (all.isEmpty) {
      _allCandles = [];
      _candles    = display;
      _rsiValues  = [];
      _macdData   = {};
      return;
    }
    final fullRsi  = TechnicalAnalysisService.calculateRSIHistory(all);
    final fullMacd = TechnicalAnalysisService.calculateMACDHistory(all);

    // Slice to the last display.length values so indexes align 1-to-1.
    final trim = all.length - display.length;
    _allCandles = all;
    _candles    = display;
    _rsiValues  = trim > 0 ? fullRsi.sublist(trim)  : fullRsi;
    final macdLine = fullMacd['macd']      ?? [];
    final sigLine  = fullMacd['signal']    ?? [];
    final hist     = fullMacd['histogram'] ?? [];
    _macdData = {
      'macd':      trim > 0 && macdLine.length > trim ? macdLine.sublist(trim)  : macdLine,
      'signal':    trim > 0 && sigLine.length  > trim ? sigLine.sublist(trim)   : sigLine,
      'histogram': trim > 0 && hist.length     > trim ? hist.sublist(trim)      : hist,
    };
  }

  void _subscribeToCandles() {
    _candleSubscription?.cancel();
    final p = _cryptoCandleParams();
    final fetchLimit = p.display + _kWarmupBars;
    _candleSubscription = _candleService
        .streamCandles(
          widget.stock.ticker,
          interval: p.interval,
          limit: fetchLimit,
        )
        .listen(
      (candles) {
        if (mounted) {
          // Slice: show only the last display bars in chart; run indicators
          // on the full warmup+display set so RSI/MACD values are valid.
          final display = candles.length > p.display
              ? candles.sublist(candles.length - p.display)
              : candles;
          _computeIndicators(candles, display);
          setState(() {
            _hasError = false;
            _errorMessage = null;
          });
          _chartController.setCandles(_candles);
        }
      },
      onError: (_) {
        if (mounted) setState(() { _hasError = true; _errorMessage = 'Failed to load chart data.'; });
      },
    );
  }

  void _subscribeToQuotes() {
    _quoteSubscription?.cancel();
    _quoteSubscription = _quoteService.streamQuotes({widget.stock.ticker}).listen(
      (quotes) {
        if (mounted) setState(() => _liveQuote = quotes[widget.stock.ticker]);
      },
      onError: (e) => debugPrint('Quote stream error: $e'),
    );
  }

  // Returns (interval, displayBars, yfRange).
  // displayBars is what the chart should show; we fetch displayBars + _kWarmupBars
  // so indicators always have enough history to produce valid output.
  ({String interval, int display, String yfRange}) _stockCandleParams() {
    switch (_timeframe) {
      case '1m':  return (interval: '1m',  display: 120, yfRange: '1d');
      case '5m':  return (interval: '5m',  display: 288, yfRange: '1d');
      case '15m': return (interval: '15m', display: 192, yfRange: '2d');
      case '30m': return (interval: '30m', display: 96,  yfRange: '2d');
      case '1h':  return (interval: '1h',  display: 168, yfRange: '7d');
      case '2h':  return (interval: '2h',  display: 168, yfRange: '14d');
      case '4h':  return (interval: '4h',  display: 180, yfRange: '30d');
      case '12h': return (interval: '12h', display: 180, yfRange: '90d');
      // Short daily views: must fetch enough for MACD(26,9) = 34 bars minimum
      case '1W':  return (interval: '1d',  display: 7,   yfRange: '3mo');
      case '4W':  return (interval: '1d',  display: 28,  yfRange: '3mo');
      case '1M':  return (interval: '1d',  display: 30,  yfRange: '3mo');
      case '3M':  return (interval: '1d',  display: 90,  yfRange: '6mo');
      case '6M':  return (interval: '1d',  display: 180, yfRange: '1y');
      case '1Y':  return (interval: '1wk', display: 52,  yfRange: '2y');
      case '5Y':  return (interval: '1wk', display: 260, yfRange: '5y');
      default:    return (interval: '1d',  display: 365, yfRange: '1y');
    }
  }

  Future<void> _fetchStockCandles() async {
    setState(() { _isLoading = true; _hasError = false; _candles = []; _rsiValues = []; _macdData = {}; });

    final p = _stockCandleParams();
    final fetchLimit = p.display + _kWarmupBars; // extra bars for indicator warmup

    if (kDebugMode) {
      debugPrint('[AssetChart] ${widget.stock.ticker} tf=${_timeframe} '
          'interval=${p.interval} display=${p.display} fetch=$fetchLimit');
    }

    List<Candle> all = [];
    final raw = await _backendService.getCandles(
        widget.stock.ticker, interval: p.interval, limit: fetchLimit);
    if (raw.isNotEmpty) all = raw.map((r) => Candle.fromMap(r)).toList();

    if (all.isEmpty) {
      final yf = YahooFinanceCandleService();
      all = await yf.fetchCandles(widget.stock.ticker,
          interval: p.interval, range: p.yfRange);
    }

    if (kDebugMode) {
      debugPrint('[AssetChart] ${widget.stock.ticker} fetched=${all.length} '
          'candles (warmup+display). display slice=${p.display}');
    }

    if (!mounted) return;

    if (all.isEmpty) {
      setState(() {
        _candles = [];
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'No chart data for ${widget.stock.ticker}';
      });
      return;
    }

    // Slice: show only the last display bars in the chart; compute indicators
    // on the full (warmup+display) set so RSI/MACD have valid values.
    final display = all.length > p.display ? all.sublist(all.length - p.display) : all;
    _computeIndicators(all, display);

    setState(() {
      _isLoading = false;
      _hasError = false;
    });
    _chartController.setCandles(_candles);
  }

  void _onTimeframeChanged(String tf) {
    setState(() => _timeframe = tf);
    if (isCryptoSymbol(widget.stock.ticker)) {
      _subscribeToCandles();
    } else {
      _fetchStockCandles();
    }
    // Re-run signal analysis for the new interval so AI commentary matches
    // the resolution the user is now viewing.
    _fetchSignalAnalysis();
  }

  Future<void> _toggleWatchlist() async {
    final service = ref.read(watchlistServiceProvider);
    try {
      final nowInList = await service.toggleWatchlist(widget.stock.ticker);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(nowInList
              ? '${widget.stock.ticker} added to watchlist'
              : '${widget.stock.ticker} removed from watchlist'),
          duration: const Duration(seconds: 1),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not update watchlist'),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 2),
        ));
      }
    }
  }

  /// Detects RSI and MACD crossover events and returns a deduplicated list of
  /// [SignalMarker]s for the chart painter.  A minimum 5-candle cooldown prevents
  /// clustering when multiple signals fire close together.
  List<SignalMarker> _computeSignalMarkers(
    List<double?> rsiValues,
    List<double?> macdLine,
    List<double?> signalLine,
  ) {
    if (_candles.isEmpty) return const [];
    final markers = <SignalMarker>[];
    int lastBuyIdx  = -99;
    int lastSellIdx = -99;
    const cooldown  = 5;

    for (int i = 1; i < _candles.length; i++) {
      final rsiPrev = i - 1 < rsiValues.length ? rsiValues[i - 1] : null;
      final rsiCurr = i     < rsiValues.length ? rsiValues[i]     : null;
      final macdPrev   = i - 1 < macdLine.length   ? macdLine[i - 1]   : null;
      final macdCurr   = i     < macdLine.length    ? macdLine[i]       : null;
      final sigPrev    = i - 1 < signalLine.length  ? signalLine[i - 1] : null;
      final sigCurr    = i     < signalLine.length  ? signalLine[i]     : null;

      // ── Buy triggers ──────────────────────────────────────────────
      // RSI cross up through 30 (oversold recovery)
      final rsiOversoldCross = rsiPrev != null && rsiCurr != null &&
          rsiPrev < 30 && rsiCurr >= 30;
      // MACD bullish cross
      final macdBullCross = macdPrev != null && macdCurr != null &&
          sigPrev != null && sigCurr != null &&
          macdPrev < sigPrev && macdCurr >= sigCurr;

      if ((rsiOversoldCross || macdBullCross) && i - lastBuyIdx >= cooldown) {
        final strength = rsiOversoldCross && macdBullCross ? 1.0 : 0.65;
        markers.add(SignalMarker(candleIndex: i, isBuy: true, strength: strength));
        lastBuyIdx = i;
      }

      // ── Sell triggers ─────────────────────────────────────────────
      // RSI cross down through 70 (overbought reversal)
      final rsiOverboughtCross = rsiPrev != null && rsiCurr != null &&
          rsiPrev > 70 && rsiCurr <= 70;
      // MACD bearish cross
      final macdBearCross = macdPrev != null && macdCurr != null &&
          sigPrev != null && sigCurr != null &&
          macdPrev > sigPrev && macdCurr <= sigCurr;

      if ((rsiOverboughtCross || macdBearCross) && i - lastSellIdx >= cooldown) {
        final strength = rsiOverboughtCross && macdBearCross ? 1.0 : 0.65;
        markers.add(SignalMarker(candleIndex: i, isBuy: false, strength: strength));
        lastSellIdx = i;
      }
    }
    return markers;
  }

  OverlayData _buildOverlays({
    List<double?> rsiValues = const [],
    List<double?> macdLine  = const [],
    List<double?> signalLine = const [],
  }) {
    if (_candles.isEmpty) return const OverlayData();

    final maLines = <MALine>[];
    if (_maType == MAType.sma || _maType == MAType.both) {
      maLines.add(MALine(values: TechnicalAnalysisService.calculateSMA(_candles, 20), color: const Color(0xFFFFEB3B), label: 'SMA20'));
      maLines.add(MALine(values: TechnicalAnalysisService.calculateSMA(_candles, 50), color: const Color(0xFFFF9800), label: 'SMA50'));
      maLines.add(MALine(values: TechnicalAnalysisService.calculateSMA(_candles, 200), color: const Color(0xFFE91E63), label: 'SMA200'));
    }
    if (_maType == MAType.ema || _maType == MAType.both) {
      maLines.add(MALine(values: TechnicalAnalysisService.calculateEMA(_candles, 12), color: const Color(0xFF00BCD4), label: 'EMA12'));
      maLines.add(MALine(values: TechnicalAnalysisService.calculateEMA(_candles, 26), color: const Color(0xFF9C27B0), label: 'EMA26'));
      maLines.add(MALine(values: TechnicalAnalysisService.calculateEMA(_candles, 50), color: const Color(0xFF4CAF50), label: 'EMA50'));
    }

    BollingerData? bollinger;
    if (_showBollingerBands) {
      final bb = TechnicalAnalysisService.calculateBollingerBands(_candles, period: 20, stdDev: 2.0);
      bollinger = BollingerData(upper: bb['upper']!, lower: bb['lower']!, middle: bb['middle']!);
    }

    final srLines = <SRLine>[];
    if (_srType == SRType.simple) {
      final support = TechnicalAnalysisService.calculateSupport(_candles);
      final resistance = TechnicalAnalysisService.calculateResistance(_candles);
      srLines.add(SRLine(price: support, color: Colors.green, label: 'Support'));
      srLines.add(SRLine(price: resistance, color: Colors.red, label: 'Resist'));
    } else if (_srType == SRType.pivot) {
      final pivots = TechnicalAnalysisService.calculatePivotPoints(_candles);
      pivots.forEach((k, v) => srLines.add(SRLine(price: v, color: Colors.orange, label: k)));
    } else if (_srType == SRType.fibonacci) {
      final fibs = TechnicalAnalysisService.calculateFibonacci(_candles);
      fibs.forEach((k, v) => srLines.add(SRLine(price: v, color: Colors.purple, label: k)));
    }

    final vwapLine = _showVWAP
        ? TechnicalAnalysisService.calculateVWAP(_candles)
        : null;

    final currentPriceLine = _liveQuote?.price ?? widget.stock.price;

    // ── AI trade-plan levels from RiskAgent ──────────────────────────────────
    final tradeLevels = <TradeLevel>[];
    final pred = _signalAnalysis?.prediction;
    if (pred != null) {
      // Stop loss — always shown, full opacity
      tradeLevels.add(TradeLevel(
        price: pred.stopLossSuggestion,
        color: const Color(0xFFFF4D6A),
        label: 'SL',
        alpha: 1.0,
      ));
      // Base target — primary AI projection
      tradeLevels.add(TradeLevel(
        price: pred.priceTargetBase,
        color: const Color(0xFF12A28C),
        label: 'Target',
        alpha: 1.0,
      ));
      // Bull / Bear cases — dimmed so they don't dominate
      if (pred.priceTargetHigh != pred.priceTargetBase) {
        tradeLevels.add(TradeLevel(
          price: pred.priceTargetHigh,
          color: const Color(0xFF00C896),
          label: 'Bull',
          alpha: 0.55,
        ));
      }
      if (pred.priceTargetLow != pred.priceTargetBase) {
        tradeLevels.add(TradeLevel(
          price: pred.priceTargetLow,
          color: const Color(0xFFFFB300),
          label: 'Bear',
          alpha: 0.55,
        ));
      }
    }

    return OverlayData(
      maLines: maLines,
      bollinger: bollinger,
      srLines: srLines,
      patterns: _signalAnalysis?.patterns,
      vwapLine: vwapLine,
      currentPriceLine: currentPriceLine,
      signalMarkers: _computeSignalMarkers(rsiValues, macdLine, signalLine),
      tradeLevels: tradeLevels,
    );
  }

  void _showChartPatternSheet(dynamic pat) {
    final type = pat.type as String;
    final signal = pat.signal as String;
    final signalColor = signal == 'BULLISH'
        ? const Color(0xFF12A28C)
        : signal == 'BEARISH' ? Colors.redAccent : Colors.white54;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111925),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(pat.displayName as String,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: signalColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: signalColor.withValues(alpha: 0.4)),
                ),
                child: Text(signal, style: TextStyle(color: signalColor, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 6),
            Text('${((pat.confidence as double) * 100).toStringAsFixed(0)}% confidence',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 14),
            Text(_patternEducationText(type),
                style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.55)),
          ],
        ),
      ),
    );
  }

  static String _patternEducationText(String type) {
    const map = <String, String>{
      'DOUBLE_TOP': 'Two peaks at roughly the same price — sellers rejected the same level twice. Usually signals a bearish reversal.',
      'DOUBLE_BOTTOM': 'Two troughs at roughly the same price — buyers defended the same level twice. Usually signals a bullish reversal.',
      'HEAD_SHOULDERS': 'Three peaks where the middle is the highest. Classic bearish reversal. Break below the neckline is the signal.',
      'INV_HEAD_SHOULDERS': 'Three troughs where the middle is lowest. Classic bullish reversal. Break above the neckline confirms.',
      'BULL_FLAG': 'Strong upward move (pole) followed by tight consolidation. Breakout above the flag top with volume surge is the entry signal.',
      'BEAR_FLAG': 'Sharp downward move followed by brief consolidation. Breakdown below flag low confirms continuation.',
      'DOJI': 'Open and close are almost the same price — neither buyers nor sellers won. Signals indecision.',
      'HAMMER': 'A small body at the top with a long lower shadow. Potential bullish reversal when found at the bottom of downtrends.',
      'BULLISH_ENGULFING': 'A bearish candle followed by a larger bullish candle. Buyers overwhelmed sellers.',
      'BEARISH_ENGULFING': 'A bullish candle followed by a larger bearish candle. Sellers took complete control.',
      'MORNING_STAR': 'Three-candle bullish reversal at the bottom of a downtrend.',
      'EVENING_STAR': 'Three-candle bearish reversal at the top of an uptrend.',
    };
    return map[type] ?? 'Pattern detected based on price action analysis.';
  }

  void _showIndicatorSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111925),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            AdvancedIndicatorSettings(
              movingAverageType: _maType,
              showBollingerBands: _showBollingerBands,
              supportResistanceType: _srType,
              subChartType: _subChartType,
              onMATypeChanged: (v) { setState(() => _maType = v); Navigator.pop(ctx); },
              onBollingerBandsChanged: (v) { setState(() => _showBollingerBands = v); },
              onSRTypeChanged: (v) { setState(() => _srType = v); Navigator.pop(ctx); },
              onSubChartChanged: (v) {
                setState(() {
                  _subChartType = v;
                  _showRSI = v == SubChartType.rsi;
                  _showMACD = v == SubChartType.macd;
                });
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(child: TextButton.icon(
                  icon: const Icon(Icons.help_outline, size: 18),
                  label: const Text('Moving Averages'),
                  onPressed: () { Navigator.pop(ctx); EducationalBottomSheet.show(context, EducationalContent.movingAverages); },
                )),
                Expanded(child: TextButton.icon(
                  icon: const Icon(Icons.help_outline, size: 18),
                  label: const Text('Support/Resistance'),
                  onPressed: () { Navigator.pop(ctx); EducationalBottomSheet.show(context, EducationalContent.supportResistance); },
                )),
              ]),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showAddToPortfolioSheet() {
    final service = ref.read(portfolioServiceProvider);
    if (service == null) return;
    final sharesCtrl = TextEditingController();
    final costCtrl = TextEditingController(
        text: widget.stock.price > 0 ? widget.stock.price.toStringAsFixed(2) : '');
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111925),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add ${widget.stock.ticker} to Portfolio',
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              TextField(
                controller: sharesCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Number of Shares', labelStyle: TextStyle(color: Colors.white54),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF12A28C))),
                  filled: true, fillColor: Color(0x08FFFFFF),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: costCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Avg Cost Per Share (\$)', labelStyle: TextStyle(color: Colors.white54),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF12A28C))),
                  filled: true, fillColor: Color(0x08FFFFFF),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: const Color(0xFF12A28C),
                  ),
                  onPressed: saving ? null : () async {
                    final shares = double.tryParse(sharesCtrl.text.trim());
                    final cost = double.tryParse(costCtrl.text.trim());
                    if (shares == null || shares <= 0 || cost == null || cost <= 0) return;
                    setSheet(() => saving = true);
                    await service.upsert(Holding(
                      symbol: widget.stock.ticker, name: widget.stock.name,
                      shares: shares, avgCost: cost, addedAt: DateTime.now(),
                    ));
                    if (mounted) setState(() => _inPortfolio = true);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: saving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Add to Portfolio', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPaperTradeSheet({bool startAsBuy = true}) {
    final service = ref.read(paperTradingServiceProvider);
    if (service == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in to use paper trading')));
      return;
    }

    final currentPrice = _liveQuote?.price ?? widget.stock.price;
    bool isBuy = startAsBuy;
    bool byDollars = true;
    final inputCtrl = TextEditingController();
    bool saving = false;
    String? error;

    double parsedShares(String text) {
      final v = double.tryParse(text.trim()) ?? 0;
      if (byDollars) return currentPrice > 0 ? v / currentPrice : 0;
      return v;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D1520),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void setInput(String v) { inputCtrl.text = v; setSheet(() => error = null); }

          return FutureBuilder<List<dynamic>>(
            future: Future.wait([
              service.streamAccount().first,
              service.getHolding(widget.stock.ticker),
            ]),
            builder: (ctx, snap) {
              final account = snap.data?[0] as PaperAccount?;
              final holding = snap.data?[1] as PaperHolding?;

              final rawVal = double.tryParse(inputCtrl.text.trim()) ?? 0;
              final sharesEntered = byDollars ? (currentPrice > 0 ? rawVal / currentPrice : 0) : rawVal;
              final dollarValue = byDollars ? rawVal : rawVal * currentPrice;

              double? grossPnl, taxEst, afterTaxEst;
              if (!isBuy && holding != null && sharesEntered > 0) {
                grossPnl = (currentPrice - holding.avgCost) * sharesEntered;
                taxEst = grossPnl > 0 ? grossPnl * holding.taxRate : 0;
                afterTaxEst = grossPnl - taxEst;
              }

              final accent = isBuy ? const Color(0xFF12A28C) : Colors.redAccent;

              return Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 36, height: 4,
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 16),
                    Row(children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(widget.stock.ticker,
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                        Row(children: [
                          Text('\$${currentPrice.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 6),
                          const Icon(Icons.circle, size: 7, color: Colors.greenAccent),
                          const SizedBox(width: 3),
                          const Text('LIVE', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.w700)),
                        ]),
                      ]),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(8)),
                        child: const Text('PAPER', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                    ]),
                    if (account == null) ...[
                      const SizedBox(height: 24),
                      const Text('Activate Paper Trading first.\nGo to Portfolio → Paper Trading tab.',
                          style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5)),
                    ] else ...[
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(children: [
                          _TradeTab('BUY', isBuy, const Color(0xFF12A28C), () =>
                              setSheet(() { isBuy = true; error = null; inputCtrl.clear(); })),
                          _TradeTab('SELL', !isBuy, Colors.redAccent, () =>
                              setSheet(() { isBuy = false; error = null; inputCtrl.clear(); })),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      if (isBuy)
                        _ContextBar(
                          label: 'Cash available',
                          value: '\$${account.cashBalance.toStringAsFixed(2)}',
                          sub: 'Max ${(account.cashBalance / currentPrice).toStringAsFixed(4)} shares',
                        )
                      else if (holding != null)
                        _ContextBar(
                          label: 'Your position',
                          value: '${holding.shares.toStringAsFixed(4)} shares',
                          sub: 'Avg \$${holding.avgCost.toStringAsFixed(2)} · ${holding.holdingDays ?? 0}d held',
                        )
                      else
                        const _ContextBar(label: 'Position', value: 'None', sub: 'You have no shares to sell'),
                      const SizedBox(height: 14),
                      Row(children: [
                        _ModeChip('By \$', byDollars, () => setSheet(() { byDollars = true; inputCtrl.clear(); error = null; })),
                        const SizedBox(width: 8),
                        _ModeChip('By Shares', !byDollars, () => setSheet(() { byDollars = false; inputCtrl.clear(); error = null; })),
                        const Spacer(),
                        if (!byDollars && rawVal > 0)
                          Text('≈ \$${dollarValue.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        if (byDollars && rawVal > 0)
                          Text('≈ ${sharesEntered.toStringAsFixed(4)} shares',
                              style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      ]),
                      const SizedBox(height: 8),
                      TextField(
                        controller: inputCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
                        autofocus: true,
                        onChanged: (_) => setSheet(() => error = null),
                        decoration: InputDecoration(
                          prefixText: byDollars ? '\$ ' : '',
                          prefixStyle: const TextStyle(color: Colors.white54, fontSize: 20),
                          suffixText: byDollars ? '' : ' shares',
                          suffixStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                          hintText: byDollars ? '0.00' : '0.0000',
                          hintStyle: const TextStyle(color: Colors.white24, fontSize: 20),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: accent.withValues(alpha: 0.3))),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: accent, width: 2)),
                          filled: true, fillColor: Colors.white.withValues(alpha: 0.05),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (isBuy)
                        Row(children: [
                          for (final amt in [100, 500, 1000, 5000]) ...[
                            _QuickBtn('\$$amt', () => setInput(byDollars ? '$amt' : (amt / currentPrice).toStringAsFixed(4))),
                            const SizedBox(width: 6),
                          ],
                          _QuickBtn('Max', () {
                            final max = account.cashBalance;
                            setInput(byDollars ? max.toStringAsFixed(2) : (max / currentPrice).toStringAsFixed(4));
                          }),
                        ])
                      else if (holding != null)
                        Row(children: [
                          for (final pct in [25, 50, 75]) ...[
                            _QuickBtn('$pct%', () {
                              final s = holding.shares * pct / 100;
                              setInput(byDollars ? (s * currentPrice).toStringAsFixed(2) : s.toStringAsFixed(4));
                            }),
                            const SizedBox(width: 6),
                          ],
                          _QuickBtn('All', () => setInput(byDollars
                              ? (holding.shares * currentPrice).toStringAsFixed(2)
                              : holding.shares.toStringAsFixed(4))),
                        ]),
                      if (!isBuy && sharesEntered > 0 && holding != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(children: [
                            Row(children: [
                              const Icon(Icons.receipt_long, size: 13, color: Colors.white38),
                              const SizedBox(width: 5),
                              Text(
                                '${holding.isShortTerm ? 'Short' : 'Long'}-term gains · ${(holding.taxRate * 100).toStringAsFixed(0)}% tax',
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                            ]),
                            const SizedBox(height: 8),
                            _SheetTaxRow('Gross P&L',
                                '${(grossPnl ?? 0) >= 0 ? '+' : ''}\$${(grossPnl ?? 0).toStringAsFixed(2)}',
                                (grossPnl ?? 0) >= 0 ? const Color(0xFF12A28C) : Colors.redAccent),
                            const SizedBox(height: 4),
                            _SheetTaxRow('Tax', '-\$${(taxEst ?? 0).toStringAsFixed(2)}', Colors.orange),
                            const Divider(height: 10, color: Colors.white12),
                            _SheetTaxRow('After-Tax',
                                '${(afterTaxEst ?? 0) >= 0 ? '+' : ''}\$${(afterTaxEst ?? 0).toStringAsFixed(2)}',
                                (afterTaxEst ?? 0) >= 0 ? const Color(0xFF12A28C) : Colors.redAccent,
                                bold: true),
                          ]),
                        ),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: 8),
                        Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: accent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          onPressed: saving ? null : () async {
                            final shares = parsedShares(inputCtrl.text);
                            if (shares <= 0) {
                              setSheet(() => error = 'Enter an amount to ${isBuy ? 'buy' : 'sell'}');
                              return;
                            }
                            setSheet(() { saving = true; error = null; });
                            final svc = ref.read(paperTradingServiceProvider)!;
                            final err = isBuy
                                ? await svc.buy(widget.stock.ticker, widget.stock.name, shares, currentPrice)
                                : await svc.sell(widget.stock.ticker, widget.stock.name, shares, currentPrice);
                            if (err != null) {
                              setSheet(() { saving = false; error = err; });
                            } else {
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(isBuy
                                      ? 'Bought ${shares.toStringAsFixed(4)} ${widget.stock.ticker} for \$${dollarValue.toStringAsFixed(2)}'
                                      : 'Sold ${shares.toStringAsFixed(4)} ${widget.stock.ticker}'),
                                  backgroundColor: accent,
                                ));
                              }
                            }
                          },
                          child: saving
                              ? const SizedBox(height: 22, width: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(
                                  isBuy ? 'Buy ${widget.stock.ticker}' : 'Sell ${widget.stock.ticker}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _getChartCoachingTip() {
    switch (_chartType) {
      case ChartType.candlestick:
        return 'Candlestick charts show the battle between buyers and sellers. Green candles = buyers won, red = sellers won.';
      case ChartType.line:
        return 'Line charts connect closing prices to show the clean trend without noise. Great for seeing the big picture.';
      case ChartType.area:
        return 'Area charts emphasize trend direction visually. The filled area helps you quickly identify bull vs bear markets.';
      default:
        return 'Bar charts show OHLC data like candlesticks but without filled bodies.';
    }
  }

  @override
  void dispose() {
    _technicalScrollController.dispose();
    _tabController.dispose();
    _candleSubscription?.cancel();
    _quoteSubscription?.cancel();
    _priceStreamSub?.cancel();
    _stockQuoteTimer?.cancel();
    _candleService.dispose();
    _quoteService.dispose();
    _chartController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ── Phase 8: Analyst Graph methods ────────────────────────────────────────

  Future<void> _runDeepAnalysis() async {
    if (_analystLoading) return;
    setState(() {
      _analystLoading = true;
      _analystError = null;
      _analystResult = null;
    });

    final query = AnalystGraphService.defaultQueryFor(
        widget.stock.ticker, 'technical');
    final userId = ref.read(userIdProvider);
    final result = await _analystService.analyze(
      message: query,
      userId: userId,
    );

    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _analystLoading = false;
        _analystError = result.error;
      });
    } else {
      setState(() {
        _analystLoading = false;
        _analystResult = result;
      });
    }
  }

  Future<void> _toggleAudio(String relativeUrl) async {
    final url = _analystService.resolveAudioUrl(relativeUrl);
    if (_audioPlaying) {
      await _audioPlayer.pause();
      if (mounted) setState(() => _audioPlaying = false);
    } else {
      await _audioPlayer.play(UrlSource(url));
      if (mounted) setState(() => _audioPlaying = true);
      _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _audioPlaying = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    AsyncValue<EnhancedAIAnalysis>? analysisAsync;
    if (_analysisRequested) {
      analysisAsync = ref.watch(aiAnalysisProvider(widget.stock.ticker));
    }

    final currentUser = ref.watch(currentUserProvider);
    final isGuest = currentUser == null || currentUser.isAnonymous;

    // Live watchlist state — streams from Firestore for guests it's always false.
    final isWatchlisted = ref.watch(isInWatchlistProvider(widget.stock.ticker)).valueOrNull ?? false;

    final displayPrice = _liveQuote?.price ?? widget.stock.price;
    final displayChange = _liveQuote?.changePercent ?? widget.stock.changePercent;
    // Use cached indicator values (computed in _computeIndicators, not here).
    // This avoids expensive O(N) recomputation on every frame.
    final rsiValues = _rsiValues;
    final macdData  = _macdData;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.stock.ticker),
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(_inPortfolio ? Icons.pie_chart : Icons.pie_chart_outline,
                color: _inPortfolio ? colorScheme.primary : Colors.white70),
            onPressed: _showAddToPortfolioSheet,
            tooltip: _inPortfolio ? 'In portfolio — tap to edit' : 'Add to portfolio',
          ),
          IconButton(
            icon: Icon(isWatchlisted ? Icons.bookmark : Icons.bookmark_border,
                color: isWatchlisted ? colorScheme.primary : Colors.white70),
            onPressed: _toggleWatchlist,
            tooltip: isWatchlisted ? 'Remove from watchlist' : 'Add to watchlist',
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0D131A),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
          ),
          child: Row(children: [
            Expanded(child: ElevatedButton(
              onPressed: () => _showPaperTradeSheet(startAsBuy: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF12A28C),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('BUY', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                Text('\$${(_liveQuote?.price ?? widget.stock.price).toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ]),
            )),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              onPressed: () => _showPaperTradeSheet(startAsBuy: false),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('SELL', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                Text('\$${(_liveQuote?.price ?? widget.stock.price).toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ]),
            )),
          ]),
        ),
      ),
      body: Column(
        children: [
          // ── Decision Strip (pinned — always visible) ─────────────────────
          _DecisionStrip(
            price: displayPrice,
            changePercent: displayChange,
            signalAnalysis: _signalAnalysis,
            signalLoading: _signalLoading,
          ),

          // ── Data latency badge (stocks only) ─────────────────────────────
          if (!widget.stock.isCrypto)
            Container(
              color: const Color(0xFF0D131A),
              padding: const EdgeInsets.only(left: 16, bottom: 6),
              child: const Row(children: [
                Icon(Icons.access_time, size: 10, color: Color(0xFF8A95A3)),
                SizedBox(width: 3),
                Text('Market data ~15 min delayed',
                    style: TextStyle(color: Color(0xFF8A95A3), fontSize: 9.5)),
              ]),
            ),

          // ── Tab bar ───────────────────────────────────────────────────────
          Container(
            color: const Color(0xFF0D131A),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: const Color(0xFF12A28C),
              unselectedLabelColor: const Color(0xFF8A95A3),
              labelStyle: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w500),
              indicatorColor: const Color(0xFF12A28C),
              indicatorWeight: 2,
              dividerColor: Colors.white10,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Technical'),
                Tab(text: 'Fundamental'),
                Tab(text: 'Flow'),
                Tab(text: 'Macro'),
                Tab(text: 'Analyst'),   // Phase 8 — DeepSeek-R1 deep analysis
              ],
            ),
          ),

          // ── Tab content ───────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildOverviewTab(isGuest, theme, colorScheme, analysisAsync),
                _buildTechnicalTab(isGuest, rsiValues, macdData),
                _buildFundamentalTab(isGuest, theme, colorScheme, analysisAsync),
                _buildFlowTab(),
                _buildMacroTab(isGuest),
                _buildAnalystTab(isGuest),  // Phase 8
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB BUILDERS
  // ═══════════════════════════════════════════════════════════════════════════

  // ── Tab 0: Overview ─────────────────────────────────────────────────────
  // Scenario cards, price targets, coaching nudge, correlation sentiment.
  Widget _buildOverviewTab(
    bool isGuest,
    ThemeData theme,
    ColorScheme colorScheme,
    AsyncValue<EnhancedAIAnalysis>? analysisAsync,
  ) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 12)),

        // Price range bar (open/high/low/close).
        // Always rendered — PriceHeroWidget shows "—" placeholders while
        // _marketRange is loading, so the card never disappears mid-session.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: PriceHeroWidget(
              stock: widget.stock,
              liveQuote: _liveQuote,
              marketRange: _marketRange,
            ),
          ),
        ),

        // Signal score bar (compact)
        SliverToBoxAdapter(
          child: GuestGate(
            feature: 'AI signal analysis',
            message: 'Create a free account to unlock AI-powered signal analysis, '
                'Bull/Base/Bear scenarios, price targets, and coaching nudges.',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _SignalBadge(
                signalAnalysis: _signalAnalysis,
                isLoading: _signalLoading,
                onRefresh: _fetchSignalAnalysis,
              ),
            ),
          ),
        ),

        // Scenario Card (Bull / Base / Bear)
        if (!isGuest && _signalAnalysis?.scenarios != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _ScenarioCard(scenarios: _signalAnalysis!.scenarios!),
            ),
          ),

        // Price prediction targets
        if (!isGuest && _signalAnalysis?.prediction != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _PredictionCard(prediction: _signalAnalysis!.prediction!),
            ),
          ),

        // Coaching nudge
        if (!isGuest &&
            _signalAnalysis?.coachingNudge != null &&
            _signalAnalysis!.coachingNudge!.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: CoachingNudgeCard(
                nudge: _signalAnalysis!.coachingNudge!,
                onLearnMore: _signalAnalysis?.coachingLessonId != null
                    ? () {
                        final lesson = LessonRegistry.byId(
                            _signalAnalysis!.coachingLessonId!);
                        if (lesson != null && context.mounted) {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => GuidedLessonScreen(lesson: lesson),
                            fullscreenDialog: true,
                          ));
                        }
                      }
                    : null,
              ),
            ),
          ),

        // Correlation / news sentiment
        if (!isGuest && _signalAnalysis?.correlation != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _CorrelationCard(correlation: _signalAnalysis!.correlation!),
            ),
          ),

        // Probabilistic Engine card (Phase 4 / gated Phase 8)
        if (!isGuest && _probabilisticData != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: SubscriptionGate(
                feature: 'Probabilistic Engine',
                description:
                    'Monte Carlo price fan, Value-at-Risk, and Bayesian price targets.',
                child: ProbabilisticCard(data: _probabilisticData!),
              ), // SubscriptionGate
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _EducationalDisclaimer(),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  // ── Tab 1: Technical ────────────────────────────────────────────────────
  // Chart, timeframe, type, indicators, pattern card, technical highlights.
  Widget _buildTechnicalTab(
    bool isGuest,
    List<double?> rsiValues,
    Map<String, List<double?>> macdData,
  ) {
    return CustomScrollView(
      controller: _technicalScrollController,
      physics: _chartInteracting
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(),
      slivers: [
        // Chart toolbar row (timeframe + type + gear icon)
        SliverToBoxAdapter(
          child: Container(
            color: const Color(0xFF0D1117),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(children: [
              Expanded(
                child: TimeframeSelector(
                  selectedTimeframe: _timeframe,
                  onChanged: _onTimeframeChanged,
                  isCrypto: isCryptoSymbol(widget.stock.ticker),
                ),
              ),
              const SizedBox(width: 8),
              ChartToolbar(
                chartType: _chartType,
                onChartTypeChanged: (t) {
                  setState(() {
                    _chartType = t;
                    _chartController.setChartType(t);
                  });
                },
                onSettingsTap: _showIndicatorSettings,
                onZoomReset: () => _chartController.resetZoom(),
                showVWAP: _showVWAP,
                onVwapToggle: () => setState(() => _showVWAP = !_showVWAP),
                onDeepAiTap: isGuest
                    ? null
                    : () async {
                        final result = await showCrewAnalysisSheet(
                          context,
                          symbol: widget.stock.ticker,
                          userLevel: 'intermediate',
                        );
                        if (result != null && mounted) _fetchSignalAnalysis();
                      },
              ),
            ]),
          ),
        ),

        // Main chart
        SliverToBoxAdapter(
          child: Container(
            color: const Color(0xFF0D1117),
            child: _hasError
                ? _buildErrorChart()
                : (_isLoading || _candles.isEmpty)
                    ? _buildLoadingChart()
                    : MarketChart(
                        key: ValueKey('${widget.stock.ticker}_$_timeframe'),
                        controller: _chartController,
                        overlays: _buildOverlays(
                          rsiValues:   rsiValues,
                          macdLine:    macdData['macd']   ?? const [],
                          signalLine:  macdData['signal'] ?? const [],
                        ),
                        height: _chartHeight,
                        onPatternTap: _showChartPatternSheet,
                        rsiValues: rsiValues,
                        macdLine: macdData['macd'] ?? [],
                        signalLine: macdData['signal'] ?? [],
                        histogram: macdData['histogram'] ?? [],
                        showRSI: _showRSI,
                        showMACD: _showMACD,
                        onInteractionChanged: (active) =>
                            setState(() => _chartInteracting = active),
                      ),
          ),
        ),

        // Indicator toggles
        if (_candles.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              color: const Color(0xFF0D1117),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                _IndicatorToggle(
                    label: 'RSI',
                    active: _showRSI,
                    color: const Color(0xFF4CAF50),
                    onTap: () => setState(() => _showRSI = !_showRSI)),
                const SizedBox(width: 8),
                _IndicatorToggle(
                    label: 'MACD',
                    active: _showMACD,
                    color: const Color(0xFFFFEB3B),
                    onTap: () => setState(() => _showMACD = !_showMACD)),
                const SizedBox(width: 8),
                _IndicatorToggle(
                    label: 'VWAP',
                    active: _showVWAP,
                    color: const Color(0xFF2196F3),
                    onTap: () => setState(() => _showVWAP = !_showVWAP)),
              ]),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 16)),

        // Chart coaching tip
        if (_candles.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child:
                  CoachingTip(message: _getChartCoachingTip(), icon: Icons.lightbulb_outline),
            ),
          ),

        // Pattern card
        if (!isGuest && _signalAnalysis?.patterns != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _PatternCard(patterns: _signalAnalysis!.patterns!),
            ),
          ),

        // Technical highlights
        if (widget.stock.technicalHighlights != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _TechnicalHighlightsSection(
                  highlights: widget.stock.technicalHighlights!),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  // ── Tab 2: Fundamental ──────────────────────────────────────────────────
  // Quick stat chips, full ratios, earnings chart, AI Claude analysis.
  Widget _buildFundamentalTab(
    bool isGuest,
    ThemeData theme,
    ColorScheme colorScheme,
    AsyncValue<EnhancedAIAnalysis>? analysisAsync,
  ) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 12)),

        // Quick stat chips (P/E, EPS, ROE …)
        if (_fundamentals != null && !widget.stock.isCrypto && _fundamentals!.hasRatios)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _FundamentalQuickStats(fundamentals: _fundamentals!),
            ),
          ),

        // Full fundamentals card
        if (_fundamentals != null && _fundamentals!.hasRatios) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: FundamentalsCard(data: _fundamentals!),
            ),
          ),
        ],

        // Earnings chart
        if (_fundamentals != null && _fundamentals!.quarterlyEps.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: EarningsChart(quarters: _fundamentals!.quarterlyEps),
            ),
          ),

        // Claude AI analysis (gated CTA → result)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: !_analysisRequested
                ? _AnalyseCTACard(
                    onTap: () => setState(() => _analysisRequested = true))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.auto_awesome,
                            color: colorScheme.primary, size: 18),
                        const SizedBox(width: 8),
                        Text('AI Analysis',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 18),
                          color: colorScheme.primary,
                          onPressed: () => ref
                              .invalidate(aiAnalysisProvider(widget.stock.ticker)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          color: Colors.white54,
                          onPressed: () =>
                              setState(() => _analysisRequested = false),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      if (analysisAsync != null)
                        analysisAsync.when(
                          loading: () => GlassCard(
                            padding: const EdgeInsets.symmetric(vertical: 36),
                            child: Column(children: [
                              CircularProgressIndicator(
                                  color: colorScheme.primary),
                              const SizedBox(height: 14),
                              Text(
                                  'Claude is analysing ${widget.stock.ticker}…',
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(color: Colors.white70)),
                            ]),
                          ),
                          error: (err, _) => GlassCard(
                            color: Colors.red.withValues(alpha: 0.08),
                            padding: const EdgeInsets.all(20),
                            child: Column(children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.redAccent, size: 36),
                              const SizedBox(height: 10),
                              Text(
                                  err
                                      .toString()
                                      .replaceFirst('Exception: ', ''),
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(color: Colors.white70)),
                              const SizedBox(height: 14),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                                onPressed: () => ref.invalidate(
                                    aiAnalysisProvider(widget.stock.ticker)),
                              ),
                            ]),
                          ),
                          data: (analysis) => EnhancedAnalysisDisplay(
                            analysis: analysis,
                            onRefresh: () => ref.invalidate(
                                aiAnalysisProvider(widget.stock.ticker)),
                          ),
                        ),
                    ],
                  ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  // ── Tab 3: Flow ─────────────────────────────────────────────────────────
  // Market position gauge, money flow bars, order book depth.
  Widget _buildFlowTab() {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 12)),

        // Market position sentiment gauge
        if (_signalAnalysis != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: MarketPositionWidget(
                signal: _signalAnalysis!,
                currentPrice: _liveQuote?.price ?? widget.stock.price,
              ),
            ),
          ),

        // Money flow — candle-computed bars + optional backend CMF section
        if (_candles.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: MoneyFlowWidget(
                candles: _candles,
                isCrypto: widget.stock.isCrypto,
                backendData: _moneyFlowData,
              ),
            ),
          ),

        // Order book depth
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: OrderBookWidget(
              symbol: widget.stock.ticker,
              isCrypto: widget.stock.isCrypto,
              currentPrice: _liveQuote?.price ?? widget.stock.price,
            ),
          ),
        ),

        // Options summary card (Phase 5) — graceful "unavailable" for crypto
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: OptionsCardWidget(
              symbol: widget.stock.ticker,
              isCrypto: widget.stock.isCrypto,
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  // ── Tab 4: Macro ────────────────────────────────────────────────────────
  // FRED macro environment, inflation/rates context, macro flags.
  Widget _buildMacroTab(bool isGuest) {
    final hasMacro = _macroOverview != null ||
        (_signalAnalysis?.correlation?.macroFlags.isNotEmpty ?? false);

    if (isGuest) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Sign in to view macro environment data.',
            style: TextStyle(color: Color(0xFF8A95A3), fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (!hasMacro) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.public_off, color: Color(0xFF8A95A3), size: 36),
            SizedBox(height: 12),
            Text('Macro data loading…',
                style: TextStyle(color: Color(0xFF8A95A3), fontSize: 14)),
          ]),
        ),
      );
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: MacroCard(
              macro: _macroOverview,
              macroFlags: _signalAnalysis?.correlation?.macroFlags ?? [],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLoadingChart() => Container(
    height: 320,
    alignment: Alignment.center,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text('Loading chart data...', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70)),
      ],
    ),
  );

  Widget _buildErrorChart() => Container(
    height: 320,
    alignment: Alignment.center,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, size: 64, color: Colors.redAccent.withValues(alpha: 0.7)),
        const SizedBox(height: 16),
        Text(_errorMessage ?? 'Failed to load chart',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
          onPressed: () {
            setState(() { _hasError = false; _errorMessage = null; });
            if (isCryptoSymbol(widget.stock.ticker)) { _subscribeToCandles(); }
            else { _fetchStockCandles(); }
          },
        ),
      ],
    ),
  );

  // ── Tab 5: Analyst — Phase 8 ──────────────────────────────────────────────
  // Full LangGraph pipeline: DeepSeek-R1 reasoning + Claude verification +
  // Cartesia TTS. Triggered by the "Run Deep Analysis" button.
  Widget _buildAnalystTab(bool isGuest) {
    if (isGuest) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, color: Colors.white24, size: 48),
              SizedBox(height: 16),
              Text(
                'Deep Analysis requires an account',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'Sign up for free to run the full\nDeepSeek-R1 + Claude analyst pipeline.',
                style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 16)),

        // ── CTA button (always shown until analysis runs) ─────────────────
        if (_analystResult == null && !_analystLoading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _AnalystCtaCard(
                symbol: widget.stock.ticker,
                onTap: _runDeepAnalysis,
              ),
            ),
          ),

        // ── Loading state ─────────────────────────────────────────────────
        if (_analystLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: _AnalystLoadingIndicator(),
            ),
          ),

        // ── Error state ───────────────────────────────────────────────────
        if (_analystError != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _AnalystErrorCard(
                error: _analystError!,
                onRetry: _runDeepAnalysis,
              ),
            ),
          ),

        // ── Results ───────────────────────────────────────────────────────
        if (_analystResult != null) ...[
          // Verification warning banner
          if (_analystResult!.isVerificationWarning)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: _VerificationWarningBanner(
                    claims: _analystResult!.flaggedClaims),
              ),
            ),

          // Dean's Coach Response
          if (_analystResult!.hasCoachResponse)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: _DeanCoachCard(
                  coachText: _analystResult!.coachResponse!,
                  audioUrl: _analystResult!.audioUrl,
                  audioPlaying: _audioPlaying,
                  onAudioTap: _analystResult!.audioUrl != null
                      ? () => _toggleAudio(_analystResult!.audioUrl!)
                      : null,
                  analystService: _analystService,
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 10)),

          // CoT Thinking card (collapsed by default)
          if (_analystResult!.hasThinking)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CotThinkingCard(thinking: _analystResult!.cotThinking!),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 10)),

          // Scenario cards
          if (_analystResult!.scenarioCards != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _AnalystScenarioSection(
                    scenarios: _analystResult!.scenarioCards!),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 10)),

          // Run again button
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton.icon(
                icon: const Icon(Icons.refresh, size: 16,
                    color: Color(0xFF12A28C)),
                label: const Text('Run again',
                    style: TextStyle(color: Color(0xFF12A28C), fontSize: 13)),
                onPressed: _runDeepAnalysis,
              ),
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

}

// ─── Private helper widgets ──────────────────────────────────────────────────

/// Hero price display — large whole part, muted smaller decimal.
class _IndicatorToggle extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _IndicatorToggle({required this.label, required this.active, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.15) : Colors.white10,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: active ? color.withValues(alpha: 0.5) : Colors.white12),
      ),
      child: Text(label, style: TextStyle(
          color: active ? color : Colors.white38, fontSize: 12, fontWeight: FontWeight.w600)),
    ),
  );
}

class _TradeTab extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _TradeTab(this.label, this.selected, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(
            color: selected ? color : Colors.white38, fontWeight: FontWeight.w700, fontSize: 14)),
      ),
    ),
  );
}

class _SheetTaxRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final bool bold;
  const _SheetTaxRow(this.label, this.value, this.valueColor, {this.bold = false});
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Text(label, style: TextStyle(
        color: Colors.white54, fontSize: 12, fontWeight: bold ? FontWeight.w700 : FontWeight.normal))),
    Text(value, style: TextStyle(
        color: valueColor, fontSize: 12, fontWeight: bold ? FontWeight.w700 : FontWeight.w600)),
  ]);
}

class _ContextBar extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  const _ContextBar({required this.label, required this.value, required this.sub});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(children: [
      Text('$label  ', style: const TextStyle(color: Colors.white38, fontSize: 12)),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
      const Spacer(),
      Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 11)),
    ]),
  );
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeChip(this.label, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: selected ? Colors.white38 : Colors.white12),
      ),
      child: Text(label, style: TextStyle(
          color: selected ? Colors.white : Colors.white38, fontSize: 12, fontWeight: FontWeight.w600)),
    ),
  );
}

class _QuickBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickBtn(this.label, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
    ),
  );
}

class _AnalyseCTACard extends StatelessWidget {
  final VoidCallback onTap;
  const _AnalyseCTACard({required this.onTap});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.auto_awesome, color: colorScheme.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Analyse This Chart with AI',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Get Claude\'s take on sentiment, price targets, risk & key factors',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60)),
          ])),
        ]),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [colorScheme.primary, colorScheme.primary.withValues(alpha: 0.75)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: onTap,
              icon: const Icon(Icons.psychology_outlined, size: 20),
              label: const Text('Analyse Now', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ),
      ]),
    );
  }
}

// Forward-declarations for widgets that exist in the old screen and are reused as-is
// These are imported from private sections we copy here (they depend on nothing external)

class CoachingTip extends StatelessWidget {
  final String message;
  final IconData icon;
  const CoachingTip({super.key, required this.message, required this.icon});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      color: theme.colorScheme.primary.withValues(alpha: 0.08),
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Icon(icon, color: theme.colorScheme.primary, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(message,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.9), height: 1.5))),
      ]),
    );
  }
}

class _EducationalDisclaimer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      color: Colors.orange.withValues(alpha: 0.1),
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        const Icon(Icons.school_outlined, color: Colors.orangeAccent, size: 24),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Educational Resource',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
          const SizedBox(height: 4),
          Text('This information is for learning purposes only. Not financial advice.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.9))),
        ])),
      ]),
    );
  }
}

class _TechnicalHighlightsSection extends StatelessWidget {
  final List<String> highlights;
  const _TechnicalHighlightsSection({required this.highlights});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.lightbulb_outline, color: theme.colorScheme.primary, size: 24),
          const SizedBox(width: 12),
          Text('Technical Insights',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 16),
        ...highlights.map((h) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(width: 6, height: 6,
                  decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(h,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9), height: 1.5))),
          ]),
        )),
      ]),
    );
  }
}

class _DecisionStrip extends StatelessWidget {
  final double price;
  final double changePercent;
  final SignalAnalysis? signalAnalysis;
  final bool signalLoading;

  const _DecisionStrip({
    required this.price,
    required this.changePercent,
    required this.signalAnalysis,
    required this.signalLoading,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = changePercent >= 0;
    final changeColor =
        isPositive ? const Color(0xFF2ECC9A) : const Color(0xFFFF5C5C);
    final changeSign = isPositive ? '+' : '';

    // Derive signal display values
    final label = signalAnalysis?.signalLabel ?? '';
    final score = signalAnalysis?.compositeScore ?? 0.0;
    final insight = signalAnalysis?.correlation?.scenarioDescription;

    final (pillText, pillFg, pillBg) = _pillStyle(label, signalLoading);

    return Container(
      color: const Color(0xFF0D131A),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Row 1: price + signal pill ──────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Price
              Text(
                '\$${price.toStringAsFixed(price >= 1000 ? 2 : price >= 10 ? 2 : 4)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 10),
              // % change badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: changeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$changeSign${changePercent.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: changeColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              // AI signal pill
              if (signalLoading)
                Container(
                  width: 88,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(20),
                  ),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    color: pillBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: pillFg,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        pillText,
                        style: TextStyle(
                          color: pillFg,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          // ── Row 2: score bar (only when loaded) ─────────────────────────
          if (!signalLoading && signalAnalysis != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (score.clamp(-1.0, 1.0) + 1.0) / 2.0,
                minHeight: 2,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation(
                  score >= 0
                      ? const Color(0xFF2ECC9A)
                      : const Color(0xFFFF5C5C),
                ),
              ),
            ),
          ],

          // ── Row 3: one-line actionable insight ──────────────────────────
          if (!signalLoading && insight != null && insight.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline,
                    size: 13, color: Color(0xFF8A95A3)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    insight,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF8A95A3),
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (signalLoading) ...[
            const SizedBox(height: 8),
            Container(
              height: 10,
              width: 220,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Returns (pillText, foreground color, background color) for the signal label.
  static (String, Color, Color) _pillStyle(String label, bool loading) {
    if (loading) return ('…', Colors.white38, Colors.white10);
    final u = label.toUpperCase();
    if (u == 'STRONG_BUY') {
      return ('STRONG BUY', const Color(0xFF12A28C), const Color(0x2012A28C));
    }
    if (u == 'BUY') {
      return ('BUY', const Color(0xFF2ECC9A), const Color(0x2000E676));
    }
    if (u == 'STRONG_SELL') {
      return ('STRONG SELL', const Color(0xFFFF5C5C), const Color(0x20F44336));
    }
    if (u == 'SELL') {
      return ('SELL', const Color(0xFFFF7070), const Color(0x20EF5350));
    }
    return ('NEUTRAL', const Color(0xFFF5A623), const Color(0x26F5A623));
  }
}

// ── Signal Engine Badge & skeleton ───────────────────────────────────────────

class _SignalBadge extends StatelessWidget {
  final SignalAnalysis? signalAnalysis;
  final bool isLoading;
  final VoidCallback onRefresh;
  const _SignalBadge({required this.signalAnalysis, required this.isLoading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const _SignalSkeleton();
    if (signalAnalysis == null) {
      return GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          const Icon(Icons.wifi_off, color: Colors.white24, size: 16),
          const SizedBox(width: 8),
          const Expanded(child: Text('Signal Engine unavailable',
              style: TextStyle(color: Colors.white38, fontSize: 11))),
          GestureDetector(
            onTap: onRefresh,
            child: const Text('Retry', style: TextStyle(color: Color(0xFF12A28C), fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
    }

    final sa = signalAnalysis!;
    final label = sa.signalLabel;
    final score = sa.compositeScore;
    final (labelColor, labelBg) = _labelColors(label);
    final scoreBarColor = score >= 0 ? const Color(0xFF12A28C) : Colors.redAccent;

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: labelBg, borderRadius: BorderRadius.circular(20)),
            child: Text(signalDisplayLabel(label),
                style: TextStyle(color: labelColor, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Score: ${score >= 0 ? "+" : ""}${score.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (score + 1.0) / 2.0,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation(scoreBarColor),
                minHeight: 5,
              ),
            ),
          ])),
          GestureDetector(onTap: onRefresh, child: const Icon(Icons.refresh, size: 16, color: Colors.white24)),
        ]),
        if (sa.signals.candlestick.pattern != null || sa.signals.indicators.rsiValue != null) ...[
          const SizedBox(height: 10),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 8),
          Row(children: [
            if (sa.signals.candlestick.pattern != null) ...[
              const Text('🕯', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Text(sa.signals.candlestick.pattern!,
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
              const SizedBox(width: 12),
            ],
            Text('RSI ${sa.signals.indicators.rsiValue?.toStringAsFixed(1) ?? '--'}',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ]),
        ],
      ]),
    );
  }

  (Color, Color) _labelColors(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('strong_buy') || lower.contains('strong buy')) {
      return (const Color(0xFF12A28C), const Color(0x2012A28C));
    }
    if (lower.contains('buy')) return (Colors.greenAccent, const Color(0x2000E676));
    if (lower.contains('strong_sell') || lower.contains('strong sell')) {
      return (Colors.red, const Color(0x20F44336));
    }
    if (lower.contains('sell')) return (Colors.redAccent, const Color(0x20EF5350));
    if (lower.contains('neutral')) return (const Color(0xFFF5A623), const Color(0x26F5A623));
    return (Colors.white70, Colors.white10);
  }
}

class _SignalSkeleton extends StatelessWidget {
  const _SignalSkeleton();
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(width: 80, height: 24, decoration: BoxDecoration(
          color: Colors.white12, borderRadius: BorderRadius.circular(12))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(height: 8, decoration: BoxDecoration(
              color: Colors.white12, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 6),
          Container(height: 5, decoration: BoxDecoration(
              color: Colors.white10, borderRadius: BorderRadius.circular(4))),
        ])),
      ]),
    );
  }
}

// ── Prediction + Correlation + Pattern cards (delegated from signal analysis) ─

class _ScenarioCard extends StatelessWidget {
  final Scenarios scenarios;
  const _ScenarioCard({required this.scenarios});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.bar_chart, color: cs.primary, size: 18),
          const SizedBox(width: 8),
          Text('Scenarios',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        _ScenarioRow(
          label: 'Bull',
          color: const Color(0xFF26A69A),
          scenario: scenarios.bull,
        ),
        const SizedBox(height: 8),
        _ScenarioRow(
          label: 'Base',
          color: cs.primary,
          scenario: scenarios.base,
        ),
        const SizedBox(height: 8),
        _ScenarioRow(
          label: 'Bear',
          color: const Color(0xFFEF5350),
          scenario: scenarios.bear,
        ),
      ]),
    );
  }
}

class _ScenarioRow extends StatelessWidget {
  final String label;
  final Color color;
  final ScenarioCase scenario;

  const _ScenarioRow({
    required this.label,
    required this.color,
    required this.scenario,
  });

  @override
  Widget build(BuildContext context) {
    final pct = scenario.probability.clamp(0, 100);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SizedBox(
          width: 36,
          child: Text(label,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct / 100.0,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color.withValues(alpha: 0.75)),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('$pct%',
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Text('\$${scenario.priceTarget.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ]),
      const SizedBox(height: 3),
      Padding(
        padding: const EdgeInsets.only(left: 44),
        child: Text(scenario.thesis,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
      ),
    ]);
  }
}

class _PredictionCard extends StatelessWidget {
  final PredictionResult prediction;
  const _PredictionCard({required this.prediction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.track_changes, color: cs.primary, size: 18),
          const SizedBox(width: 8),
          Text('Price Target', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${(prediction.probability * 100).toStringAsFixed(0)}% confidence',
                style: TextStyle(color: cs.primary, fontSize: 10, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _PriceColumn('Low', prediction.priceTargetLow, Colors.redAccent),
          _PriceColumn('Target', prediction.priceTargetBase, cs.primary),
          _PriceColumn('High', prediction.priceTargetHigh, Colors.greenAccent),
        ]),
        ...[
          const SizedBox(height: 10),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.shield_outlined, size: 14, color: Colors.orange),
            const SizedBox(width: 6),
            Text('Stop Loss: \$${prediction.stopLossSuggestion.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.orange, fontSize: 12)),
            const SizedBox(width: 12),
            Text('R/R: ${prediction.riskRewardRatio.toStringAsFixed(1)}x',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ],
        // Backtest row (Phase B) — shown only when data is available
        if (prediction.backtestWinRate != null) ...[
          const SizedBox(height: 8),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.history, size: 13, color: Colors.white38),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: 'Historical: ',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  TextSpan(
                    text: '${(prediction.backtestWinRate! * 100).toStringAsFixed(0)}% win rate',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  if (prediction.backtestAvgGainPct != null)
                    TextSpan(
                      text: ', avg ${prediction.backtestAvgGainPct!.toStringAsFixed(1)}% move',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  if (prediction.backtestSampleCount != null)
                    TextSpan(
                      text: ' (${prediction.backtestSampleCount} instances)',
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                ]),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _PriceColumn extends StatelessWidget {
  final String label;
  final double price;
  final Color color;
  const _PriceColumn(this.label, this.price, this.color);
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      const SizedBox(height: 4),
      Text('\$${price.toStringAsFixed(2)}', style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
    ]);
  }
}

class _CorrelationCard extends StatelessWidget {
  final CorrelationResult correlation;
  const _CorrelationCard({required this.correlation});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sentimentColor = correlation.newsSentimentScore > 0.2 ? Colors.greenAccent
        : correlation.newsSentimentScore < -0.2 ? Colors.redAccent : Colors.white70;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.bubble_chart, color: theme.colorScheme.primary, size: 18),
          const SizedBox(width: 8),
          Text('Correlation Analysis', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: sentimentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(correlation.sentimentLabel,
                style: TextStyle(color: sentimentColor, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 10),
        Text(correlation.scenarioDescription,
            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
        if (correlation.topHeadlines.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...correlation.topHeadlines.take(2).map((h) => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('• ', style: TextStyle(color: Colors.white38, fontSize: 11)),
              Expanded(child: Text(h, style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.4))),
            ]),
          )),
        ],
      ]),
    );
  }
}

class _PatternCard extends StatelessWidget {
  final PatternScanResult patterns;
  const _PatternCard({required this.patterns});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (patterns.patterns.isEmpty && patterns.supportResistance.isEmpty) return const SizedBox.shrink();
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.pattern, color: theme.colorScheme.primary, size: 18),
          const SizedBox(width: 8),
          Text('Detected Patterns', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('${patterns.patterns.length} pattern${patterns.patterns.length == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
        if (patterns.patterns.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: patterns.patterns.take(4).map((p) {
              final color = p.signal == 'BULLISH' ? Colors.greenAccent
                  : p.signal == 'BEARISH' ? Colors.redAccent : Colors.white54;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text(p.displayName,
                    style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
              );
            }).toList(),
          ),
        ],
        if (patterns.supportResistance.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 8),
          Text('S/R Levels', style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8, runSpacing: 4,
            children: patterns.supportResistance.take(4).map((sr) {
              final isSupport = sr.type == 'SUPPORT';
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isSupport ? Colors.green : Colors.red).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('\$${sr.price.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: isSupport ? Colors.greenAccent : Colors.redAccent,
                        fontSize: 11, fontWeight: FontWeight.w600)),
              );
            }).toList(),
          ),
        ],
      ]),
    );
  }
}

class _FundamentalQuickStats extends StatelessWidget {
  final FundamentalData fundamentals;
  const _FundamentalQuickStats({required this.fundamentals});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratios = <String, String>{};
    if (fundamentals.pe != null) ratios['P/E'] = fundamentals.pe!.toStringAsFixed(1);
    if (fundamentals.ps != null) ratios['P/S'] = fundamentals.ps!.toStringAsFixed(2);
    if (fundamentals.ttmEps != null) ratios['EPS'] = '\$${fundamentals.ttmEps!.toStringAsFixed(2)}';
    if (fundamentals.roe != null) ratios['ROE'] = '${fundamentals.roe!.toStringAsFixed(1)}%';
    if (ratios.isEmpty) return const SizedBox.shrink();
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: ratios.entries.map((e) => Column(children: [
          Text(e.key, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(height: 2),
          Text(e.value, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
        ])).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Phase 8 — Analyst Graph private widgets
// ═══════════════════════════════════════════════════════════════════════════

/// CTA card shown before the user has run deep analysis.
class _AnalystCtaCard extends StatelessWidget {
  final String symbol;
  final VoidCallback onTap;
  const _AnalystCtaCard({required this.symbol, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF12A28C).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.biotech, color: Color(0xFF12A28C), size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Deep Analysis', style: TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              Text('DeepSeek-R1 · Claude Sonnet · Cartesia TTS',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        const Text(
          'Runs the full 5-node LangGraph pipeline:\n'
          '• Intent classification (Mistral 7B)\n'
          '• Real-time market data & technicals\n'
          '• Deep reasoning (DeepSeek-R1 14B)\n'
          '• Fact verification (Claude Sonnet)\n'
          '• Voice synthesis (Cartesia TTS)',
          style: TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.6),
        ),
        const SizedBox(height: 6),
        const Text('⏱  ~60–90 seconds',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow_rounded, size: 20, color: Colors.white),
            label: Text('Run Deep Analysis on $symbol',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF12A28C),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: onTap,
          ),
        ),
      ]),
    );
  }
}

/// Animated loading indicator shown during the ~90 s analysis window.
class _AnalystLoadingIndicator extends StatefulWidget {
  const _AnalystLoadingIndicator();
  @override
  State<_AnalystLoadingIndicator> createState() => _AnalystLoadingIndicatorState();
}

class _AnalystLoadingIndicatorState extends State<_AnalystLoadingIndicator> {
  static const _steps = [
    'Classifying intent…',
    'Fetching market data…',
    'DeepSeek-R1 reasoning…',
    'Verifying with Claude…',
    'Synthesising response…',
  ];
  int _step = 0;

  @override
  void initState() {
    super.initState();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 14));
      if (!mounted) return false;
      setState(() => _step = (_step + 1).clamp(0, _steps.length - 1));
      return _step < _steps.length - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(
        width: 44, height: 44,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF12A28C)),
        ),
      ),
      const SizedBox(height: 20),
      Text(_steps[_step],
          style: const TextStyle(color: Colors.white70, fontSize: 14,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text('Step ${_step + 1} of ${_steps.length}',
          style: const TextStyle(color: Colors.white38, fontSize: 12)),
    ]);
  }
}

/// Error card shown when the analyst pipeline fails.
class _AnalystErrorCard extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _AnalystErrorCard({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
          SizedBox(width: 8),
          Text('Analysis Failed', style: TextStyle(
              color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        Text(error, style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.5)),
        const SizedBox(height: 14),
        TextButton.icon(
          icon: const Icon(Icons.refresh, size: 16, color: Color(0xFF12A28C)),
          label: const Text('Try again', style: TextStyle(color: Color(0xFF12A28C))),
          onPressed: onRetry,
        ),
      ]),
    );
  }
}

/// Yellow warning banner shown when Claude's verification flagged the analysis.
class _VerificationWarningBanner extends StatelessWidget {
  final List<String> claims;
  const _VerificationWarningBanner({required this.claims});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
          SizedBox(width: 6),
          Text('⚠️ Analysis flagged for review',
              style: TextStyle(color: Colors.orange,
                  fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
        if (claims.isNotEmpty) ...[
          const SizedBox(height: 6),
          ...claims.map((c) => Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('• $c',
                style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.4)),
          )),
        ],
      ]),
    );
  }
}

/// Dean's coach response card — 3–4 sentence verdict with optional audio button.
class _DeanCoachCard extends StatelessWidget {
  final String coachText;
  final String? audioUrl;
  final bool audioPlaying;
  final VoidCallback? onAudioTap;
  final AnalystGraphService analystService;

  const _DeanCoachCard({
    required this.coachText,
    this.audioUrl,
    required this.audioPlaying,
    required this.analystService,
    this.onAudioTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF12A28C).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.record_voice_over,
                color: Color(0xFF12A28C), size: 16),
          ),
          const SizedBox(width: 10),
          const Text('Dean',
              style: TextStyle(color: Colors.white,
                  fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF12A28C).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('AI Coach',
                style: TextStyle(color: Color(0xFF12A28C),
                    fontSize: 9, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 12),
        // Coach text inside AI block
        Container(
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: Color(0xFF12A28C), width: 2),
            ),
          ),
          padding: const EdgeInsets.only(left: 12),
          child: Text(coachText,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13.5, height: 1.6)),
        ),
        // Audio button (shown only when Cartesia URL is present)
        if (audioUrl != null) ...[
          const SizedBox(height: 14),
          const Divider(height: 1, color: Colors.white10),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onAudioTap,
            child: Row(children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF12A28C).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(
                  audioPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: const Color(0xFF12A28C), size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(audioPlaying ? 'Playing…' : 'Play voice summary',
                  style: const TextStyle(color: Color(0xFF12A28C),
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// Bull / Base / Bear scenario cards from the analyst synthesis node.
class _AnalystScenarioSection extends StatelessWidget {
  final AnalystScenarios scenarios;
  const _AnalystScenarioSection({required this.scenarios});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.bar_chart, color: Color(0xFF12A28C), size: 18),
          SizedBox(width: 8),
          Text('Scenarios',
              style: TextStyle(color: Colors.white,
                  fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        _AnalystScenarioRow(
          label: 'BULL',
          color: const Color(0xFF26A69A),
          card: scenarios.bull,
        ),
        const SizedBox(height: 10),
        _AnalystScenarioRow(
          label: 'BASE',
          color: const Color(0xFF12A28C),
          card: scenarios.base,
        ),
        const SizedBox(height: 10),
        _AnalystScenarioRow(
          label: 'BEAR',
          color: const Color(0xFFEF5350),
          card: scenarios.bear,
        ),
      ]),
    );
  }
}

class _AnalystScenarioRow extends StatelessWidget {
  final String label;
  final Color color;
  final AnalystScenarioCard card;

  const _AnalystScenarioRow({
    required this.label,
    required this.color,
    required this.card,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(label,
                style: TextStyle(color: color,
                    fontSize: 10, fontWeight: FontWeight.w800)),
          ),
          const Spacer(),
          if (card.probability.isNotEmpty)
            Text(card.probability,
                style: TextStyle(color: color,
                    fontSize: 12, fontWeight: FontWeight.w700)),
          if (card.target.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(card.target,
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ]),
        if (card.trigger.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(card.trigger,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12, height: 1.4)),
        ],
      ]),
    );
  }
}
