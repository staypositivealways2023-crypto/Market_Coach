import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../../models/holding.dart';
import '../../models/paper_account.dart';
import '../../providers/paper_trading_provider.dart';
import '../../providers/portfolio_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../services/backend_service.dart';
import '../../services/paper_trading_service.dart';
import '../../services/portfolio_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/disclaimer_banner.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/guest_gate.dart';
import '../../widgets/paywall_bottom_sheet.dart';

class PortfolioScreen extends ConsumerStatefulWidget {
  const PortfolioScreen({super.key});

  @override
  ConsumerState<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends ConsumerState<PortfolioScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _backend = BackendService();

  // ── Real portfolio prices ─────────────────────────────────────────────────
  Map<String, double> _prices = {};
  bool _pricesLoading = false;

  // ── Paper portfolio prices ────────────────────────────────────────────────
  Map<String, double> _paperPrices = {};
  bool _paperPricesLoading = false;

  // ── Portfolio-level AI analysis ───────────────────────────────────────────
  Map<String, dynamic>? _portfolioAnalysis;
  bool _analysisLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Fetch prices once on mount in case providers are already in data state
    // (ref.listen only fires on changes, not on initial cached data).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final holdings = ref.read(portfolioHoldingsProvider).valueOrNull ?? [];
      if (holdings.isNotEmpty && _prices.isEmpty) _refreshPrices(holdings);
      final paper = ref.read(paperHoldingsProvider).valueOrNull ?? [];
      if (paper.isNotEmpty && _paperPrices.isEmpty) _refreshPaperPrices(paper);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Real portfolio: fetch prices for holdings ─────────────────────────────

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

  // ── Paper portfolio: fetch live prices for holdings ───────────────────────
  //
  // Called automatically via ref.listen when paperHoldingsProvider changes.
  // Works for both stocks (AAPL, BHP) and crypto (BTC, ETH) — BackendService
  // routes to the appropriate data source (Polygon / Binance / yfinance).

  Future<void> _refreshPaperPrices(List<PaperHolding> holdings) async {
    if (holdings.isEmpty || _paperPricesLoading) return;
    setState(() => _paperPricesLoading = true);
    final symbols = holdings.map((h) => h.symbol).toList();
    final quotes = await _backend.getQuotes(symbols);
    final prices = <String, double>{};
    quotes.forEach((symbol, q) {
      final price = (q['price'] as num?)?.toDouble() ??
          (q['current_price'] as num?)?.toDouble();
      if (price != null) prices[symbol] = price;
    });
    if (mounted) setState(() { _paperPrices = prices; _paperPricesLoading = false; });
  }

