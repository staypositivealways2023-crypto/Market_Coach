import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../../models/holding.dart';
import '../../providers/portfolio_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../services/backend_service.dart';
import '../../services/portfolio_service.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/paywall_bottom_sheet.dart';
import '../paper_trading/paper_trading_screen.dart';

class PortfolioScreen extends ConsumerStatefulWidget {
  const PortfolioScreen({super.key});

  @override
  ConsumerState<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends ConsumerState<PortfolioScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _backend = BackendService();

  // Live prices keyed by symbol
  Map<String, double> _prices = {};
  bool _pricesLoading = false;

  // Portfolio-level AI analysis from backend
  Map<String, dynamic>? _portfolioAnalysis;
  bool _analysisLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshPrices(List<Holding> holdings) async {
    if (holdings.isEmpty || _pricesLoading) return;
    setState(() => _pricesLoading = true);
    final symbols = holdings.map((h) => h.symbol).toList();
    final quotes = await _backend.getQuotes(symbols);
    final prices = <String, double>{};
    quotes.forEach((symbol, q) {
      final price = (q['price'] as num?)?.toDouble() ??
          (q['current_price'] as num?)?.toDouble();
      if (price != null) prices[symbol] = price;
    });
    if (mounted) setState(() { _prices = prices; _pricesLoading = false; });
  }

  Future<void> _fetchPortfolioAnalysis(List<Holding> holdings) async {
    if (holdings.isEmpty) return;
    setState(() => _analysisLoading = true);
    final result = await _backend.analysePortfolio(holdings);
    if (mounted) setState(() { _portfolioAnalysis = result; _analysisLoading = false; });
  }

  List<HoldingWithValue> _enrich(List<Holding> holdings) {
    return holdings
        .map((h) => HoldingWithValue(holding: h, currentPrice: _prices[h.symbol]))
        .toList();
  }

