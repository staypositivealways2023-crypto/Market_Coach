import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../../models/candle.dart';
import '../../models/quote.dart';
import '../../models/stock_summary.dart';
import '../../services/candle_service.dart';
import '../../services/quote_service.dart';
import '../../services/technical_analysis_service.dart';
import '../../services/pattern_recognition_service.dart';
import '../../utils/crypto_helper.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/chart/advanced_price_chart.dart';
import '../../widgets/chart/chart_type_selector.dart';
import '../../widgets/chart/rsi_sub_chart.dart';
import '../../widgets/chart/macd_sub_chart.dart';
import '../../widgets/chart/advanced_indicator_settings.dart';
import '../../widgets/educational_bottom_sheet.dart';
import '../../models/enhanced_ai_analysis.dart';
import '../../models/fundamentals.dart';
import '../../models/market_detail.dart';
import '../../providers/analysis_provider.dart';
import '../../services/backend_service.dart';
import '../../widgets/earnings_chart.dart';
import '../../widgets/fundamentals_card.dart';
import '../../widgets/price_range_bar.dart';
import '../analysis/_enhanced_analysis_display.dart';
import '../../providers/iq_score_provider.dart';
import '../../widgets/trade_debrief_sheet.dart';
import '../../models/signal_analysis.dart';
import '../../models/holding.dart';
import '../../models/paper_account.dart';
import '../../providers/portfolio_provider.dart';
import '../../providers/paper_trading_provider.dart';

class StockDetailScreenEnhanced extends ConsumerStatefulWidget {
  final StockSummary stock;

  const StockDetailScreenEnhanced({super.key, required this.stock});

  @override
  ConsumerState<StockDetailScreenEnhanced> createState() => _StockDetailScreenEnhancedState();
}

class _StockDetailScreenEnhancedState extends ConsumerState<StockDetailScreenEnhanced> {
  final _candleService = BinanceCandleService();  // crypto only
  final _quoteService = BinanceQuoteService();     // crypto live quotes

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
  String _timeframe = '1h'; // overridden in initState for stocks
  bool _showRSI = true;
  bool _showMACD = true;

  // Indicator settings
  MAType _maType = MAType.none;
  bool _showBollingerBands = false;
  SRType _srType = SRType.none;
  SubChartType _subChartType = SubChartType.rsi;

  // Backend data
  final _backendService = BackendService();
  MarketRange? _marketRange;
  FundamentalData? _fundamentals;

  // Signal Engine (Phase 3)
  SignalAnalysis? _signalAnalysis;
  bool _signalLoading = true;   // true so skeleton shows on first frame

  // AI Analysis
  bool _analysisRequested = false;

  // Portfolio
  bool _inPortfolio = false;

  @override
  void initState() {
    super.initState();
    _timeframe = '1D';
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fetchSignalAnalysis();
        _checkPortfolio();
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
    if (mounted && range != null) {
      setState(() => _marketRange = range);
    }
  }

  Future<void> _fetchFundamentals() async {
    final data = await _backendService.getFundamentals(widget.stock.ticker);
    if (mounted && data != null) {
      setState(() => _fundamentals = data);
    }
  }