  Future<void> _fetchPortfolioAnalysis(List<Holding> holdings) async {
    if (holdings.isEmpty) return;
    setState(() => _analysisLoading = true);
    final result = await _backend.analysePortfolio(holdings);
    if (!mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Analysis unavailable — check your connection and try again.'),
          duration: Duration(seconds: 4),
        ),
      );
    }
    setState(() { _portfolioAnalysis = result; _analysisLoading = false; });
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

  void _showSellSheet(HoldingWithValue holding) {
    final service = ref.read(portfolioServiceProvider);
    if (service == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SellHoldingSheet(
        holding: holding,
        service: service,
        onSold: () {
          final holdings = ref.read(portfolioHoldingsProvider).valueOrNull ?? [];
          _refreshPrices(holdings);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Gate the entire Portfolio screen for guest users.
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null || currentUser.isAnonymous) {
      return GuestGateScreen(
        feature: 'Portfolio',
        message: 'Create a free account to track your investments, '
            'monitor P&L, and practise paper trading.',
        child: const SizedBox.shrink(),
      );
    }

    final holdingsAsync = ref.watch(portfolioHoldingsProvider);

    // Real portfolio: fetch prices whenever holdings change.
    ref.listen<AsyncValue<List<Holding>>>(portfolioHoldingsProvider, (_, next) {
      next.whenData(_refreshPrices);
    });

    // Paper portfolio: fetch live prices whenever paper holdings change.
    // This is the fix for P&L showing $0 — prices are fetched reactively
    // as soon as Firestore emits the holdings snapshot.
    ref.listen<AsyncValue<List<PaperHolding>>>(paperHoldingsProvider, (_, next) {
      next.whenData(_refreshPaperPrices);
    });

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
          body: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: DisclaimerBanner(),
              ),
              Expanded(
                child: TabBarView(
            controller: _tabController,
            children: [
              // ── Tab 1: Real Portfolio ──────────────────────────────────────
              holdings.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: () => _refreshPrices(holdings),
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
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
                      if (enriched.length >= 2)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: _AllocationChart(holdings: enriched, totalValue: totalValue),
                          ),
                        ),
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
                          (context, i) => Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: _HoldingCard(
                              holding: enriched[i],
                              totalValue: totalValue,
                              onEdit: () => _showAddSheet(existing: enriched[i].holding),
                              onDelete: () => _confirmDelete(enriched[i].holding),
                              onSell: () => _showSellSheet(enriched[i]),
                            ),
                          ),
                          childCount: enriched.length,
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 40)),
                    ],
                  ),
                ),

              // ── Tab 2: Paper Trading ───────────────────────────────────────
              // Prices are fetched by _refreshPaperPrices (triggered via ref.listen
              // above) and passed down so P&L is always live.
              _PaperTab(
                paperPrices: _paperPrices,
                pricesLoading: _paperPricesLoading,
                onRefresh: () {
                  final holdings = ref.read(paperHoldingsProvider).valueOrNull ?? [];
                  _refreshPaperPrices(holdings);
                },
              ),
            ],
          ),
                ), // Expanded
              ], // Column
            ), // body Column
        );
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.pie_chart_outline, size: 72, color: Colors.white24),
          const SizedBox(height: 20),
          const Text('No holdings yet',
              style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Tap + to add your first position',
              style: TextStyle(color: Colors.white38, fontSize: 14)),
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

// ═══════════════════════════════════════════════════════════════════════════════
// PAPER TRADING TAB
// ═══════════════════════════════════════════════════════════════════════════════

/// Paper portfolio view — shows live P&L for all paper holdings.
///
/// Prices are fetched by the parent [_PortfolioScreenState] via
/// [_refreshPaperPrices] and passed as [paperPrices].  This avoids the
/// addPostFrameCallback loop that caused P&L to show $0 on initial load.
class _PaperTab extends ConsumerWidget {
  final Map<String, double> paperPrices;
  final bool pricesLoading;
  final VoidCallback onRefresh;

  const _PaperTab({
    required this.paperPrices,
    required this.pricesLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(paperAccountProvider);
    final holdingsAsync = ref.watch(paperHoldingsProvider);

    return accountAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: Colors.white70))),
      data: (account) {
        if (account == null || !account.isActive) {
          return _PaperActivationView(
            onActivate: () async {
              final svc = ref.read(paperTradingServiceProvider);
              await svc?.activate();
            },
          );
        }

        return holdingsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
              child: Text('Error: $e', style: const TextStyle(color: Colors.white70))),
          data: (holdings) {
            // Enrich holdings with live prices passed from parent.
            final enriched = holdings
                .map((h) => PaperHoldingWithValue(
                      holding: h,
                      currentPrice: paperPrices[h.symbol],
                    ))
                .toList();

            // Portfolio totals using live prices where available.
            final holdingsValue = enriched.fold<double>(
                0, (s, h) => s + (h.currentValue ?? h.totalCost));
            final totalValue = account.cashBalance + holdingsValue;
            final totalPnl = totalValue - PaperAccount.startingBalance;
            final isPositive = totalPnl >= 0;

            if (holdings.isEmpty) {
              return _PaperEmptyView(
                cashBalance: account.cashBalance,
                onRefresh: onRefresh,
              );
            }

            return RefreshIndicator(
              onRefresh: () async => onRefresh(),
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // ── Summary ──────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _PaperSummaryCard(
                        totalValue: totalValue,
                        cashBalance: account.cashBalance,
                        holdingsValue: holdingsValue,
                        totalPnl: totalPnl,
                        isPositive: isPositive,
                        isLoading: pricesLoading,
                      ),
                    ),
                  ),

                  // ── Holdings header ───────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          Text(
                            'Positions (${enriched.length})',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const Spacer(),
                          if (pricesLoading)
                            const SizedBox(
                              width: 12, height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.5),
                            )
                          else
                            GestureDetector(
                              onTap: onRefresh,
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.refresh, size: 14, color: Colors.white38),
                                  SizedBox(width: 4),
                                  Text('Refresh prices',
                                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // ── Holdings list ─────────────────────────────────────────
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final svc = ref.read(paperTradingServiceProvider);
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: _PaperHoldingCard(
                            holding: enriched[i],
                            onSell: svc == null ? null : () => _showPaperSellSheet(
                              context, enriched[i], svc, onRefresh),
                          ),
                        );
                      },
                      childCount: enriched.length,
                    ),
                  ),

                  // ── Cash row ──────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: _CashBalanceRow(cashBalance: account.cashBalance),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Paper Summary Card ─────────────────────────────────────────────────────────