  void _showAddSheet({Holding? existing}) {
    final service = ref.read(portfolioServiceProvider);
    if (service == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111925),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddHoldingSheet(
        service: service,
        existing: existing,
        onSaved: () {
          final holdings = ref.read(portfolioHoldingsProvider).valueOrNull ?? [];
          _refreshPrices(holdings);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final holdingsAsync = ref.watch(portfolioHoldingsProvider);

    return holdingsAsync.when(
      loading: () => const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: Text('Error: $e', style: const TextStyle(color: Colors.white70))),
      ),
      data: (holdings) {
        // Refresh prices when holdings list changes
        WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPrices(holdings));

        final enriched = _enrich(holdings);
        final totalValue = enriched.fold<double>(
            0, (s, h) => s + (h.currentValue ?? h.totalCost));
        final totalCost = enriched.fold<double>(0, (s, h) => s + h.totalCost);
        final totalPnl = totalValue - totalCost;
        final totalPnlPct = totalCost > 0 ? (totalPnl / totalCost) * 100 : 0.0;
        final isPositive = totalPnl >= 0;

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Portfolio'),
            backgroundColor: Colors.transparent,
            actions: [
              if (holdings.isNotEmpty)
                Consumer(
                  builder: (context, ref, _) {
                    final sub = ref.watch(subscriptionProvider).valueOrNull;
                    return IconButton(
                      icon: const Icon(Icons.insights_outlined),
                      tooltip: 'AI Analysis',
                      onPressed: () {
                        if (sub != null && !sub.isPro) {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const PaywallBottomSheet(),
                          );
                          return;
                        }
                        _fetchPortfolioAnalysis(holdings);
                      },
                    );
                  },
                ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add position',
                onPressed: () => _showAddSheet(),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Theme.of(context).colorScheme.primary,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white38,
              tabs: const [
                Tab(icon: Icon(Icons.account_balance_wallet_outlined, size: 18), text: 'My Portfolio'),
                Tab(icon: Icon(Icons.currency_exchange, size: 18), text: 'Paper Trading'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              // ── Tab 1: Real Portfolio ────────────────────────────────────
              holdings.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: () => _refreshPrices(holdings),
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      // ── Summary Card ───────────────────────────────────────
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: _SummaryCard(
                            totalValue: totalValue,
                            totalPnl: totalPnl,
                            totalPnlPct: totalPnlPct.toDouble(),
                            isPositive: isPositive,
                            isLoading: _pricesLoading,
                          ),
                        ),
                      ),

                      // ── Allocation Pie Chart ───────────────────────────────
                      if (enriched.length >= 2)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: _AllocationChart(
                              holdings: enriched,
                              totalValue: totalValue,
                            ),
                          ),
                        ),

                      // ── AI Portfolio Analysis ──────────────────────────────
                      if (_analysisLoading)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: _AnalysisLoadingCard(),
                          ),
                        )
                      else if (_portfolioAnalysis != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: _PortfolioAnalysisCard(data: _portfolioAnalysis!),
                          ),
                        ),

                      // ── Holdings List ──────────────────────────────────────
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text(
                            'Holdings (${holdings.length})',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),

                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final h = enriched[i];
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: _HoldingCard(
                                holding: h,
                                totalValue: totalValue,
                                onEdit: () => _showAddSheet(existing: h.holding),
                                onDelete: () => _confirmDelete(h.holding),
                              ),
                            );
                          },
                          childCount: enriched.length,
                        ),
                      ),

                      const SliverToBoxAdapter(child: SizedBox(height: 40)),
                    ],
                  ),
                ),

              // ── Tab 2: Paper Trading ──────────────────────────────────────
              const PaperTradingScreen(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.pie_chart_outline, size: 72, color: Colors.white24),
          const SizedBox(height: 20),
          const Text(
            'No holdings yet',
            style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap + to add your first position',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Position'),
            onPressed: () => _showAddSheet(),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Holding h) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Remove ${h.symbol}?',
            style: const TextStyle(color: Colors.white)),
        content: const Text('This will delete this position permanently.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final service = ref.read(portfolioServiceProvider);
      await service?.remove(h.symbol);
    }
  }
}

