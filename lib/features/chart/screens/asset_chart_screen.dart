// ignore_for_file: library_private_types_in_public_api
import 'dart:async';

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
import '../../../services/pattern_recognition_service.dart';
import '../../../services/backend_service.dart';
import '../../../utils/crypto_helper.dart';
import '../../../widgets/glass_card.dart';
import '../../../widgets/macro_card.dart';
import '../../../widgets/chart/advanced_indicator_settings.dart';
import '../../../widgets/chart/chart_type_selector.dart';
import '../../../widgets/educational_bottom_sheet.dart';
import '../../../widgets/earnings_chart.dart';
import '../../../widgets/fundamentals_card.dart';
import '../../../widgets/price_range_bar.dart';
import '../../../providers/analysis_provider.dart';
import '../../../providers/portfolio_provider.dart';
import '../../../providers/paper_trading_provider.dart';
import '../../../screens/analysis/_enhanced_analysis_display.dart';
import '../controllers/chart_controller.dart';
import '../models/chart_overlay.dart';
import '../widgets/market_chart.dart';
import '../widgets/timeframe_selector.dart';
import '../widgets/chart_toolbar.dart';

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

class _AssetChartScreenState extends ConsumerState<AssetChartScreen> {
  final _candleService = BinanceCandleService();
  final _quoteService = BinanceQuoteService();
  final _backendService = BackendService();
  final _chartController = ChartController();

  StreamSubscription<List<Candle>>? _candleSubscription;
  StreamSubscription<Map<String, Quote>>? _quoteSubscription;

  List<Candle> _candles = [];
  Quote? _liveQuote;
  bool _isWatchlisted = false;
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

  double get _chartHeight {
    if (_showRSI && _showMACD) return 500;
    if (_showRSI || _showMACD) return 430;
    return 340;
  }

  @override
  void initState() {
    super.initState();
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
    if (!widget.stock.isCrypto) _fetchFundamentals();
  }

  Future<void> _fetchMarketRange() async {
    final range = await _backendService.getPriceRange(widget.stock.ticker);
    if (mounted && range != null) setState(() => _marketRange = range);
  }