class _PaperSummaryCard extends StatelessWidget {
  final double totalValue;
  final double cashBalance;
  final double holdingsValue;
  final double totalPnl;
  final bool isPositive;
  final bool isLoading;

  const _PaperSummaryCard({
    required this.totalValue,
    required this.cashBalance,
    required this.holdingsValue,
    required this.totalPnl,
    required this.isPositive,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF12A28C);
    final pnlColor = isPositive ? green : Colors.redAccent;
    final fmt = NumberFormat('#,##0.00');
    final pnlPct = (totalPnl.abs() / PaperAccount.startingBalance) * 100;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.currency_exchange, size: 15, color: Colors.white38),
            const SizedBox(width: 6),
            const Text('Paper Account',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Virtual \$1M',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ),
          ]),
          const SizedBox(height: 8),

          // Total value
          isLoading
              ? const SizedBox(height: 44, child: Center(child: LinearProgressIndicator()))
              : Text(
                  '\$${fmt.format(totalValue)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.2,
                    height: 1.0,
                  ),
                ),

          const SizedBox(height: 8),

          // P&L vs $1M start
          Row(children: [
            Icon(isPositive ? Icons.trending_up : Icons.trending_down,
                color: pnlColor, size: 16),
            const SizedBox(width: 4),
            Text(
              '${isPositive ? '+' : '-'}\$${fmt.format(totalPnl.abs())}  '
              '(${pnlPct.toStringAsFixed(2)}%)',
              style: TextStyle(
                  color: pnlColor, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            const Text('vs \$1M start',
                style: TextStyle(color: Colors.white30, fontSize: 12)),
          ]),

          const SizedBox(height: 14),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 14),

          // Cash / Holdings breakdown
          Row(children: [
            Expanded(
              child: _StatCol(
                label: 'Cash',
                value: '\$${_compact(cashBalance)}',
                color: Colors.white70,
              ),
            ),
            Expanded(
              child: _StatCol(
                label: 'Holdings',
                value: '\$${_compact(holdingsValue)}',
                color: Colors.white70,
              ),
            ),
            Expanded(
              child: _StatCol(
                label: 'Return',
                value: '${isPositive ? '+' : ''}${(totalPnl / PaperAccount.startingBalance * 100).toStringAsFixed(2)}%',
                color: pnlColor,
              ),
            ),
          ]),
        ],
      ),
    );
  }

  static String _compact(double v) {
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(2)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
    return NumberFormat('#,##0.00').format(v);
  }
}