// ── Summary Card ──────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final double totalValue;
  final double totalPnl;
  final double totalPnlPct;
  final bool isPositive;
  final bool isLoading;

  const _SummaryCard({
    required this.totalValue,
    required this.totalPnl,
    required this.totalPnlPct,
    required this.isPositive,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final green = const Color(0xFF12A28C);
    final red = Colors.redAccent;
    final pnlColor = isPositive ? green : red;
    final fmt = NumberFormat('#,##0.00');

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Total Value', style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 6),
          isLoading
              ? const SizedBox(height: 44, child: Center(child: LinearProgressIndicator()))
              : _PortfolioValueText(value: totalValue, fmt: fmt),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                  color: pnlColor, size: 16),
              const SizedBox(width: 4),
              Text(
                '\$${fmt.format(totalPnl.abs())}  (${totalPnlPct.abs().toStringAsFixed(2)}%)',
                style: TextStyle(color: pnlColor, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Text(
                isPositive ? 'total gain' : 'total loss',
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Hero portfolio value ──────────────────────────────────────────────────────

class _PortfolioValueText extends StatelessWidget {
  final double value;
  final NumberFormat fmt;
  const _PortfolioValueText({required this.value, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final formatted = '\$${fmt.format(value)}';
    final dotIndex = formatted.indexOf('.');
    final whole = dotIndex >= 0 ? formatted.substring(0, dotIndex) : formatted;
    final decimal = dotIndex >= 0 ? formatted.substring(dotIndex) : '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          whole,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
            height: 1.0,
          ),
        ),
        if (decimal.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              decimal,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 22,
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

// ── Allocation Pie Chart ──────────────────────────────────────────────────────

class _AllocationChart extends StatelessWidget {
  final List<HoldingWithValue> holdings;
  final double totalValue;

  const _AllocationChart({required this.holdings, required this.totalValue});

  static const _colors = [
    Color(0xFF12A28C), Color(0xFF2563EB), Color(0xFFE91E63),
    Color(0xFFFF9800), Color(0xFF9C27B0), Color(0xFF00BCD4),
    Color(0xFF4CAF50), Color(0xFFFF5722),
  ];

  @override
  Widget build(BuildContext context) {
    final data = holdings.map((h) {
      final val = h.currentValue ?? h.totalCost;
      return _PiePoint(h.symbol, val);
    }).toList();

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Allocation', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: SfCircularChart(
              margin: EdgeInsets.zero,
              series: <CircularSeries>[
                PieSeries<_PiePoint, String>(
                  dataSource: data,
                  xValueMapper: (p, _) => p.label,
                  yValueMapper: (p, _) => p.value,
                  pointColorMapper: (_, i) => _colors[i % _colors.length],
                  dataLabelSettings: const DataLabelSettings(
                    isVisible: true,
                    labelPosition: ChartDataLabelPosition.outside,
                    textStyle: TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                  dataLabelMapper: (p, _) {
                    final pct = totalValue > 0 ? (p.value / totalValue * 100) : 0;
                    return '${p.label}\n${pct.toStringAsFixed(1)}%';
                  },
                  explode: true,
                  explodeIndex: 0,
                  strokeWidth: 0,
                ),
              ],
            ),
          ),
          // Legend row
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: List.generate(holdings.length, (i) {
              final h = holdings[i];
              final pct = totalValue > 0
                  ? ((h.currentValue ?? h.totalCost) / totalValue * 100)
                  : 0.0;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: _colors[i % _colors.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${h.symbol} ${pct.toStringAsFixed(1)}%',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _PiePoint {
  final String label;
  final double value;
  _PiePoint(this.label, this.value);
}

// ── Portfolio AI Analysis Card ─────────────────────────────────────────────────

class _AnalysisLoadingCard extends StatelessWidget {
  const _AnalysisLoadingCard();
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          const Text('Analysing your portfolio…',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }
}

class _PortfolioAnalysisCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _PortfolioAnalysisCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final metrics = data['metrics'] as Map<String, dynamic>?;
    final rebalancing = data['rebalancing'] as List<dynamic>?;
    final insight = data['ai_insight'] as String?;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.auto_awesome, color: Theme.of(context).colorScheme.primary, size: 18),
            const SizedBox(width: 8),
            const Text('Portfolio Analysis',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 14),

          // Risk metrics
          if (metrics != null) ...[
            _MetricRow('Sharpe Ratio', _fmt(metrics['sharpe_ratio'])),
            _MetricRow('Sortino Ratio', _fmt(metrics['sortino_ratio'])),
            _MetricRow('Volatility (ann.)', '${_fmtPct(metrics['portfolio_volatility'])}%'),
            const SizedBox(height: 12),
          ],

          // Rebalancing tips
          if (rebalancing != null && rebalancing.isNotEmpty) ...[
            const Text('Rebalancing Suggestions',
                style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ...rebalancing.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(color: Color(0xFF12A28C), fontSize: 14)),
                  Expanded(
                    child: Text(r.toString(),
                        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 12),
          ],

          // AI narrative
          if (insight != null && insight.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(insight,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.55)),
            ),
        ],
      ),
    );
  }

  String _fmt(dynamic v) {
    if (v == null) return '—';
    return (v as num).toStringAsFixed(2);
  }

  String _fmtPct(dynamic v) {
    if (v == null) return '—';
    return ((v as num) * 100).toStringAsFixed(1);
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  const _MetricRow(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Holding Card ──────────────────────────────────────────────────────────────

class _HoldingCard extends StatelessWidget {
  final HoldingWithValue holding;
  final double totalValue;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _HoldingCard({
    required this.holding,
    required this.totalValue,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final green = const Color(0xFF12A28C);
    final red = Colors.redAccent;
    final pnlColor = holding.isPositive ? green : red;
    final fmt = NumberFormat('#,##0.00');
    final alloc = totalValue > 0
        ? ((holding.currentValue ?? holding.totalCost) / totalValue * 100)
        : 0.0;

    return GlassCard(
      onTap: onEdit,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              // Symbol + name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(holding.symbol,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    Text(holding.name,
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),

              // Current value + P&L
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    holding.currentValue != null
                        ? '\$${fmt.format(holding.currentValue!)}'
                        : '\$${fmt.format(holding.totalCost)}',
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  if (holding.pnl != null)
                    Text(
                      '${holding.isPositive ? '+' : ''}\$${fmt.format(holding.pnl!)} '
                      '(${holding.pnlPct!.toStringAsFixed(1)}%)',
                      style: TextStyle(color: pnlColor, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                ],
              ),

              // Delete
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.white24),
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 10),

          // Details row
          Row(
            children: [
              _Detail('Shares', holding.shares.toStringAsFixed(
                  holding.shares == holding.shares.floorToDouble() ? 0 : 4)),
              _Detail('Avg Cost', '\$${fmt.format(holding.avgCost)}'),
              if (holding.currentPrice != null)
                _Detail('Price', '\$${fmt.format(holding.currentPrice!)}'),
              _Detail('Allocation', '${alloc.toStringAsFixed(1)}%'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  final String label;
  final String value;
  const _Detail(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ── Add / Edit Holding Sheet ──────────────────────────────────────────────────

class _AddHoldingSheet extends StatefulWidget {
  final PortfolioService service;
  final Holding? existing;
  final VoidCallback onSaved;

  const _AddHoldingSheet({required this.service, this.existing, required this.onSaved});

  @override
  State<_AddHoldingSheet> createState() => _AddHoldingSheetState();
}

class _AddHoldingSheetState extends State<_AddHoldingSheet> {
  final _backend = BackendService();
  final _symbolCtrl = TextEditingController();
  final _sharesCtrl = TextEditingController();
  final _costCtrl = TextEditingController();

  // auto-detected from live quote
  String? _detectedName;
  double? _livePrice;
  bool _lookingUp = false;
  bool _lookupDone = false;
  String? _lookupError;

  bool _saving = false;
  String? _error;

  // debounce timer
  DateTime? _lastTyped;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _symbolCtrl.text = widget.existing!.symbol;
      _detectedName = widget.existing!.name;
      _sharesCtrl.text = widget.existing!.shares.toString();
      _costCtrl.text = widget.existing!.avgCost.toString();
      _lookupDone = true;
    }
  }

  @override
  void dispose() {
    _symbolCtrl.dispose();
    _sharesCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  void _onSymbolChanged(String val) {
    final trimmed = val.trim().toUpperCase();
    setState(() {
      _detectedName = null;
      _livePrice = null;
      _lookupDone = false;
      _lookupError = null;
    });
    if (trimmed.isEmpty) return;

    _lastTyped = DateTime.now();
    final capturedTime = _lastTyped;

    // 600ms debounce
    Future.delayed(const Duration(milliseconds: 600), () async {
      if (_lastTyped != capturedTime || !mounted) return;
      setState(() => _lookingUp = true);

      final quote = await _backend.getQuote(trimmed);

      if (!mounted) return;
      if (quote != null) {
        final price = (quote['price'] as num?)?.toDouble() ??
            (quote['current_price'] as num?)?.toDouble();
        final name = quote['name'] as String? ??
            quote['company_name'] as String? ??
            trimmed;
        setState(() {
          _detectedName = name;
          _livePrice = price;
          _lookingUp = false;
          _lookupDone = true;
          _lookupError = null;
          // auto-fill cost with live price if empty
          if (_costCtrl.text.isEmpty && price != null) {
            _costCtrl.text = price.toStringAsFixed(2);
          }
        });
      } else {
        setState(() {
          _lookingUp = false;
          _lookupDone = true;
          _lookupError = 'Symbol not found';
        });
      }
    });
  }

  Future<void> _save() async {
    final symbol = _symbolCtrl.text.trim().toUpperCase();
    final name = _detectedName ?? symbol;
    final shares = double.tryParse(_sharesCtrl.text.trim());
    final cost = double.tryParse(_costCtrl.text.trim());

    if (symbol.isEmpty || shares == null || shares <= 0 || cost == null || cost <= 0) {
      setState(() => _error = 'Enter a valid symbol, shares, and cost');
      return;
    }
    setState(() { _saving = true; _error = null; });
    await widget.service.upsert(Holding(
      symbol: symbol,
      name: name,
      shares: shares,
      avgCost: cost,
      addedAt: widget.existing?.addedAt ?? DateTime.now(),
    ));
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    const green = Color(0xFF12A28C);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20,
          MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // drag handle
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          Text(isEdit ? 'Edit Position' : 'Add Position',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),

          // ── Symbol field with live lookup ──────────────────────────────────
          TextField(
            controller: _symbolCtrl,
            enabled: !isEdit,
            autofocus: !isEdit,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700,
                letterSpacing: 1.5),
            onChanged: _onSymbolChanged,
            decoration: InputDecoration(
              labelText: 'Symbol — type AAPL, BTC, ETH…',
              labelStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              suffixIcon: _lookingUp
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38)))
                  : _lookupDone
                      ? Icon(_lookupError == null ? Icons.check_circle : Icons.cancel,
                          color: _lookupError == null ? green : Colors.redAccent, size: 22)
                      : null,
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: _lookupError != null
                          ? Colors.redAccent
                          : _lookupDone
                              ? green
                              : Colors.white24)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: green, width: 2)),
              disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white12)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
            ),
          ),

          // ── Auto-detected result card ──────────────────────────────────────
          if (_lookupDone && _lookupError == null && _detectedName != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: green.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.verified, color: Color(0xFF12A28C), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_detectedName!,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    if (_livePrice != null)
                      Text('Live price: \$${_livePrice!.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ]),
                ),
                if (_livePrice != null)
                  TextButton(
                    onPressed: () => setState(() => _costCtrl.text = _livePrice!.toStringAsFixed(2)),
                    style: TextButton.styleFrom(
                      foregroundColor: green,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    child: const Text('Use live price', style: TextStyle(fontSize: 12)),
                  ),
              ]),
            ),
          ],
          if (_lookupError != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
              const SizedBox(width: 6),
              Text(_lookupError!, style: const TextStyle(color: Colors.orange, fontSize: 12)),
            ]),
          ],

          const SizedBox(height: 14),

          // ── Shares ────────────────────────────────────────────────────────
          TextField(
            controller: _sharesCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Number of Shares',
              labelStyle: const TextStyle(color: Colors.white54),
              suffixText: _livePrice != null &&
                      (_sharesCtrl.text.isNotEmpty) &&
                      double.tryParse(_sharesCtrl.text) != null
                  ? '≈ \$${(double.parse(_sharesCtrl.text) * _livePrice!).toStringAsFixed(2)}'
                  : null,
              suffixStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: green, width: 2)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
            ),
          ),
          const SizedBox(height: 12),

          // ── Avg cost per share ─────────────────────────────────────────────
          TextField(
            controller: _costCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Avg Cost Per Share (\$)',
              labelStyle: const TextStyle(color: Colors.white54),
              prefixText: '\$ ',
              prefixStyle: const TextStyle(color: Colors.white54),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: green, width: 2)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                backgroundColor: green,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(isEdit ? 'Save Changes' : 'Add to Portfolio',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}