  Future<void> _fetchFundamentals() async {
    final data = await _backendService.getFundamentals(widget.stock.ticker);
    if (mounted && data != null) setState(() => _fundamentals = data);
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

  Future<void> _fetchSignalAnalysis() async {
    if (!mounted) return;
    setState(() { _signalLoading = true; _signalAnalysis = null; });
    final interval = isCryptoSymbol(widget.stock.ticker) ? '1h' : '1d';
    final result = await _backendService.analyseStock(widget.stock.ticker, interval: interval);
    if (mounted) setState(() { _signalAnalysis = result; _signalLoading = false; });
  }

  String _binanceInterval(String tf) {
    const map = {
      '1m': '1m', '5m': '5m', '15m': '15m', '30m': '30m',
      '1h': '1h', '2h': '2h', '4h': '4h', '12h': '12h',
      '1D': '1d', '1W': '1w', '4W': '1d', '1M': '1M',
      '3M': '1d', '6M': '1d', '1Y': '1w', '5Y': '1w',
    };
    return map[tf] ?? '1d';
  }

  void _subscribeToCandles() {
    _candleSubscription?.cancel();
    _candleSubscription = _candleService
        .streamCandles(widget.stock.ticker, interval: _binanceInterval(_timeframe))
        .listen(
      (candles) {
        if (mounted) {
          setState(() {
            _candles = candles;
            _hasError = false;
            _errorMessage = null;
          });
          _chartController.setCandles(candles);
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

  Future<void> _fetchStockCandles() async {
    setState(() { _isLoading = true; _hasError = false; _candles = []; });

    String interval; int limit; String yfRange;
    switch (_timeframe) {
      case '1m':  interval = '1m';   limit = 120;  yfRange = '1d';   break;
      case '5m':  interval = '5m';   limit = 288;  yfRange = '1d';   break;
      case '15m': interval = '15m';  limit = 192;  yfRange = '2d';   break;
      case '30m': interval = '30m';  limit = 96;   yfRange = '2d';   break;
      case '1h':  interval = '1h';   limit = 168;  yfRange = '7d';   break;
      case '2h':  interval = '2h';   limit = 168;  yfRange = '14d';  break;
      case '4h':  interval = '4h';   limit = 180;  yfRange = '30d';  break;
      case '12h': interval = '12h';  limit = 180;  yfRange = '90d';  break;
      case '1W':  interval = '1d';   limit = 7;    yfRange = '5d';   break;
      case '4W':  interval = '1d';   limit = 28;   yfRange = '1mo';  break;
      case '1M':  interval = '1d';   limit = 30;   yfRange = '1mo';  break;
      case '3M':  interval = '1d';   limit = 90;   yfRange = '3mo';  break;
      case '6M':  interval = '1d';   limit = 180;  yfRange = '6mo';  break;
      case '1Y':  interval = '1wk';  limit = 52;   yfRange = '1y';   break;
      case '5Y':  interval = '1wk';  limit = 260;  yfRange = '5y';   break;
      default:    interval = '1d';   limit = 365;  yfRange = '1y';   break;
    }

    List<Candle> candles = [];

    final raw = await _backendService.getCandles(widget.stock.ticker, interval: interval, limit: limit);
    if (raw.isNotEmpty) candles = raw.map((r) => Candle.fromMap(r)).toList();

    if (candles.isEmpty) {
      final av = AlphaVantageCandleService();
      final all = await av.fetchDailyCandles(widget.stock.ticker, days: 400);
      if (all.isNotEmpty) candles = all.length > limit ? all.sublist(all.length - limit) : all;
    }

    if (candles.isEmpty) {
      final yf = YahooFinanceCandleService();
      candles = await yf.fetchCandles(widget.stock.ticker, interval: interval, range: yfRange);
    }

    if (mounted) {
      setState(() {
        _candles = candles;
        _isLoading = false;
        _hasError = candles.isEmpty;
        if (candles.isEmpty) _errorMessage = 'No chart data for ${widget.stock.ticker}';
      });
      if (candles.isNotEmpty) _chartController.setCandles(candles);
    }
  }

  void _onTimeframeChanged(String tf) {
    setState(() => _timeframe = tf);
    if (isCryptoSymbol(widget.stock.ticker)) {
      _subscribeToCandles();
    } else {
      _fetchStockCandles();
    }
  }

  void _toggleWatchlist() {
    setState(() => _isWatchlisted = !_isWatchlisted);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_isWatchlisted ? 'Added to watchlist' : 'Removed from watchlist'),
      duration: const Duration(seconds: 1),
    ));
  }

  OverlayData _buildOverlays() {
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

    return OverlayData(
      maLines: maLines,
      bollinger: bollinger,
      srLines: srLines,
      patterns: _signalAnalysis?.patterns,
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
    _candleSubscription?.cancel();
    _quoteSubscription?.cancel();
    _candleService.dispose();
    _quoteService.dispose();
    _chartController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    AsyncValue<EnhancedAIAnalysis>? analysisAsync;
    if (_analysisRequested) {
      analysisAsync = ref.watch(aiAnalysisProvider(widget.stock.ticker));
    }

    final displayPrice = _liveQuote?.price ?? widget.stock.price;
    final displayChange = _liveQuote?.changePercent ?? widget.stock.changePercent;
    final isPositive = displayChange >= 0;
    final changeColor = isPositive ? Colors.greenAccent : Colors.redAccent;

    // Compute indicator data once for sub-panels
    final rsiValues = _candles.isNotEmpty ? TechnicalAnalysisService.calculateRSIHistory(_candles) : <double?>[];
    final macdData = _candles.isNotEmpty ? TechnicalAnalysisService.calculateMACDHistory(_candles) : <String, List<double?>>{};

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
            icon: Icon(_isWatchlisted ? Icons.bookmark : Icons.bookmark_border,
                color: _isWatchlisted ? colorScheme.primary : Colors.white70),
            onPressed: _toggleWatchlist,
            tooltip: _isWatchlisted ? 'Remove from watchlist' : 'Add to watchlist',
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
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Asset Header ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _AssetHeader(
                stock: widget.stock,
                price: displayPrice,
                changePercent: displayChange,
                isPositive: isPositive,
                changeColor: changeColor,
                isLive: _liveQuote != null,
              ),
            ),
          ),

          if (_marketRange != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: PriceRangeBars(range: _marketRange!, isCrypto: widget.stock.isCrypto),
              ),
            ),

          if (_fundamentals != null && !widget.stock.isCrypto && _fundamentals!.hasRatios)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: _FundamentalQuickStats(fundamentals: _fundamentals!),
              ),
            ),

          // ── Signal Badge ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _SignalBadge(
                signalAnalysis: _signalAnalysis,
                isLoading: _signalLoading,
                onRefresh: _fetchSignalAnalysis,
              ),
            ),
          ),

          if (_signalAnalysis?.prediction != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: _PredictionCard(prediction: _signalAnalysis!.prediction!),
              ),
            ),

          if (_signalAnalysis?.correlation != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: _CorrelationCard(correlation: _signalAnalysis!.correlation!),
              ),
            ),

          // Macro card (Phase A) — FRED macro environment + context flags
          if (_macroOverview != null ||
              (_signalAnalysis?.correlation?.macroFlags.isNotEmpty ?? false))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: MacroCard(
                  macro: _macroOverview,
                  macroFlags: _signalAnalysis?.correlation?.macroFlags ?? [],
                ),
              ),
            ),

          if (_signalAnalysis?.patterns != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: _PatternCard(patterns: _signalAnalysis!.patterns!),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Chart Toolbar (timeframe + type + gear) ──
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
                ),
              ]),
            ),
          ),

          // ── Main CustomPainter Chart ──
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
                          overlays: _buildOverlays(),
                          height: _chartHeight,
                          onPatternTap: _showChartPatternSheet,
                          rsiValues: rsiValues,
                          macdLine: macdData['macd'] ?? [],
                          signalLine: macdData['signal'] ?? [],
                          histogram: macdData['histogram'] ?? [],
                          showRSI: _showRSI,
                          showMACD: _showMACD,
                        ),
            ),
          ),

          // ── Indicator toggles (RSI / MACD) ──
          if (_candles.isNotEmpty)
            SliverToBoxAdapter(
              child: Container(
                color: const Color(0xFF0D1117),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  _IndicatorToggle(
                      label: 'RSI', active: _showRSI,
                      color: const Color(0xFF4CAF50),
                      onTap: () => setState(() => _showRSI = !_showRSI)),
                  const SizedBox(width: 8),
                  _IndicatorToggle(
                      label: 'MACD', active: _showMACD,
                      color: const Color(0xFFFFEB3B),
                      onTap: () => setState(() => _showMACD = !_showMACD)),
                ]),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── AI Analysis ──
          if (!_analysisRequested)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _AnalyseCTACard(onTap: () => setState(() => _analysisRequested = true)),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.auto_awesome, color: colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text('AI Analysis', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        color: colorScheme.primary,
                        onPressed: () => ref.invalidate(aiAnalysisProvider(widget.stock.ticker)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        color: Colors.white54,
                        onPressed: () => setState(() => _analysisRequested = false),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    if (analysisAsync != null)
                      analysisAsync.when(
                        loading: () => GlassCard(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(children: [
                            CircularProgressIndicator(color: colorScheme.primary),
                            const SizedBox(height: 16),
                            Text('Claude is analysing ${widget.stock.ticker}…',
                                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70)),
                          ]),
                        ),
                        error: (err, _) => GlassCard(
                          color: Colors.red.withValues(alpha: 0.08),
                          padding: const EdgeInsets.all(20),
                          child: Column(children: [
                            const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                            const SizedBox(height: 12),
                            Text(err.toString().replaceFirst('Exception: ', ''),
                                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70)),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                              onPressed: () => ref.invalidate(aiAnalysisProvider(widget.stock.ticker)),
                            ),
                          ]),
                        ),
                        data: (analysis) => EnhancedAnalysisDisplay(
                          analysis: analysis,
                          onRefresh: () => ref.invalidate(aiAnalysisProvider(widget.stock.ticker)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Coaching Tip ──
          if (_candles.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: CoachingTip(message: _getChartCoachingTip(), icon: Icons.lightbulb_outline),
              ),
            ),

          if (_candles.isNotEmpty) const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // ── Fundamentals ──
          if (_fundamentals != null && _fundamentals!.hasRatios) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: FundamentalsCard(data: _fundamentals!),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],

          if (_fundamentals != null && _fundamentals!.quarterlyEps.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: EarningsChart(quarters: _fundamentals!.quarterlyEps),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          if (widget.stock.technicalHighlights != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _TechnicalHighlightsSection(highlights: widget.stock.technicalHighlights!),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _EducationalDisclaimer(),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

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
}

// ─── Private helper widgets ──────────────────────────────────────────────────

/// Hero price display — large whole part, muted smaller decimal.
class _HeroPriceText extends StatelessWidget {
  final double price;
  const _HeroPriceText({required this.price});

  @override
  Widget build(BuildContext context) {
    final decimals = price < 1 ? 4 : 2;
    final formatted = price.toStringAsFixed(decimals);
    final dotIndex = formatted.indexOf('.');
    final whole = '\$${formatted.substring(0, dotIndex)}';
    final decimal = formatted.substring(dotIndex); // includes the dot

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          whole,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 42,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
            height: 1.0,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(
            decimal,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 24,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.5,
              height: 1.0,
            ),
          ),
        ),
      ],
    );
  }
}