class _StatCol extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCol({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ── Paper Holding Card ─────────────────────────────────────────────────────────

class _PaperHoldingCard extends StatelessWidget {
  final PaperHoldingWithValue holding;
  final VoidCallback? onSell;
  const _PaperHoldingCard({required this.holding, this.onSell});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF12A28C);
    final pnlColor = holding.isPositive ? green : Colors.redAccent;
    final fmt = NumberFormat('#,##0.00');
    final hasPnl = holding.unrealizedPnl != null;

    return GlassCard(
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
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    Text(holding.name,
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
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
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                  if (hasPnl)
                    Text(
                      '${holding.isPositive ? '+' : ''}\$${fmt.format(holding.unrealizedPnl!.abs())} '
                      '(${holding.unrealizedPnlPct!.toStringAsFixed(1)}%)',
                      style: TextStyle(
                          color: pnlColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    )
                  else
                    const Text('Fetching price…',
                        style: TextStyle(color: Colors.white30, fontSize: 12)),
                ],
              ),
            ],
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 10),

          // Details row
          Row(
            children: [
              _Detail('Shares',
                  holding.shares % 1 == 0
                      ? holding.shares.toInt().toString()
                      : holding.shares.toStringAsFixed(4)),
              _Detail('Avg Cost', '\$${fmt.format(holding.avgCost)}'),
              if (holding.currentPrice != null)
                _Detail('Price', '\$${fmt.format(holding.currentPrice!)}'),
              _Detail('Cost Basis', '\$${fmt.format(holding.totalCost)}'),
            ],
          ),

          // Tax indicator
          if (holding.holdingDays != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Icon(Icons.timer_outlined, size: 12, color: Colors.white30),
                const SizedBox(width: 4),
                Text(
                  '${holding.holdingDays}d held · '
                  '${holding.isShortTerm ? '22% short-term' : '15% long-term'} gains',
                  style: const TextStyle(color: Colors.white30, fontSize: 11),
                ),
              ]),
            ),

          // Sell button
          if (onSell != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onSell,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFDC2626), Color(0xFFB91C1C)]),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x33DC2626), blurRadius: 8, offset: Offset(0, 2))
                  ],
                ),
                alignment: Alignment.center,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sell_outlined, size: 13, color: Colors.white),
                    SizedBox(width: 6),
                    Text('Sell Position',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Paper sell helper (called from _PaperTab) ─────────────────────────────────

void _showPaperSellSheet(
  BuildContext context,
  PaperHoldingWithValue holding,
  PaperTradingService svc,
  VoidCallback onRefresh,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PaperSellSheet(
      holding: holding,
      service: svc,
      onSold: onRefresh,
    ),
  );
}

class _PaperSellSheet extends StatefulWidget {
  final PaperHoldingWithValue holding;
  final PaperTradingService service;
  final VoidCallback onSold;
  const _PaperSellSheet(
      {required this.holding, required this.service, required this.onSold});

  @override
  State<_PaperSellSheet> createState() => _PaperSellSheetState();
}

class _PaperSellSheetState extends State<_PaperSellSheet> {
  late double _sharesToSell;
  bool _selling = false;

  @override
  void initState() {
    super.initState();
    _sharesToSell = widget.holding.shares;
  }