  void _showChartPatternSheet(ChartPatternResult pat) {
    final signalColor = pat.signal == 'BULLISH'
        ? const Color(0xFF12A28C)
        : pat.signal == 'BEARISH'
            ? Colors.redAccent
            : Colors.white54;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111925),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  pat.displayName,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: signalColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: signalColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(pat.signal,
                    style: TextStyle(color: signalColor, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${(pat.confidence * 100).toStringAsFixed(0)}% confidence',
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
            if (pat.keyPrice != null) ...[
              const SizedBox(height: 4),
              Text('Key level: \$${pat.keyPrice!.toStringAsFixed(pat.keyPrice! >= 100 ? 2 : 4)}',
                style: TextStyle(color: signalColor, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 14),
            Text(
              _patternEducationText(pat.type),
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.55),
            ),
          ],
        ),
      ),
    );
  }

  static String _patternEducationText(String type) {
    const map = <String, String>{
      'DOUBLE_TOP':
          'Two peaks at roughly the same price — sellers rejected the same level twice. Usually signals a bearish reversal. Sell pressure often increases on the break below the trough between the two peaks.',
      'DOUBLE_BOTTOM':
          'Two troughs at roughly the same price — buyers defended the same level twice. Usually signals a bullish reversal. Momentum often accelerates on the break above the peak between the two lows.',
      'HEAD_SHOULDERS':
          'Three peaks where the middle is the highest. Left and right shoulders at similar heights. Classic bearish reversal. Break below the neckline is the signal.',
      'INV_HEAD_SHOULDERS':
          'Three troughs where the middle is lowest — the inverse of Head & Shoulders. Classic bullish reversal. Break above the neckline confirms.',
      'ASCENDING_TRIANGLE':
          'Flat resistance with higher lows. Buyers are getting more aggressive each dip. Usually resolves as a bullish breakout through the flat top.',
      'DESCENDING_TRIANGLE':
          'Flat support with lower highs. Sellers push harder on each rally. Usually resolves as a bearish breakdown through the flat bottom.',
      'SYMMETRICAL_TRIANGLE':
          'Lower highs and higher lows converging. Neither buyers nor sellers dominate — a big move is compressed. Direction of breakout determines the signal.',
      'BULL_FLAG':
          'Strong upward move (pole) followed by tight, sideways consolidation (flag). Breakout above the flag top with volume surge is the entry signal.',
      'BEAR_FLAG':
          'Sharp downward move followed by brief consolidation. Breakdown below flag low confirms continuation.',
      'WEDGE_RISING':
          'Price rises in a tightening channel. Despite the upward movement, often signals weakening momentum and a potential reversal downward.',
      'WEDGE_FALLING':
          'Price falls in a tightening channel. Buyers gradually step in at higher lows — often signals a bullish reversal when price breaks the upper trendline.',

      // ── Single-candle patterns ──
      'DOJI':
          'Open and close are almost the same price — neither buyers nor sellers won. A Doji signals indecision in the market. After a long trend, it often warns of a reversal. Context matters: a Doji in the middle of consolidation is far less meaningful.',
      'HAMMER':
          'A small body at the top with a long lower shadow at least twice the body length. Buyers pushed price back up after sellers drove it down hard. Found at the bottom of downtrends, it signals potential bullish reversal. Confirmation on the next candle (green close above the hammer) strengthens the signal.',
      'HANGING_MAN':
          'Looks identical to a hammer but appears at the top of an uptrend — making it bearish. The long lower shadow shows sellers briefly took control. Bulls recovered, but the warning is there. Confirmation on the next candle (red close below the hanging man) is needed.',
      'SHOOTING_STAR':
          'A small body at the bottom with a long upper shadow. Buyers tried to push price higher but failed — sellers rejected the rally and pushed price back down. Found at the top of uptrends, it signals potential bearish reversal. The longer the upper shadow, the more powerful the rejection.',
      'INVERTED_HAMMER':
          'Looks like a shooting star but appears at the bottom of a downtrend — making it potentially bullish. Buyers tested higher levels. Even though price pulled back, it shows buyers are stepping in. Needs a bullish confirmation candle to be acted on.',
      'MARUBOZU':
          'A candle with almost no wicks — the open is at one extreme and the close at the other. A bullish Marubozu (green) means buyers dominated the entire session with no pullback. A bearish one (red) means sellers controlled the entire move. Signals very strong conviction in the direction.',

      // ── Two-candle patterns ──
      'BULLISH_ENGULFING':
          'A bearish (red) candle followed by a larger bullish (green) candle whose body fully covers the previous one. Buyers completely overwhelmed sellers. One of the strongest single-pivot reversal signals. Most powerful when it occurs after a sustained downtrend and on high volume.',
      'BEARISH_ENGULFING':
          'A bullish (green) candle followed by a larger bearish (red) candle whose body fully covers the previous one. Sellers took complete control. Most reliable at the top of an uptrend. Higher volume on the engulfing candle increases the signal strength.',
      'BULLISH_HARAMI':
          'A large bearish candle followed by a small bullish candle whose body fits inside the first candle. "Harami" means "pregnant" in Japanese — the small candle is contained within the large one. Selling momentum is slowing. Less powerful than engulfing, but a warning that the downtrend may be pausing.',
      'BEARISH_HARAMI':
          'A large bullish candle followed by a small bearish candle whose body fits inside the first candle. Buying momentum is losing steam. The market is hesitating after a strong up move. A red confirmation candle after the harami strengthens the bearish case.',

      // ── Three-candle patterns ──
      'MORNING_STAR':
          'Three-candle bullish reversal: (1) large bearish candle, (2) small-bodied candle that gaps below (the "star" — indecision), (3) large bullish candle that closes above the midpoint of candle 1. Signals the bottom of a downtrend. One of the most reliable multi-candle reversal patterns.',
      'EVENING_STAR':
          'Three-candle bearish reversal: (1) large bullish candle, (2) small-bodied candle that gaps above (the "star" — indecision), (3) large bearish candle that closes below the midpoint of candle 1. Signals the top of an uptrend. The bearish counterpart to the Morning Star — equally reliable.',
    };
    return map[type] ?? 'Pattern detected based on price action analysis.';
  }

  Future<void> _checkPortfolio() async {
    final service = ref.read(portfolioServiceProvider);
    if (service == null) return;
    final h = await service.getHolding(widget.stock.ticker);
    if (mounted) setState(() => _inPortfolio = h != null);
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add ${widget.stock.ticker} to Portfolio',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              TextField(
                controller: sharesCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Number of Shares',
                  labelStyle: TextStyle(color: Colors.white54),
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
                  labelText: 'Avg Cost Per Share (\$)',
                  labelStyle: TextStyle(color: Colors.white54),
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
                  onPressed: saving
                      ? null
                      : () async {
                          final shares = double.tryParse(sharesCtrl.text.trim());
                          final cost = double.tryParse(costCtrl.text.trim());
                          if (shares == null || shares <= 0 || cost == null || cost <= 0) return;
                          setSheet(() => saving = true);
                          await service.upsert(Holding(
                            symbol: widget.stock.ticker,
                            name: widget.stock.name,
                            shares: shares,
                            avgCost: cost,
                            addedAt: DateTime.now(),
                          ));
                          if (mounted) setState(() => _inPortfolio = true);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                  child: saving
                      ? const SizedBox(height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Add to Portfolio',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to use paper trading')));
      return;
    }

    final currentPrice = _liveQuote?.price ?? widget.stock.price;
    bool isBuy = startAsBuy;
    // byDollars = true → user types $ amount; false → user types shares
    bool byDollars = true;
    final inputCtrl = TextEditingController();
    bool saving = false;
    String? error;

    // Parse the raw input into shares based on mode
    double parsedShares(String text, PaperHolding? holding) {
      final v = double.tryParse(text.trim()) ?? 0;
      if (byDollars) return currentPrice > 0 ? v / currentPrice : 0;
      return v;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D1520),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          // Quick-fill helpers
          void setInput(String v) {
            inputCtrl.text = v;
            setSheet(() => error = null);
          }

          return FutureBuilder<List<dynamic>>(
            future: Future.wait([
              service.streamAccount().first,
              service.getHolding(widget.stock.ticker),
            ]),
            builder: (ctx, snap) {
              final account = snap.data?[0] as PaperAccount?;
              final holding = snap.data?[1] as PaperHolding?;

              final rawVal = double.tryParse(inputCtrl.text.trim()) ?? 0;
              final sharesEntered = byDollars
                  ? (currentPrice > 0 ? rawVal / currentPrice : 0)
                  : rawVal;
              final dollarValue = byDollars ? rawVal : rawVal * currentPrice;

              // Sell tax estimate
              double? grossPnl, taxEst, afterTaxEst;
              if (!isBuy && holding != null && sharesEntered > 0) {
                grossPnl = (currentPrice - holding.avgCost) * sharesEntered;
                taxEst = grossPnl > 0 ? grossPnl * holding.taxRate : 0;
                afterTaxEst = grossPnl - taxEst;
              }

              final accent = isBuy ? const Color(0xFF12A28C) : Colors.redAccent;

              return Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 36, height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Header: ticker + live price
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
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('PAPER', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                    ]),

                    if (account == null) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'Activate Paper Trading first.\nGo to Portfolio → Paper Trading tab.',
                        style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
                      ),
                    ] else ...[
                      const SizedBox(height: 16),

                      // ── BUY / SELL toggle ─────────────────────────────────
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

                      // ── Account context ───────────────────────────────────
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
                          sub: 'Avg \$${holding.avgCost.toStringAsFixed(2)} · ${holding.holdingDays ?? 0}d held · ${holding.isShortTerm ? '22%' : '15%'} tax',
                        )
                      else
                        const _ContextBar(label: 'Position', value: 'None', sub: 'You have no shares to sell'),

                      const SizedBox(height: 14),

                      // ── $ or Shares toggle ────────────────────────────────
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

                      // ── Main input ────────────────────────────────────────
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
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // ── Quick-fill buttons ────────────────────────────────
                      if (isBuy) ...[
                        Row(children: [
                          for (final amt in [100, 500, 1000, 5000]) ...[
                            _QuickBtn('\$$amt', () => setInput(byDollars ? '$amt' : (amt / currentPrice).toStringAsFixed(4))),
                            const SizedBox(width: 6),
                          ],
                          _QuickBtn('Max', () {
                            final max = account.cashBalance;
                            setInput(byDollars
                                ? max.toStringAsFixed(2)
                                : (max / currentPrice).toStringAsFixed(4));
                          }),
                        ]),
                      ] else if (holding != null) ...[
                        Row(children: [
                          for (final pct in [25, 50, 75]) ...[
                            _QuickBtn('$pct%', () {
                              final s = holding.shares * pct / 100;
                              setInput(byDollars
                                  ? (s * currentPrice).toStringAsFixed(2)
                                  : s.toStringAsFixed(4));
                            }),
                            const SizedBox(width: 6),
                          ],
                          _QuickBtn('All', () {
                            setInput(byDollars
                                ? (holding.shares * currentPrice).toStringAsFixed(2)
                                : holding.shares.toStringAsFixed(4));
                          }),
                        ]),
                      ],

                      // ── Sell tax breakdown ────────────────────────────────
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
                                '${holding.isShortTerm ? 'Short' : 'Long'}-term gains · '
                                '${(holding.taxRate * 100).toStringAsFixed(0)}% tax',
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

                      // ── Confirm button ────────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: accent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          onPressed: saving
                              ? null
                              : () async {
                                  final shares = parsedShares(inputCtrl.text, holding);
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
                                      ref.invalidate(iqScoreProvider);
                                      showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        backgroundColor: Colors.transparent,
                                        builder: (_) => TradeDebriefSheet(
                                          symbol: widget.stock.ticker,
                                          name: widget.stock.name,
                                          isBuy: isBuy,
                                          shares: shares,
                                          price: currentPrice,
                                          totalValue: dollarValue,
                                          signalAnalysis: _signalAnalysis,
                                        ),
                                      );
                                    }
                                  }
                                },
                          child: saving
                              ? const SizedBox(height: 22, width: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(
                                  isBuy
                                      ? 'Buy ${widget.stock.ticker}'
                                      : 'Sell ${widget.stock.ticker}',
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

  Future<void> _fetchSignalAnalysis() async {
    if (!mounted) return;
    setState(() { _signalLoading = true; _signalAnalysis = null; });
    final interval = isCryptoSymbol(widget.stock.ticker) ? '1h' : '1d';
    final result = await _backendService.analyseStock(
      widget.stock.ticker,
      interval: interval,
    );
    if (mounted) setState(() { _signalAnalysis = result; _signalLoading = false; });
  }

  /// Maps unified UI timeframe → Binance kline interval string.
  String _binanceInterval(String tf) {
    const map = {
      '1m': '1m', '5m': '5m', '15m': '15m', '30m': '30m',
      '1h': '1h', '2h': '2h', '4h': '4h', '12h': '12h',
      '1D': '1d', '1W': '1w',
      '4W': '1d',  // 28 daily candles
      '1M': '1M',  // Binance monthly
      '3M': '1d',  // 90 daily candles
      '6M': '1d',  // 180 daily candles
      '1Y': '1w',  // 52 weekly candles
      '5Y': '1w',  // 260 weekly candles
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
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = 'Failed to load chart data. Please try again.';
          });
        }
      },
    );
  }

  void _subscribeToQuotes() {
    _quoteSubscription?.cancel();

    _quoteSubscription = _quoteService
        .streamQuotes({widget.stock.ticker})
        .listen(
      (quotes) {
        if (mounted) {
          setState(() => _liveQuote = quotes[widget.stock.ticker]);
        }
      },
      onError: (error) {
        // Quote errors are non-critical, just log them
        debugPrint('Quote stream error: $error');
      },
    );
  }

  @override
  void dispose() {
    _candleSubscription?.cancel();
    _quoteSubscription?.cancel();
    _candleService.dispose();
    _quoteService.dispose();
    super.dispose();
  }

  void _onTimeframeChanged(String timeframe) {
    setState(() => _timeframe = timeframe);
    if (isCryptoSymbol(widget.stock.ticker)) {
      _subscribeToCandles();
    } else {
      _fetchStockCandles();
    }
  }

  Future<void> _fetchStockCandles() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
      _candles = [];
    });

    String interval;
    int limit;
    String yfRange;
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
      default:    interval = '1d';   limit = 365;  yfRange = '1y';   break; // '1D'
    }

    List<Candle> candles = [];

    // 1. Try Python backend (fastest, most accurate)
    final raw = await _backendService.getCandles(
      widget.stock.ticker, interval: interval, limit: limit,
    );
    if (raw.isNotEmpty) {
      candles = raw.map((r) => Candle.fromMap(r)).toList();
    }

    // 2. Alpha Vantage fallback (we have 2 keys, 25 req/day each)
    if (candles.isEmpty) {
      final av = AlphaVantageCandleService();
      final all = await av.fetchDailyCandles(widget.stock.ticker, days: 400);
      if (all.isNotEmpty) {
        candles = all.length > limit ? all.sublist(all.length - limit) : all;
      }
    }

    // 3. Yahoo Finance fallback (no key needed)
    if (candles.isEmpty) {
      final yf = YahooFinanceCandleService();
      candles = await yf.fetchCandles(
        widget.stock.ticker,
        interval: interval,
        range: yfRange,
      );
    }

    if (mounted) {
      setState(() {
        _candles = candles;
        _isLoading = false;
        _hasError = candles.isEmpty;
        if (candles.isEmpty) {
          _errorMessage = 'No chart data for ${widget.stock.ticker}';
        }
      });
    }
  }

  void _toggleWatchlist() {
    setState(() => _isWatchlisted = !_isWatchlisted);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isWatchlisted
              ? 'Added to watchlist'
              : 'Removed from watchlist',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Watch analysis provider only after user taps "Analyse" (lazy — no API call until needed)
    AsyncValue<EnhancedAIAnalysis>? analysisAsync;
    if (_analysisRequested) {
      analysisAsync = ref.watch(aiAnalysisProvider(widget.stock.ticker));
    }

    // Use live quote if available, otherwise use stock data
    final displayPrice = _liveQuote?.price ?? widget.stock.price;
    final displayChange = _liveQuote?.changePercent ?? widget.stock.changePercent;
    final isPositive = displayChange >= 0;
    final changeColor = isPositive ? Colors.greenAccent : Colors.redAccent;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.stock.ticker),
        centerTitle: false,
        actions: [
          // Portfolio button
          IconButton(
            icon: Icon(
              _inPortfolio ? Icons.pie_chart : Icons.pie_chart_outline,
              color: _inPortfolio ? colorScheme.primary : Colors.white70,
            ),
            onPressed: _showAddToPortfolioSheet,
            tooltip: _inPortfolio ? 'In portfolio — tap to edit' : 'Add to portfolio',
          ),
          // Watchlist button
          IconButton(
            icon: Icon(
              _isWatchlisted ? Icons.bookmark : Icons.bookmark_border,
              color: _isWatchlisted ? colorScheme.primary : Colors.white70,
            ),
            onPressed: _toggleWatchlist,
            tooltip: _isWatchlisted ? 'Remove from watchlist' : 'Add to watchlist',
          ),
          const SizedBox(width: 8),
        ],
      ),
      // ── Sticky Buy / Sell bar ───────────────────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0D131A),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
          ),
          child: Row(children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => _showPaperTradeSheet(startAsBuy: true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF12A28C),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('BUY',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('\$${(_liveQuote?.price ?? widget.stock.price).toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _showPaperTradeSheet(startAsBuy: false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('SELL',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('\$${(_liveQuote?.price ?? widget.stock.price).toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ]),
              ),
            ),
          ]),
        ),
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Asset Header Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _AssetHeaderSection(
                stock: widget.stock,
                price: displayPrice,
                changePercent: displayChange,
                isPositive: isPositive,
                changeColor: changeColor,
                isLive: _liveQuote != null,
              ),
            ),
          ),

          // Price Range Bar (day + 52W range from backend)
          if (_marketRange != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: PriceRangeBars(range: _marketRange!, isCrypto: widget.stock.isCrypto),
              ),
            ),

          // Fundamental quick-stats (stocks only, shown when loaded)
          if (_fundamentals != null && !widget.stock.isCrypto && _fundamentals!.hasRatios)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: _FundamentalQuickStats(fundamentals: _fundamentals!),
              ),
            ),

          // Crypto market stats (mkt cap + 24h vol)
          if (widget.stock.isCrypto && _marketRange != null &&
              (_marketRange!.marketCap != null || _marketRange!.volume != null))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: _CryptoQuickStats(range: _marketRange!),
              ),
            ),

          // Signal Engine badge
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

          // Prediction Engine card (Phase 4) — price target + risk/reward
          if (_signalAnalysis?.prediction != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: _PredictionCard(prediction: _signalAnalysis!.prediction!),
              ),
            ),

          // Correlation card (Phase 5) — news × price scenario + fundamentals
          if (_signalAnalysis?.correlation != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: _CorrelationCard(correlation: _signalAnalysis!.correlation!),
              ),
            ),

          // Pattern card (Phase 6) — chart patterns + S/R levels
          if (_signalAnalysis?.patterns != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: _PatternCard(patterns: _signalAnalysis!.patterns!),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Chart Toolbar ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: const Color(0xFF0D1117),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  // Timeframe pills
                  Expanded(
                    child: _TimeframeSelector(
                      selectedTimeframe: _timeframe,
                      onChanged: _onTimeframeChanged,
                      isCrypto: isCryptoSymbol(widget.stock.ticker),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Chart type icon
                  _ChartTypeButton(
                    chartType: _chartType,
                    onChanged: (t) => setState(() => _chartType = t),
                  ),
                  const SizedBox(width: 4),
                  // Indicators gear
                  IconButton(
                    icon: const Icon(Icons.tune, size: 18, color: Colors.white54),
                    onPressed: _showIndicatorSettings,
                    tooltip: 'Indicators',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),

          // ── Main Chart ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: const Color(0xFF0D1117),
              child: _hasError
                  ? _buildErrorChart()
                  : (_isLoading || _candles.isEmpty)
                      ? _buildLoadingChart()
                      : AdvancedPriceChart(
                          key: ValueKey(_timeframe),
                          candles: _candles,
                          chartType: _chartType,
                          trackballBehavior: TrackballBehavior(
                            enable: true,
                            activationMode: ActivationMode.singleTap,
                            lineType: TrackballLineType.vertical,
                            lineColor: Colors.white24,
                            lineWidth: 1,
                            lineDashArray: const [4, 4],
                            tooltipSettings: const InteractiveTooltip(
                              enable: true,
                              color: Color(0xFF1A2435),
                              borderColor: Color(0xFF12A28C),
                              borderWidth: 1,
                              textStyle: TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                            markerSettings: const TrackballMarkerSettings(
                              markerVisibility: TrackballVisibilityMode.visible,
                              width: 8,
                              height: 8,
                              borderWidth: 2,
                              borderColor: Color(0xFF12A28C),
                              color: Colors.white,
                            ),
                          ),
                          maType: _maType,
                          showBollingerBands: _showBollingerBands,
                          srType: _srType,
                          patterns: _signalAnalysis?.patterns,
                          onPatternTap: _showChartPatternSheet,
                        ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── AI Analysis Section ────────────────────────────────────────
          if (!_analysisRequested)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _AnalyseCTACard(
                  onTap: () => setState(() => _analysisRequested = true),
                ),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section header
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, color: colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'AI Analysis',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          color: colorScheme.primary,
                          tooltip: 'Refresh analysis',
                          onPressed: () => ref.invalidate(aiAnalysisProvider(widget.stock.ticker)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          color: Colors.white54,
                          tooltip: 'Hide analysis',
                          onPressed: () => setState(() => _analysisRequested = false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Async states
                    if (analysisAsync == null)
                      const SizedBox.shrink()
                    else
                      analysisAsync.when(
                        loading: () => GlassCard(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            children: [
                              CircularProgressIndicator(color: colorScheme.primary),
                              const SizedBox(height: 16),
                              Text(
                                'Claude is analysing ${widget.stock.ticker}…',
                                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Fetching market data & running AI analysis',
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
                              ),
                            ],
                          ),
                        ),
                        error: (err, _) => GlassCard(
                          color: Colors.red.withValues(alpha: 0.08),
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                              const SizedBox(height: 12),
                              Text(
                                err.toString().replaceFirst('Exception: ', ''),
                                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                                onPressed: () => ref.invalidate(aiAnalysisProvider(widget.stock.ticker)),
                              ),
                            ],
                          ),
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

          // Coaching Tip for Chart Interpretation
          if (_candles.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: CoachingTip(
                  message: _getChartCoachingTip(),
                  icon: Icons.lightbulb_outline,
                ),
              ),
            ),

          if (_candles.isNotEmpty) const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Indicator Sub-Charts ───────────────────────────────────────
          if (_candles.isNotEmpty) ...[
            // RSI
            if (_showRSI)
              SliverToBoxAdapter(
                child: Container(
                  color: const Color(0xFF0D1117),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 1, color: Colors.white12),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                        child: Row(children: [
                          Text('RSI 14', style: TextStyle(color: Colors.purple[200], fontSize: 11, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => EducationalBottomSheet.show(context, EducationalContent.rsi),
                            child: const Icon(Icons.help_outline, size: 14, color: Colors.white38),
                          ),
                        ]),
                      ),
                      RsiSubChart(
                        candles: _candles,
                        rsiValues: TechnicalAnalysisService.calculateRSIHistory(_candles),
                      ),
                    ],
                  ),
                ),
              ),

            // MACD
            if (_showMACD)
              SliverToBoxAdapter(
                child: Container(
                  color: const Color(0xFF0D1117),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 1, color: Colors.white12),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                        child: Row(children: [
                          Text('MACD 12 26 9', style: TextStyle(color: Colors.blue[200], fontSize: 11, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => EducationalBottomSheet.show(context, EducationalContent.macd),
                            child: const Icon(Icons.help_outline, size: 14, color: Colors.white38),
                          ),
                        ]),
                      ),
                      Builder(builder: (context) {
                        final macd = TechnicalAnalysisService.calculateMACDHistory(_candles);
                        return MacdSubChart(
                          candles: _candles,
                          macdLine: macd['macd']!,
                          signalLine: macd['signal']!,
                          histogram: macd['histogram']!,
                        );
                      }),
                    ],
                  ),
                ),
              ),

            // Toggle buttons row
            SliverToBoxAdapter(
              child: Container(
                color: const Color(0xFF0D1117),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    _IndicatorToggle(label: 'RSI', active: _showRSI, color: Colors.purple[200]!, onTap: () => setState(() => _showRSI = !_showRSI)),
                    const SizedBox(width: 8),
                    _IndicatorToggle(label: 'MACD', active: _showMACD, color: Colors.blue[200]!, onTap: () => setState(() => _showMACD = !_showMACD)),
                  ],
                ),
              ),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // Educational Insights Panel
          if (_candles.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _EducationalInsightsPanel(
                  candles: _candles,
                  rsi: TechnicalAnalysisService.calculateRSIHistory(_candles),
                  macd: TechnicalAnalysisService.calculateMACDHistory(_candles),
                ),
              ),
            ),

          if (_candles.isNotEmpty) const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // Fundamentals + Earnings (real data from backend)
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

          // Technical Highlights
          if (widget.stock.technicalHighlights != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _TechnicalHighlightsSection(
                  highlights: widget.stock.technicalHighlights!,
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // Educational Disclaimer
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

  Widget _buildLoadingChart() {
    return Container(
      height: 350,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Loading chart data...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Connecting to market data',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorChart() {
    return Container(
      height: 350,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.redAccent.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'Failed to load chart',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            onPressed: () {
              setState(() {
                _hasError = false;
                _errorMessage = null;
              });
              if (isCryptoSymbol(widget.stock.ticker)) {
                _subscribeToCandles();
              } else {
                _fetchStockCandles();
              }
            },
          ),
        ],
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
      case ChartType.bar:
        return 'Bar charts show OHLC data like candlesticks but without filled bodies. A traditional way to view price action.';
    }
  }

  void _showIndicatorSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AdvancedIndicatorSettings(
        movingAverageType: _maType,
        showBollingerBands: _showBollingerBands,
        supportResistanceType: _srType,
        subChartType: _subChartType,
        onMATypeChanged: (maType) {
          setState(() => _maType = maType);
        },
        onBollingerBandsChanged: (showBB) {
          setState(() => _showBollingerBands = showBB);
        },
        onSRTypeChanged: (srType) {
          setState(() => _srType = srType);
        },
        onSubChartChanged: (subChartType) {
          setState(() => _subChartType = subChartType);
        },
      ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    icon: const Icon(Icons.help_outline, size: 18),
                    label: const Text('Moving Averages'),
                    onPressed: () {
                      Navigator.pop(context);
                      EducationalBottomSheet.show(
                        context,
                        EducationalContent.movingAverages,
                      );
                    },
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    icon: const Icon(Icons.help_outline, size: 18),
                    label: const Text('Support/Resistance'),
                    onPressed: () {
                      Navigator.pop(context);
                      EducationalBottomSheet.show(
                        context,
                        EducationalContent.supportResistance,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_showBollingerBands)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton.icon(
                icon: const Icon(Icons.help_outline, size: 18),
                label: const Text('Bollinger Bands Explained'),
                onPressed: () {
                  Navigator.pop(context);
                  EducationalBottomSheet.show(
                    context,
                    EducationalContent.bollingerBands,
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// Paper trade buy/sell tab
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
            child: Text(label,
                style: TextStyle(
                    color: selected ? color : Colors.white38,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
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
        Expanded(
            child: Text(label,
                style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.normal))),
        Text(value,
            style: TextStyle(
                color: valueColor,
                fontSize: 12,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600)),
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
            border: Border.all(
              color: selected ? Colors.white38 : Colors.white12,
            ),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? Colors.white : Colors.white38,
                  fontSize: 12, fontWeight: FontWeight.w600)),
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
          child: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      );
}

// Asset Header Section Widget
class _AssetHeaderSection extends StatelessWidget {
  final StockSummary stock;
  final double price;
  final double changePercent;
  final bool isPositive;
  final Color changeColor;
  final bool isLive;

  const _AssetHeaderSection({
    required this.stock,
    required this.price,
    required this.changePercent,
    required this.isPositive,
    required this.changeColor,
    required this.isLive,
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
          // Name + Live Badge
          Row(
            children: [
              Expanded(
                child: Text(
                  stock.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isLive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'LIVE',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 4),

          // Sector + Industry
          if (stock.sector != null)
            Text(
              '${stock.sector}${stock.industry != null ? ' • ${stock.industry}' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white70,
              ),
            ),

          const SizedBox(height: 16),

          // Price + Change
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${price.toStringAsFixed(price < 1 ? 4 : 2)}',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: changeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                      color: changeColor,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${isPositive ? '+' : ''}${changePercent.toStringAsFixed(2)}%',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: changeColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Quick Fundamentals Preview (if available)
          if (stock.fundamentals != null) ...[
            const Divider(height: 1),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: stock.fundamentals!.entries.take(4).map((entry) {
                return _FundamentalChip(
                  label: entry.key,
                  value: entry.value,
                );
              }).toList(),
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

  const _FundamentalChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white54,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// Timeframe Selector Widget — unified list for both crypto and stocks
class _TimeframeSelector extends StatelessWidget {
  final String selectedTimeframe;
  final ValueChanged<String> onChanged;
  // isCrypto kept for API compatibility but not used — same list for both
  final bool isCrypto;

  const _TimeframeSelector({
    required this.selectedTimeframe,
    required this.onChanged,
    this.isCrypto = false,
  });

  // Unified timeframe list — intraday → daily → range
  static const _timeframes = [
    '1m', '5m', '15m', '30m',
    '1h', '2h', '4h', '12h',
    '1D', '1W', '4W',
    '1M', '3M', '6M', '1Y', '5Y',
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _timeframes.map((tf) {
          final isSelected = tf == selectedTimeframe;
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: GestureDetector(
              onTap: () => onChanged(tf),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF12A28C)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF12A28C)
                        : Colors.white12,
                  ),
                ),
                child: Text(
                  tf,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white54,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}


// Technical Highlights Section Widget
class _TechnicalHighlightsSection extends StatelessWidget {
  final List<String> highlights;

  const _TechnicalHighlightsSection({required this.highlights});

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
              Icon(
                Icons.lightbulb_outline,
                color: theme.colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Technical Insights',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...highlights.map((highlight) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      highlight,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// Educational Insights Panel Widget
class _EducationalInsightsPanel extends StatelessWidget {
  final List<Candle> candles;
  final List<double?> rsi;
  final Map<String, List<double?>> macd;

  const _EducationalInsightsPanel({
    required this.candles,
    required this.rsi,
    required this.macd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insights = PatternRecognitionService.generateInsights(candles, rsi, macd);

    if (insights.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 48,
              color: Colors.white38,
            ),
            const SizedBox(height: 12),
            Text(
              'No notable patterns detected',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Charts are in a neutral state. Continue monitoring for new patterns.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white54,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                color: theme.colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Market Insights',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${insights.length} ${insights.length == 1 ? 'insight' : 'insights'}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...insights.map((insight) => _InsightCard(insight: insight)),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final MarketInsight insight;

  const _InsightCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _getInsightColor(insight.type).withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  insight.icon,
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    insight.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _getInsightColor(insight.type),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              insight.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
                height: 1.5,
              ),
            ),
            if (insight.relatedLessonId != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                icon: const Icon(Icons.school_outlined, size: 16),
                label: const Text('Learn More'),
                onPressed: () {
                  // TODO: Navigate to lesson detail screen
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Opening lesson: ${insight.relatedLessonId}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getInsightColor(InsightType type) {
    switch (type) {
      case InsightType.technical:
        return Colors.blueAccent;
      case InsightType.pattern:
        return Colors.purpleAccent;
      case InsightType.supportResistance:
        return Colors.orangeAccent;
      case InsightType.divergence:
        return Colors.greenAccent;
    }
  }
}

// AI Analyse CTA Card
class _AnalyseCTACard extends StatelessWidget {
  final VoidCallback onTap;

  const _AnalyseCTACard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.auto_awesome, color: colorScheme.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Analyse This Chart with AI',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Get Claude\'s take on sentiment, price targets, risk & key factors',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primary,
                    colorScheme.primary.withValues(alpha: 0.75),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: onTap,
                icon: const Icon(Icons.psychology_outlined, size: 20),
                label: const Text(
                  'Analyse Now',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Educational Disclaimer Widget
class _EducationalDisclaimer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassCard(
      color: Colors.orange.withValues(alpha: 0.1),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(
            Icons.school_outlined,
            color: Colors.orangeAccent,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Educational Resource',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.orangeAccent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This information is for learning purposes only. Not financial advice.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartTypeButton extends StatelessWidget {
  final ChartType chartType;
  final ValueChanged<ChartType> onChanged;
  const _ChartTypeButton({required this.chartType, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final icons = {
      ChartType.candlestick: Icons.candlestick_chart,
      ChartType.line: Icons.show_chart,
      ChartType.area: Icons.area_chart,
      ChartType.bar: Icons.bar_chart,
    };
    final types = ChartType.values;
    final current = types.indexOf(chartType);
    final next = types[(current + 1) % types.length];
    return IconButton(
      icon: Icon(icons[chartType], size: 18, color: Colors.white70),
      onPressed: () => onChanged(next),
      tooltip: 'Chart type',
      visualDensity: VisualDensity.compact,
    );
  }
}

class _IndicatorToggle extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _IndicatorToggle({required this.label, required this.active, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.15) : Colors.white10,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? color.withValues(alpha: 0.5) : Colors.white12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? color : Colors.white38,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ── Signal Engine Badge ─────────────────────────────────────────────────────

class _SignalBadge extends StatelessWidget {
  final SignalAnalysis? signalAnalysis;
  final bool isLoading;
  final VoidCallback onRefresh;

  const _SignalBadge({
    required this.signalAnalysis,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return _SignalSkeleton();
    }
    if (signalAnalysis == null) {
      // Backend unreachable — show a tappable "retry" card
      return GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.wifi_off, color: Colors.white24, size: 16),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Signal Engine unavailable — check console for error',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
            GestureDetector(
              onTap: onRefresh,
              child: const Text(
                'Retry',
                style: TextStyle(color: Color(0xFF12A28C), fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    final sa = signalAnalysis!;
    final label = sa.signalLabel;
    final score = sa.compositeScore;
    final cs = sa.signals.candlestick;
    final ind = sa.signals.indicators;

    final (labelColor, labelBg) = _labelColors(label);
    final scoreBarColor = score >= 0 ? const Color(0xFF12A28C) : Colors.redAccent;

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: signal chip + score bar + refresh
          Row(
            children: [
              // Signal chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: labelBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  signalDisplayLabel(label),
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Score bar
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Composite Score: ${score >= 0 ? "+" : ""}${score.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (score + 1.0) / 2.0,   // map -1..+1 → 0..1
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation(scoreBarColor),
                        minHeight: 5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16, color: Colors.white38),
                visualDensity: VisualDensity.compact,
                tooltip: 'Refresh signals',
                onPressed: onRefresh,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Indicator pills row
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (cs.pattern != null)
                _Pill(
                  label: cs.pattern!,
                  color: _signalColor(cs.signal),
                ),
              _Pill(
                label: 'RSI ${ind.rsiValue?.toStringAsFixed(0) ?? "--"} (${ind.rsiSignal})',
                color: _rsiColor(ind.rsiSignal),
              ),
              _Pill(
                label: 'MACD ${ind.macdSignal}',
                color: _macdColor(ind.macdSignal),
              ),
              _Pill(
                label: ind.emaStack.replaceAll('_', ' '),
                color: _emaColor(ind.emaStack),
              ),
              _Pill(
                label: 'Vol ${ind.volume.replaceAll("_", " ")}',
                color: ind.volume == 'ABOVE_AVERAGE'
                    ? Colors.tealAccent
                    : Colors.white38,
              ),
            ],
          ),
        ],
      ),
    );
  }

  (Color, Color) _labelColors(String label) {
    switch (label) {
      case 'STRONG_BUY': return (Colors.white, const Color(0xFF0D7A3E));
      case 'BUY':        return (const Color(0xFF12A28C), const Color(0xFF12A28C).withValues(alpha: 0.18));
      case 'STRONG_SELL': return (Colors.white, const Color(0xFF8B1A1A));
      case 'SELL':       return (Colors.redAccent, Colors.redAccent.withValues(alpha: 0.18));
      default:           return (Colors.white60, Colors.white12);
    }
  }

  Color _signalColor(String signal) {
    if (signal == 'BULLISH') return const Color(0xFF12A28C);
    if (signal == 'BEARISH') return Colors.redAccent;
    return Colors.white38;
  }

  Color _rsiColor(String signal) {
    if (signal == 'OVERSOLD')   return const Color(0xFF12A28C);
    if (signal == 'OVERBOUGHT') return Colors.redAccent;
    return Colors.white38;
  }

  Color _macdColor(String signal) {
    if (signal.contains('BULL')) return const Color(0xFF12A28C);
    if (signal.contains('BEAR')) return Colors.redAccent;
    return Colors.white38;
  }

  Color _emaColor(String stack) {
    if (stack.startsWith('PRICE_ABOVE')) return const Color(0xFF12A28C);
    if (stack.startsWith('PRICE_BELOW')) return Colors.redAccent;
    return Colors.white38;
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SignalSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 90, height: 26,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 10, color: Colors.white10),
                const SizedBox(height: 5),
                Container(height: 5, color: Colors.white10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Prediction Card (Phase 4) ────────────────────────────────────────────────

class _PredictionCard extends StatelessWidget {
  final PredictionResult prediction;
  const _PredictionCard({required this.prediction});

  @override
  Widget build(BuildContext context) {
    final p = prediction;
    final isBull = p.direction == 'BULLISH';
    final isBear = p.direction == 'BEARISH';
    final dirColor = isBull
        ? const Color(0xFF12A28C)
        : isBear
            ? Colors.redAccent
            : Colors.white54;

    final retSign = p.expectedReturnPct >= 0 ? '+' : '';
    final fmt = _fmtPrice;

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(Icons.track_changes, color: dirColor, size: 16),
              const SizedBox(width: 6),
              Text(
                'Price Target  •  ${p.horizon}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Direction + probability chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: dirColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: dirColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${p.direction}  ${(p.probability * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: dirColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Price range bar
          _PriceRangeRow(
            low:     p.priceTargetLow,
            base:    p.priceTargetBase,
            high:    p.priceTargetHigh,
            current: p.priceCurrent,
            dirColor: dirColor,
          ),

          const SizedBox(height: 12),

          // Stats row
          Row(
            children: [
              _StatCell(
                label: 'Return',
                value: '$retSign${p.expectedReturnPct.toStringAsFixed(1)}%',
                valueColor: p.expectedReturnPct >= 0
                    ? const Color(0xFF12A28C)
                    : Colors.redAccent,
              ),
              _StatCell(
                label: 'Risk/Reward',
                value: '${p.riskRewardRatio.toStringAsFixed(1)}:1',
                valueColor: p.riskRewardRatio >= 2
                    ? const Color(0xFF12A28C)
                    : Colors.white70,
              ),
              _StatCell(
                label: 'Stop Loss',
                value: fmt(p.stopLossSuggestion),
                valueColor: Colors.redAccent.withValues(alpha: 0.85),
              ),
              _StatCell(
                label: 'ATR(14)',
                value: fmt(p.atr14),
                valueColor: Colors.white38,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtPrice(double v) {
    if (v >= 10000) return '\$${v.toStringAsFixed(0)}';
    if (v >= 100)   return '\$${v.toStringAsFixed(2)}';
    if (v >= 1)     return '\$${v.toStringAsFixed(3)}';
    return '\$${v.toStringAsFixed(5)}';
  }
}

class _PriceRangeRow extends StatelessWidget {
  final double low, base, high, current;
  final Color dirColor;
  const _PriceRangeRow({
    required this.low, required this.base,
    required this.high, required this.current,
    required this.dirColor,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = _fmt;
    return Row(
      children: [
        // Low label
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fmt(low), style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w700)),
            const Text('Low', style: TextStyle(color: Colors.white38, fontSize: 9)),
          ],
        ),
        const SizedBox(width: 8),
        // Bar
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Background track
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Colored fill from low→high
              Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.redAccent.withValues(alpha: 0.6),
                      dirColor.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Base marker
              Align(
                alignment: _barPosition(low, base, high),
                child: Container(
                  width: 2,
                  height: 12,
                  color: dirColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // High label
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(fmt(high), style: TextStyle(color: dirColor, fontSize: 11, fontWeight: FontWeight.w700)),
            const Text('High', style: TextStyle(color: Colors.white38, fontSize: 9)),
          ],
        ),
      ],
    );
  }

  Alignment _barPosition(double lo, double val, double hi) {
    if (hi == lo) return Alignment.center;
    final frac = ((val - lo) / (hi - lo)).clamp(0.0, 1.0);
    return Alignment(frac * 2 - 1, 0);
  }

  String _fmt(double v) {
    if (v >= 10000) return '\$${v.toStringAsFixed(0)}';
    if (v >= 100)   return '\$${v.toStringAsFixed(2)}';
    if (v >= 1)     return '\$${v.toStringAsFixed(2)}';
    return '\$${v.toStringAsFixed(4)}';
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  const _StatCell({required this.label, required this.value, required this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(color: valueColor, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
        ],
      ),
    );
  }
}

// ── Correlation Card (Phase 5) ────────────────────────────────────────────────

class _CorrelationCard extends StatelessWidget {
  final CorrelationResult correlation;
  const _CorrelationCard({required this.correlation});

  @override
  Widget build(BuildContext context) {
    final c = correlation;
    final sentColor = c.sentimentLabel == 'positive'
        ? const Color(0xFF12A28C)
        : c.sentimentLabel == 'negative'
            ? Colors.redAccent
            : Colors.white54;

    final scenarioColor = _scenarioColor(c.scenario);

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.newspaper_outlined, color: Colors.white54, size: 15),
              const SizedBox(width: 6),
              const Text(
                'News × Price Correlation',
                style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              // Sentiment chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: sentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sentColor.withValues(alpha: 0.35)),
                ),
                child: Text(
                  c.sentimentLabel.toUpperCase(),
                  style: TextStyle(color: sentColor, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Scenario label + description
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: scenarioColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scenarioColor.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.scenarioLabel,
                  style: TextStyle(color: scenarioColor, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  c.scenarioDescription,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),

          // High-impact flags
          if (c.highImpactFlags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: c.highImpactFlags.map((flag) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Text(
                  flag,
                  style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              )).toList(),
            ),
          ],

          // Top headlines
          if (c.topHeadlines.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...c.topHeadlines.map((h) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: TextStyle(color: Colors.white30, fontSize: 11)),
                  Expanded(
                    child: Text(
                      h,
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            )),
          ],

          // Fundamental score (stocks only)
          if (c.fundamentalScore != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Text(
                  'Fundamental Score',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const Spacer(),
                Text(
                  '${c.fundamentalScore}/100',
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 6),
                _GradeChip(grade: c.fundamentalGrade ?? '?'),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (c.fundamentalScore ?? 0) / 100.0,
                minHeight: 4,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _gradeColor(c.fundamentalGrade ?? '?'),
                ),
              ),
            ),
            if (c.fundamentalSignals.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...c.fundamentalSignals.take(3).map((sig) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  ', style: TextStyle(color: Colors.white24, fontSize: 10)),
                    Expanded(
                      child: Text(
                        sig,
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ],
        ],
      ),
    );
  }

  Color _scenarioColor(String scenario) {
    if (scenario.contains('BULLISH') || scenario == 'QUIET_RISING' || scenario == 'POSITIVE_FLAT') {
      return const Color(0xFF12A28C);
    }
    if (scenario.contains('BEARISH') || scenario == 'QUIET_FALLING' || scenario == 'NEGATIVE_FLAT') {
      return Colors.redAccent;
    }
    return Colors.white54;
  }

  Color _gradeColor(String grade) {
    switch (grade) {
      case 'A': return const Color(0xFF12A28C);
      case 'B': return Colors.lightGreenAccent;
      case 'C': return Colors.amber;
      case 'D': return Colors.orange;
      default:  return Colors.redAccent;
    }
  }
}

class _GradeChip extends StatelessWidget {
  final String grade;
  const _GradeChip({required this.grade});

  @override
  Widget build(BuildContext context) {
    final color = _color(grade);
    return Container(
      width: 26,
      height: 20,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      alignment: Alignment.center,
      child: Text(
        grade,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }

  Color _color(String g) {
    switch (g) {
      case 'A': return const Color(0xFF12A28C);
      case 'B': return Colors.lightGreenAccent;
      case 'C': return Colors.amber;
      case 'D': return Colors.orange;
      default:  return Colors.redAccent;
    }
  }
}

// ── Fundamental Quick Stats (below price header) ──────────────────────────────

// Explanations shown when user taps the info icon
final _kFundExplanations = <String, _FundExplain>{
  'Mkt Cap':    _FundExplain('Market Capitalisation',
      'Total market value of all outstanding shares. Reflects the company\'s size: Mega (>\$200B), Large (>\$10B), Mid (>\$2B), Small (<\$2B).'),
  'P/E':        _FundExplain('Price-to-Earnings Ratio',
      'How much investors pay per \$1 of earnings. A P/E of 20 means you pay \$20 for every \$1 of profit. Lower P/E = cheaper relative to earnings. Compare to sector average.'),
  'P/S':        _FundExplain('Price-to-Sales Ratio',
      'Share price divided by revenue per share. Useful for companies with no earnings yet. Lower P/S = potentially undervalued relative to revenue.'),
  'EPS':        _FundExplain('Earnings Per Share (TTM)',
      'Net profit divided by shares outstanding, over the trailing twelve months. Growing EPS is a sign of a healthy, profitable business.'),
  'Net Margin': _FundExplain('Net Profit Margin',
      'Percentage of revenue that becomes profit after all expenses. A 15% margin means the company keeps \$0.15 from every \$1 sold. Higher is better.'),
  'ROE':        _FundExplain('Return on Equity',
      'How efficiently management uses shareholder money to generate profit. 15%+ is generally considered good. Buffett looks for >20% sustained ROE.'),
  'D/E':        _FundExplain('Debt-to-Equity Ratio',
      'Total debt divided by shareholder equity. A D/E of 1.0 means equal debt and equity. Higher D/E = more financial risk, but also common in capital-heavy industries.'),
  'Curr. Ratio':_FundExplain('Current Ratio',
      'Current assets divided by current liabilities. Measures ability to pay short-term debts. Above 1.5 is healthy; below 1.0 may signal liquidity risk.'),
};

class _FundamentalQuickStats extends StatelessWidget {
  final FundamentalData fundamentals;
  const _FundamentalQuickStats({required this.fundamentals});

  @override
  Widget build(BuildContext context) {
    final f = fundamentals;
    final items = <_FundItem>[];

    if (f.marketCap != null)    items.add(_FundItem('Mkt Cap', _fmtLarge(f.marketCap!)));
    // P/E: only show if positive (negative P/E is not meaningful)
    if (f.pe != null && f.pe! > 0) items.add(_FundItem('P/E', f.pe!.toStringAsFixed(1)));
    if (f.ps != null && f.ps! > 0) items.add(_FundItem('P/S', f.ps!.toStringAsFixed(1)));
    if (f.ttmEps != null)       items.add(_FundItem('EPS', '\$${f.ttmEps!.toStringAsFixed(2)}'));
    // netMargin / roe already stored as % from backend (e.g. 21.5 = 21.5%)
    if (f.netMargin != null)    items.add(_FundItem('Net Margin', '${f.netMargin!.toStringAsFixed(1)}%'));
    if (f.roe != null)          items.add(_FundItem('ROE', '${f.roe!.toStringAsFixed(1)}%'));
    if (f.debtEquity != null)   items.add(_FundItem('D/E', f.debtEquity!.toStringAsFixed(2)));
    if (f.currentRatio != null) items.add(_FundItem('Curr. Ratio', f.currentRatio!.toStringAsFixed(2)));

    if (items.isEmpty) return const SizedBox.shrink();

    final cellWidth = (MediaQuery.of(context).size.width - 68) / 4;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with info button
          Row(
            children: [
              const Text(
                'Fundamentals',
                style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _showInfoSheet(context, items),
                child: const Icon(Icons.info_outline, size: 14, color: Colors.white30),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 0,
            runSpacing: 0,
            children: items.map((item) => GestureDetector(
              onTap: () => _showSingleExplanation(context, item.label),
              child: SizedBox(
                width: cellWidth,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            item.label,
                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                          ),
                          const SizedBox(width: 2),
                          const Icon(Icons.info_outline, size: 9, color: Colors.white24),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  void _showSingleExplanation(BuildContext context, String label) {
    final entry = _kFundExplanations[label];
    if (entry == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111925),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.title,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(entry.body,
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
          ],
        ),
      ),
    );
  }

  void _showInfoSheet(BuildContext context, List<_FundItem> items) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111925),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            const Text(
              'Fundamental Metrics Explained',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap any metric below to learn more.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ...items.map((item) {
              final entry = _kFundExplanations[item.label];
              if (entry == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF12A28C).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(item.label,
                            style: const TextStyle(
                              color: Color(0xFF12A28C), fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 8),
                        Text(item.value,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(entry.title,
                      style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(entry.body,
                      style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.45)),
                    const Divider(color: Colors.white12, height: 20),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _fmtLarge(double v) {
    if (v >= 1e12) return '\$${(v / 1e12).toStringAsFixed(2)}T';
    if (v >= 1e9)  return '\$${(v / 1e9).toStringAsFixed(2)}B';
    if (v >= 1e6)  return '\$${(v / 1e6).toStringAsFixed(2)}M';
    return '\$${v.toStringAsFixed(0)}';
  }
}

class _FundItem {
  final String label;
  final String value;
  const _FundItem(this.label, this.value);
}

/// Minimal stats row shown for crypto assets (market cap + 24h volume).
class _CryptoQuickStats extends StatelessWidget {
  final MarketRange range;
  const _CryptoQuickStats({required this.range});

  String _fmtLarge(double v) {
    if (v >= 1e12) return '\$${(v / 1e12).toStringAsFixed(2)}T';
    if (v >= 1e9)  return '\$${(v / 1e9).toStringAsFixed(2)}B';
    if (v >= 1e6)  return '\$${(v / 1e6).toStringAsFixed(2)}M';
    return '\$${v.toStringAsFixed(0)}';
  }

  String _fmtVol(int v) {
    if (v >= 1000000000) return '${(v / 1e9).toStringAsFixed(2)}B';
    if (v >= 1000000)    return '${(v / 1e6).toStringAsFixed(2)}M';
    if (v >= 1000)       return '${(v / 1e3).toStringAsFixed(1)}K';
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final items = <_FundItem>[];
    if (range.marketCap != null) items.add(_FundItem('Mkt Cap', _fmtLarge(range.marketCap!)));
    if (range.volume != null)    items.add(_FundItem('24h Vol', _fmtVol(range.volume!)));

    if (items.isEmpty) return const SizedBox.shrink();

    final cellWidth = (MediaQuery.of(context).size.width - 68) / 4;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Market Stats',
            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 0,
            runSpacing: 0,
            children: items.map((item) => SizedBox(
              width: cellWidth,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      item.label,
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }
}

class _FundExplain {
  final String title;
  final String body;
  const _FundExplain(this.title, this.body);
}

// ── Pattern Card (Phase 6) ────────────────────────────────────────────────────

class _PatternCard extends StatelessWidget {
  final PatternScanResult patterns;
  const _PatternCard({required this.patterns});

  static const _patternEducation = <String, String>{
    'DOUBLE TOP':
        'Two peaks at roughly the same price — sellers rejected the same level twice. Usually signals a bearish reversal. Sell pressure often increases on the break below the trough between the two peaks (the "neckline").',
    'DOUBLE BOTTOM':
        'Two troughs at roughly the same price — buyers defended the same level twice. Usually signals a bullish reversal. Momentum often accelerates on the break above the peak between the two lows.',
    'HEAD SHOULDERS':
        'Three peaks where the middle peak is the highest. Left and right "shoulders" are at similar heights. A classic bearish reversal pattern. Break below the neckline (connecting the two troughs) is the signal.',
    'INV HEAD SHOULDERS':
        'Three troughs where the middle is the lowest — the inverse of Head & Shoulders. A classic bullish reversal pattern. Break above the neckline confirms the setup.',
    'ASCENDING TRIANGLE':
        'Flat resistance ceiling with a series of higher lows. Buyers are getting more aggressive each dip. Usually resolves as a bullish breakout through the flat top.',
    'DESCENDING TRIANGLE':
        'Flat support floor with a series of lower highs. Sellers are pushing harder on each rally. Usually resolves as a bearish breakdown through the flat bottom.',
    'SYMMETRICAL TRIANGLE':
        'Lower highs and higher lows converging toward a point. Neither buyers nor sellers dominate — a big move is being compressed. Direction of breakout determines the signal; wait for confirmation.',
    'BULL FLAG':
        'A strong upward move (the pole) followed by tight, sideways-to-down consolidation (the flag). Bulls rest before continuing. Breakout above the flag top with volume surge is the entry signal.',
    'BEAR FLAG':
        'A sharp downward move followed by a brief consolidation. Bears pause before resuming the trend. Breakdown below flag low confirms continuation.',
    'WEDGE RISING':
        'Price is rising but in a tightening channel with converging support and resistance. Despite upward movement, it often signals weakening momentum and a potential reversal downward.',
    'WEDGE FALLING':
        'Price is falling in a tightening channel. Despite downward movement, buyers are gradually stepping in at higher lows, often signalling a bullish reversal when price breaks above the upper trendline.',
  };

  @override
  Widget build(BuildContext context) {
    final p = patterns;
    final trendColor = p.trend == 'UPTREND'
        ? const Color(0xFF12A28C)
        : p.trend == 'DOWNTREND'
            ? Colors.redAccent
            : Colors.white54;

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.candlestick_chart_outlined, color: Colors.white54, size: 15),
              const SizedBox(width: 6),
              const Text(
                'Chart Patterns',
                style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              // Trend pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: trendColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: trendColor.withValues(alpha: 0.35)),
                ),
                child: Text(
                  '${p.trend.replaceAll('_', ' ')}  ${p.trendStrength}',
                  style: TextStyle(color: trendColor, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Detected patterns
          if (p.patterns.isEmpty)
            const Text(
              'No significant chart patterns detected on this timeframe.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            )
          else
            ...p.patterns.map((pat) => _PatternRow(
              pattern: pat,
              onTap: () => _showPatternExplanation(context, pat),
            )),

          // Support / Resistance levels
          if (p.supportResistance.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Key Levels',
              style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            ...p.supportResistance.take(4).map((sr) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Container(
                    width: 6, height: 6,
                    margin: const EdgeInsets.only(right: 8, top: 1),
                    decoration: BoxDecoration(
                      color: sr.type == 'SUPPORT'
                          ? const Color(0xFF12A28C)
                          : Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(
                    '\$${sr.price.toStringAsFixed(sr.price >= 100 ? 2 : 4)}',
                    style: TextStyle(
                      color: sr.type == 'SUPPORT'
                          ? const Color(0xFF12A28C)
                          : Colors.redAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    sr.type,
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${sr.strength}x touch',
                    style: const TextStyle(color: Colors.white24, fontSize: 10),
                  ),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }

  void _showPatternExplanation(BuildContext context, ChartPatternResult pat) {
    final key = pat.type.replaceAll('_', ' ');
    final explanation = _patternEducation[key] ?? pat.description;
    final signalColor = pat.signal == 'BULLISH'
        ? const Color(0xFF12A28C)
        : pat.signal == 'BEARISH'
            ? Colors.redAccent
            : Colors.white54;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111925),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  pat.displayName,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: signalColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: signalColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    pat.signal,
                    style: TextStyle(color: signalColor, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${(pat.confidence * 100).toStringAsFixed(0)}% confidence',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            if (pat.keyPrice != null) ...[
              const SizedBox(height: 4),
              Text(
                'Key level: \$${pat.keyPrice!.toStringAsFixed(pat.keyPrice! >= 100 ? 2 : 4)}',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              explanation,
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatternRow extends StatelessWidget {
  final ChartPatternResult pattern;
  final VoidCallback onTap;
  const _PatternRow({required this.pattern, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final signalColor = pattern.signal == 'BULLISH'
        ? const Color(0xFF12A28C)
        : pattern.signal == 'BEARISH'
            ? Colors.redAccent
            : Colors.white54;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: signalColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: signalColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            // Signal dot
            Container(
              width: 8, height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(color: signalColor, shape: BoxShape.circle),
            ),
            // Name + description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pattern.displayName,
                    style: TextStyle(
                      color: signalColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pattern.description,
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Confidence + info icon
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${(pattern.confidence * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: signalColor, fontSize: 11, fontWeight: FontWeight.w700),
                ),
                const Icon(Icons.info_outline, size: 12, color: Colors.white24),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