class _AssetHeader extends StatelessWidget {
  final StockSummary stock;
  final double price;
  final double changePercent;
  final bool isPositive;
  final Color changeColor;
  final bool isLive;

  const _AssetHeader({
    required this.stock, required this.price, required this.changePercent,
    required this.isPositive, required this.changeColor, required this.isLive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(stock.name,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            if (isLive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6,
                      decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('LIVE', style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary, fontWeight: FontWeight.bold)),
                ]),
              ),
          ]),
          const SizedBox(height: 4),
          if (stock.sector != null)
            Text('${stock.sector}${stock.industry != null ? ' • ${stock.industry}' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _HeroPriceText(price: price),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: changeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(isPositive ? Icons.arrow_upward : Icons.arrow_downward, color: changeColor, size: 16),
                const SizedBox(width: 4),
                Text('${isPositive ? '+' : ''}${changePercent.toStringAsFixed(2)}%',
                    style: theme.textTheme.titleMedium?.copyWith(color: changeColor, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
          if (stock.fundamentals != null) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16, runSpacing: 12,
              children: stock.fundamentals!.entries.take(4).map((e) =>
                  _FundamentalChip(label: e.key, value: e.value)).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _FundamentalChip extends StatelessWidget {
  final String label;
  final String value;
  const _FundamentalChip({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54)),
      const SizedBox(height: 4),
      Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
    ]);
  }
}

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