  double get _currentPrice =>
      widget.holding.currentPrice ?? widget.holding.avgCost;
  double get _proceeds => _sharesToSell * _currentPrice;
  double get _grossPnl =>
      _sharesToSell * (_currentPrice - widget.holding.avgCost);
  bool get _isFullSell =>
      (_sharesToSell - widget.holding.shares).abs() < 0.0001;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    const red = Color(0xFFEF4444);
    final pnlColor = _grossPnl >= 0 ? const Color(0xFF22C55E) : red;
    final maxShares = widget.holding.shares;
    final isWhole = maxShares == maxShares.floorToDouble();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1520),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0xFF1A2535), width: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: red.withValues(alpha: 0.3)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.sell_outlined, size: 14, color: Color(0xFFEF4444)),
                  SizedBox(width: 6),
                  Text('Sell', style: TextStyle(
                      color: Color(0xFFEF4444), fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
              ),
              const SizedBox(width: 12),
              Text(widget.holding.symbol,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22)),
              const SizedBox(width: 8),
              const Text('Paper Trade',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(children: [
                _SellStat('You hold',
                    '${isWhole ? maxShares.toInt() : maxShares.toStringAsFixed(4)} sh'),
                _SellStat('Avg Cost', '\$${fmt.format(widget.holding.avgCost)}'),
                if (widget.holding.currentPrice != null)
                  _SellStat('Price', '\$${fmt.format(widget.holding.currentPrice!)}'),
              ]),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Text('Shares to sell',
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                isWhole ? _sharesToSell.toInt().toString()
                    : _sharesToSell.toStringAsFixed(4),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ]),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: red, thumbColor: red,
                inactiveTrackColor: Colors.white12,
                overlayColor: red.withValues(alpha: 0.15),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              ),
              child: Slider(
                value: _sharesToSell.clamp(0.0, maxShares),
                min: 0, max: maxShares,
                divisions: isWhole ? maxShares.toInt().clamp(1, 200) : 100,
                onChanged: (v) => setState(() => _sharesToSell = v == 0 ? 0.0001 : v),
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              TextButton(onPressed: () => setState(() => _sharesToSell = maxShares * 0.25),
                  child: const Text('25%', style: TextStyle(fontSize: 12))),
              TextButton(onPressed: () => setState(() => _sharesToSell = maxShares * 0.5),
                  child: const Text('50%', style: TextStyle(fontSize: 12))),
              TextButton(onPressed: () => setState(() => _sharesToSell = maxShares * 0.75),
                  child: const Text('75%', style: TextStyle(fontSize: 12))),
              TextButton(onPressed: () => setState(() => _sharesToSell = maxShares),
                  child: const Text('All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(children: [
                _SellStat('Proceeds', '\$${fmt.format(_proceeds)}'),
                _SellStat('Gross P&L',
                    '${_grossPnl >= 0 ? '+' : ''}\$${fmt.format(_grossPnl)}',
                    color: pnlColor),
              ]),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: _selling || _sharesToSell <= 0 ? null : _confirmSell,
                style: ElevatedButton.styleFrom(
                  backgroundColor: red, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _selling
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(
                        _isFullSell ? 'Close Position' :
                            'Sell ${isWhole ? _sharesToSell.toInt() : _sharesToSell.toStringAsFixed(4)} Shares',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text('Virtual trade — no real money involved',
                  style: TextStyle(color: Colors.white30, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSell() async {
    setState(() => _selling = true);
    final price = widget.holding.currentPrice;
    if (price == null) {
      setState(() => _selling = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No live price available. Refresh and try again.'),
              backgroundColor: Colors.redAccent),
        );
      }
      return;
    }
    final err = await widget.service.sell(
        widget.holding.symbol, widget.holding.name, _sharesToSell, price);
    if (mounted) {
      Navigator.pop(context);
      widget.onSold();
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: Colors.redAccent));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Sold ${_sharesToSell.toStringAsFixed(2)} ${widget.holding.symbol}'),
          backgroundColor: const Color(0xFF1E293B),
        ));
      }
    }
  }
}

// ── Cash Balance Row ──────────────────────────────────────────────────────────

class _CashBalanceRow extends StatelessWidget {
  final double cashBalance;
  const _CashBalanceRow({required this.cashBalance});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        const Icon(Icons.account_balance_wallet_outlined,
            size: 16, color: Colors.white38),
        const SizedBox(width: 8),
        const Text('Cash available',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
        const Spacer(),
        Text('\$${fmt.format(cashBalance)}',
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ── Paper Empty / Activation ──────────────────────────────────────────────────

class _PaperEmptyView extends StatelessWidget {
  final double cashBalance;
  final VoidCallback onRefresh;
  const _PaperEmptyView({required this.cashBalance, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    final primary = Theme.of(context).colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.currency_exchange, size: 36, color: primary),
            ),
            const SizedBox(height: 24),
            const Text('No paper positions',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Cash available: \$${fmt.format(cashBalance)}',
              style: TextStyle(color: primary, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'Open any stock or crypto and tap Trade to open a position.',
              style: TextStyle(color: Colors.white38, fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PaperActivationView extends StatefulWidget {
  final Future<void> Function() onActivate;
  const _PaperActivationView({required this.onActivate});

  @override
  State<_PaperActivationView> createState() => _PaperActivationViewState();
}

class _PaperActivationViewState extends State<_PaperActivationView> {
  bool _activating = false;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90, height: 90,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.currency_exchange, size: 44, color: primary),
            ),
            const SizedBox(height: 28),
            const Text('Paper Trading',
                style: TextStyle(
                    color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            const Text(
              'Practice with \$1,000,000 in virtual cash.\nNo real money involved.',
              style: TextStyle(color: Colors.white54, fontSize: 15, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _activating
                    ? null
                    : () async {
                        setState(() => _activating = true);
                        await widget.onActivate();
                      },
                child: _activating
                    ? const SizedBox(
                        height: 22, width: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Activate Paper Trading',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// REAL PORTFOLIO WIDGETS (unchanged)
// ═══════════════════════════════════════════════════════════════════════════════

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
    const green = Color(0xFF12A28C);
    final pnlColor = isPositive ? green : Colors.redAccent;
    final fmt = NumberFormat('#,##0.00');

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Total Value',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 6),
          isLoading
              ? const SizedBox(
                  height: 44,
                  child: Center(child: LinearProgressIndicator()))
              : _PortfolioValueText(value: totalValue, fmt: fmt),
          const SizedBox(height: 12),
          Row(children: [
            Icon(isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                color: pnlColor, size: 16),
            const SizedBox(width: 4),
            Text(
              '\$${fmt.format(totalPnl.abs())}  (${totalPnlPct.abs().toStringAsFixed(2)}%)',
              style: TextStyle(
                  color: pnlColor, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Text(
              isPositive ? 'total gain' : 'total loss',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ]),
        ],
      ),
    );
  }
}

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
        Text(whole,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
              height: 1.0,
            )),
        if (decimal.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(decimal,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 22,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.5,
                  height: 1.0,
                )),
          ),
      ],
    );
  }
}

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
          const Text('Allocation',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
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
                    textStyle:
                        TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                  dataLabelMapper: (p, _) {
                    final pct = totalValue > 0
                        ? (p.value / totalValue * 100)
                        : 0;
                    return '${p.label}\n${pct.toStringAsFixed(1)}%';
                  },
                  explode: true,
                  explodeIndex: 0,
                  strokeWidth: 0,
                ),
              ],
            ),
          ),
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
                  Text('${h.symbol} ${pct.toStringAsFixed(1)}%',
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 11)),
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

class _AnalysisLoadingCard extends StatelessWidget {
  const _AnalysisLoadingCard();
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        const Text('Analysing your portfolio…',
            style: TextStyle(color: Colors.white70, fontSize: 14)),
      ]),
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
            Icon(Icons.auto_awesome,
                color: Theme.of(context).colorScheme.primary, size: 18),
            const SizedBox(width: 8),
            const Text('Portfolio Analysis',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 14),
          if (metrics != null) ...[
            _MetricRow('Sharpe Ratio', _fmt(metrics['sharpe_ratio'])),
            _MetricRow('Sortino Ratio', _fmt(metrics['sortino_ratio'])),
            _MetricRow('Volatility (ann.)',
                '${_fmtPct(metrics['portfolio_volatility'])}%'),
            const SizedBox(height: 12),
          ],
          if (rebalancing != null && rebalancing.isNotEmpty) ...[
            const Text('Rebalancing Suggestions',
                style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ...rebalancing.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ',
                      style: TextStyle(color: Color(0xFF12A28C), fontSize: 14)),
                  Expanded(
                    child: Text(r.toString(),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13, height: 1.4)),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 12),
          ],
          if (insight != null && insight.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(insight,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13, height: 1.55)),
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
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _HoldingCard extends StatelessWidget {
  final HoldingWithValue holding;
  final double totalValue;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSell;

  const _HoldingCard({
    required this.holding,
    required this.totalValue,
    required this.onEdit,
    required this.onDelete,
    required this.onSell,
  });

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF12A28C);
    final pnlColor = holding.isPositive ? green : Colors.redAccent;
    final fmt = NumberFormat('#,##0.00');
    final alloc = totalValue > 0
        ? ((holding.currentValue ?? holding.totalCost) / totalValue * 100)
        : 0.0;

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(holding.symbol,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  Text(holding.name,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  holding.currentValue != null
                      ? '\$${fmt.format(holding.currentValue!)}'
                      : '\$${fmt.format(holding.totalCost)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                ),
                if (holding.pnl != null)
                  Text(
                    '${holding.isPositive ? '+' : ''}\$${fmt.format(holding.pnl!)} '
                    '(${holding.pnlPct!.toStringAsFixed(1)}%)',
                    style: TextStyle(
                        color: pnlColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
              ],
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.more_vert, size: 18, color: Colors.white38),
              onPressed: () => _showActions(context),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 10),
          Row(children: [
            _Detail('Shares',
                holding.shares.toStringAsFixed(
                    holding.shares == holding.shares.floorToDouble() ? 0 : 4)),
            _Detail('Avg Cost', '\$${fmt.format(holding.avgCost)}'),
            if (holding.currentPrice != null)
              _Detail('Price', '\$${fmt.format(holding.currentPrice!)}'),
            _Detail('Alloc.', '${alloc.toStringAsFixed(1)}%'),
          ]),
          const SizedBox(height: 12),
          // Action buttons row
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: onEdit,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_outlined, size: 13, color: Colors.white54),
                      SizedBox(width: 5),
                      Text('Edit',
                          style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: onSell,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFDC2626), Color(0xFFB91C1C)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x33DC2626),
                          blurRadius: 8,
                          offset: Offset(0, 2)),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sell_outlined, size: 13, color: Colors.white),
                      SizedBox(width: 5),
                      Text('Sell',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111925),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: Colors.white70),
                title: const Text('Edit position',
                    style: TextStyle(color: Colors.white)),
                onTap: () { Navigator.pop(context); onEdit(); },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Remove position',
                    style: TextStyle(color: Colors.redAccent)),
                onTap: () { Navigator.pop(context); onDelete(); },
              ),
            ],
          ),
        ),
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
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ── Sell Holding Sheet ────────────────────────────────────────────────────────