class _EducationalInsightsPanel extends StatelessWidget {
  final List<Candle> candles;
  final List<double?> rsi;
  final Map<String, List<double?>> macd;
  const _EducationalInsightsPanel({required this.candles, required this.rsi, required this.macd});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insights = PatternRecognitionService.generateInsights(candles, rsi, macd);
    if (insights.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const Icon(Icons.analytics_outlined, size: 48, color: Colors.white38),
          const SizedBox(height: 12),
          Text('No notable patterns detected',
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.white70), textAlign: TextAlign.center),
        ]),
      );
    }
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome, color: theme.colorScheme.primary, size: 24),
          const SizedBox(width: 12),
          Text('Market Insights', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${insights.length}', style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 16),
        ...insights.map((i) => _InsightCard(insight: i)),
      ]),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final MarketInsight insight;
  const _InsightCard({required this.insight});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _colorFor(insight.type);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(insight.icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(child: Text(insight.title,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: color))),
          ]),
          const SizedBox(height: 12),
          Text(insight.description,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9), height: 1.5)),
        ]),
      ),
    );
  }

  Color _colorFor(InsightType type) {
    switch (type) {
      case InsightType.technical: return Colors.blueAccent;
      case InsightType.pattern: return Colors.purpleAccent;
      case InsightType.supportResistance: return Colors.orangeAccent;
      case InsightType.divergence: return Colors.greenAccent;
    }
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
    if (fundamentals.roe != null) ratios['ROE'] = '${(fundamentals.roe! * 100).toStringAsFixed(1)}%';
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