class _SellHoldingSheet extends StatefulWidget {
  final HoldingWithValue holding;
  final PortfolioService service;
  final VoidCallback onSold;

  const _SellHoldingSheet({
    required this.holding,
    required this.service,
    required this.onSold,
  });

  @override
  State<_SellHoldingSheet> createState() => _SellHoldingSheetState();
}

class _SellHoldingSheetState extends State<_SellHoldingSheet> {
  late double _sharesToSell;
  bool _selling = false;

  @override
  void initState() {
    super.initState();
    _sharesToSell = widget.holding.shares; // default: sell all
  }

  double get _proceeds =>
      _sharesToSell * (widget.holding.currentPrice ?? widget.holding.avgCost);

  double get _realisedPnl =>
      _sharesToSell * ((widget.holding.currentPrice ?? widget.holding.avgCost) -
          widget.holding.avgCost);

  bool get _isFullSell =>
      (_sharesToSell - widget.holding.shares).abs() < 0.0001;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    const red = Color(0xFFEF4444);
    const green = Color(0xFF22C55E);
    final pnlColor = _realisedPnl >= 0 ? green : red;
    final maxShares = widget.holding.shares;
    final isWhole = maxShares == maxShares.floorToDouble();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1520),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0xFF1A2535), width: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: red.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.sell_outlined, size: 14, color: Color(0xFFEF4444)),
                const SizedBox(width: 6),
                const Text('Sell', style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
            ),
            const SizedBox(width: 12),
            Text(widget.holding.symbol,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(widget.holding.name,
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),

          const SizedBox(height: 20),

          // Position summary
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(children: [
              _SellStat('You hold', '${isWhole ? maxShares.toInt() : maxShares.toStringAsFixed(4)} shares'),
              _SellStat('Avg Cost', '\$${fmt.format(widget.holding.avgCost)}'),
              if (widget.holding.currentPrice != null)
                _SellStat('Current', '\$${fmt.format(widget.holding.currentPrice!)}'),
            ]),
          ),

          const SizedBox(height: 20),

          // Shares to sell
          Row(children: [
            const Text('Shares to sell',
                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(
              isWhole
                  ? _sharesToSell.toInt().toString()
                  : _sharesToSell.toStringAsFixed(4),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ]),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: red,
              thumbColor: red,
              inactiveTrackColor: Colors.white12,
              overlayColor: red.withValues(alpha: 0.15),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: _sharesToSell.clamp(0.0, maxShares),
              min: 0,
              max: maxShares,
              divisions: isWhole ? maxShares.toInt().clamp(1, 200) : 100,
              onChanged: (v) => setState(() => _sharesToSell = v == 0 ? 0.0001 : v),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => setState(() => _sharesToSell = maxShares * 0.25),
                child: const Text('25%', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: () => setState(() => _sharesToSell = maxShares * 0.50),
                child: const Text('50%', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: () => setState(() => _sharesToSell = maxShares * 0.75),
                child: const Text('75%', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: () => setState(() => _sharesToSell = maxShares),
                child: const Text('All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Proceeds preview
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(children: [
              _SellStat('Proceeds', '\$${fmt.format(_proceeds)}'),
              _SellStat(
                'Realised P&L',
                '${_realisedPnl >= 0 ? '+' : ''}\$${fmt.format(_realisedPnl)}',
                color: pnlColor,
              ),
              if (!_isFullSell)
                _SellStat(
                  'Remaining',
                  '${isWhole ? (maxShares - _sharesToSell).toInt() : (maxShares - _sharesToSell).toStringAsFixed(4)} shs',
                ),
            ]),
          ),

          const SizedBox(height: 20),

          // Confirm button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _selling || _sharesToSell <= 0 ? null : _confirmSell,
              style: ElevatedButton.styleFrom(
                backgroundColor: red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _selling
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(
                      _isFullSell
                          ? 'Sell All — Close Position'
                          : 'Sell ${isWhole ? _sharesToSell.toInt() : _sharesToSell.toStringAsFixed(4)} Shares',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
            ),
          ),

          const SizedBox(height: 8),
          const Center(
            child: Text('⚠️ For tracking only. Not a real trade.',
                style: TextStyle(color: Colors.white30, fontSize: 11)),
          ),
        ],
      ),
    ),
  );
  }

  Future<void> _confirmSell() async {
    setState(() => _selling = true);
    try {
      await widget.service.sell(widget.holding.symbol, _sharesToSell);
      if (mounted) {
        Navigator.pop(context);
        widget.onSold();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sold ${_sharesToSell.toStringAsFixed(2)} ${widget.holding.symbol}',
            ),
            backgroundColor: const Color(0xFF1E293B),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _selling = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
}

class _SellStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _SellStat(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  color: color ?? Colors.white70,
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
              overflow: TextOverflow.ellipsis),
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

  const _AddHoldingSheet(
      {required this.service, this.existing, required this.onSaved});

  @override
  State<_AddHoldingSheet> createState() => _AddHoldingSheetState();
}

class _AddHoldingSheetState extends State<_AddHoldingSheet> {
  final _backend = BackendService();
  final _symbolCtrl = TextEditingController();
  final _sharesCtrl = TextEditingController();
  final _costCtrl = TextEditingController();

  String? _detectedName;
  double? _livePrice;
  bool _lookingUp = false;
  bool _lookupDone = false;
  String? _lookupError;
  bool _saving = false;
  String? _error;
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

    if (symbol.isEmpty || shares == null || shares <= 0 ||
        cost == null || cost <= 0) {
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
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Text(isEdit ? 'Edit Position' : 'Add Position',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),

          // Symbol field
          TextField(
            controller: _symbolCtrl,
            textCapitalization: TextCapitalization.characters,
            onChanged: _onSymbolChanged,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Symbol (e.g. AAPL, BTC)',
              labelStyle: const TextStyle(color: Colors.white38),
              suffixIcon: _lookingUp
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : _lookupDone && _lookupError == null
                      ? const Icon(Icons.check_circle_outline,
                          color: green, size: 20)
                      : null,
              border: const OutlineInputBorder(),
              enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: green)),
            ),
            readOnly: isEdit,
          ),
          if (_lookupError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_lookupError!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
          if (_detectedName != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_detectedName!,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),

          const SizedBox(height: 12),

          // Shares + cost
          Row(children: [
            Expanded(
              child: TextField(
                controller: _sharesCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Shares',
                  labelStyle: TextStyle(color: Colors.white38),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: green)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _costCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Avg Cost (\$)',
                  labelStyle: TextStyle(color: Colors.white38),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: green)),
                ),
              ),
            ),
          ]),

          if (_livePrice != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Current price: \$${NumberFormat('#,##0.00').format(_livePrice)}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 13)),
            ),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: green,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(isEdit ? 'Save Changes' : 'Add to Portfolio',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
