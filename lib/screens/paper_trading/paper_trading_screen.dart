import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/paper_account.dart';
import '../../providers/paper_trading_provider.dart';
import '../../services/backend_service.dart';
import '../../widgets/disclaimer_banner.dart';
import '../../widgets/glass_card.dart';

class PaperTradingScreen extends ConsumerStatefulWidget {
  const PaperTradingScreen({super.key});

  @override
  ConsumerState<PaperTradingScreen> createState() => _PaperTradingScreenState();
}

class _PaperTradingScreenState extends ConsumerState<PaperTradingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _backend = BackendService();
  Map<String, double> _prices = {};
  DateTime? _lastRefreshed;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    // Refresh prices every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final holdings = ref.read(paperHoldingsProvider).valueOrNull ?? [];
      _fetchPrices(holdings);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _fetchPrices(List<PaperHolding> holdings) async {
    if (holdings.isEmpty) return;
    final quotes = await _backend.getQuotes(holdings.map((h) => h.symbol).toList());
    final m = <String, double>{};
    quotes.forEach((sym, q) {
      final p = (q['price'] as num?)?.toDouble() ??
          (q['current_price'] as num?)?.toDouble();
      if (p != null) m[sym] = p;
    });
    if (mounted) setState(() { _prices = m; _lastRefreshed = DateTime.now(); });
  }

  @override
  Widget build(BuildContext context) {
    final accountAsync = ref.watch(paperAccountProvider);

    return accountAsync.when(
      loading: () => const _LoadingView(),
      error: (e, _) => _ErrorView(message: e.toString()),
      data: (account) {
        if (account == null || !account.isActive) {
          return _ActivationView(onActivate: () async {
            final service = ref.read(paperTradingServiceProvider);
            await service?.activate();
          });
        }
        return _TradingDashboard(
          account: account,
          tabs: _tabs,
          prices: _prices,
          lastRefreshed: _lastRefreshed,
          onRefreshPrices: _fetchPrices,
        );
      },
    );
  }
}

// ── Activation Screen ─────────────────────────────────────────────────────────

class _ActivationView extends StatefulWidget {
  final Future<void> Function() onActivate;
  const _ActivationView({required this.onActivate});

  @override
  State<_ActivationView> createState() => _ActivationViewState();
}

class _ActivationViewState extends State<_ActivationView> {
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
                style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            const Text(
              'Practice trading with \$1,000,000 in virtual cash.\nNo real money — all the strategy.',
              style: TextStyle(color: Colors.white54, fontSize: 15, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 36),
            _Feature(Icons.attach_money, 'Start with \$1,000,000 virtual cash'),
            const SizedBox(height: 12),
            _Feature(Icons.show_chart, 'Live real-time market prices'),
            const SizedBox(height: 12),
            _Feature(Icons.receipt_long, 'Capital gains tax simulation (22% / 15%)'),
            const SizedBox(height: 12),
            _Feature(Icons.insights, 'Track P&L, tax, and profit margin'),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _activating
                    ? null
                    : () async {
                        setState(() => _activating = true);
                        await widget.onActivate();
                      },
                child: _activating
                    ? const SizedBox(height: 22, width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Activate Paper Trading',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Feature(this.icon, this.text);
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(children: [
      Icon(icon, color: primary, size: 20),
      const SizedBox(width: 12),
      Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 14))),
    ]);
  }
}

// ── Main Dashboard ────────────────────────────────────────────────────────────

class _TradingDashboard extends ConsumerWidget {
  final PaperAccount account;
  final TabController tabs;
  final Map<String, double> prices;
  final DateTime? lastRefreshed;
  final Future<void> Function(List<PaperHolding>) onRefreshPrices;

  const _TradingDashboard({
    required this.account,
    required this.tabs,
    required this.prices,
    required this.lastRefreshed,
    required this.onRefreshPrices,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holdingsAsync = ref.watch(paperHoldingsProvider);
    final txAsync = ref.watch(paperTransactionsProvider);
    final holdings = holdingsAsync.valueOrNull ?? [];

    // Initial price fetch when holdings load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (prices.isEmpty && holdings.isNotEmpty) onRefreshPrices(holdings);
    });

    final enriched = holdings
        .map((h) => PaperHoldingWithValue(holding: h, currentPrice: prices[h.symbol]))
        .toList();

    final holdingsValue = enriched.fold<double>(
        0, (s, h) => s + (h.currentValue ?? h.totalCost));
    final totalValue = account.cashBalance + holdingsValue;
    final totalPnl = totalValue - PaperAccount.startingBalance;
    final isPositive = totalPnl >= 0;

    return Column(
      children: [
        // ── Summary strip ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _SummaryStrip(
            totalValue: totalValue,
            cashBalance: account.cashBalance,
            holdingsValue: holdingsValue,
            totalPnl: totalPnl,
            isPositive: isPositive,
            lastRefreshed: lastRefreshed,
            onRefresh: () => onRefreshPrices(holdings),
          ),
        ),

        // ── Tabs ───────────────────────────────────────────────────────────
        const SizedBox(height: 12),
        TabBar(
          controller: tabs,
          indicatorColor: Theme.of(context).colorScheme.primary,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          tabs: const [
            Tab(text: 'Holdings'),
            Tab(text: 'Transactions'),
          ],
        ),

        // ── Disclaimer ────────────────────────────────────────────────────
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: DisclaimerBanner(),
        ),

        // ── Tab views ──────────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: tabs,
            children: [
              _HoldingsTab(
                enriched: enriched,
                onRefresh: () => onRefreshPrices(holdings),
                onReset: () => _confirmReset(context, ref),
              ),
              _TransactionsTab(txAsync: txAsync),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Reset Account?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will wipe all holdings and transactions and reset your balance to \$1,000,000.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(paperTradingServiceProvider)?.resetAccount();
    }
  }
}

// ── Summary Strip ─────────────────────────────────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  final double totalValue;
  final double cashBalance;
  final double holdingsValue;
  final double totalPnl;
  final bool isPositive;
  final DateTime? lastRefreshed;
  final VoidCallback onRefresh;

  const _SummaryStrip({
    required this.totalValue,
    required this.cashBalance,
    required this.holdingsValue,
    required this.totalPnl,
    required this.isPositive,
    required this.lastRefreshed,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final pnlColor = isPositive ? primary : Colors.redAccent;
    final fmt = NumberFormat('#,##0.00');
    final pnlPct = ((totalPnl / PaperAccount.startingBalance) * 100).abs();
    final refreshLabel = lastRefreshed != null
        ? 'Live · ${DateFormat('h:mm:ss a').format(lastRefreshed!)}'
        : 'Pull to refresh';

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.currency_exchange, size: 16, color: Colors.white38),
            const SizedBox(width: 6),
            const Text('Paper Account', style: TextStyle(color: Colors.white38, fontSize: 12)),
            const Spacer(),
            // Live badge
            GestureDetector(
              onTap: onRefresh,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: lastRefreshed != null
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, size: 6,
                      color: lastRefreshed != null ? Colors.greenAccent : Colors.white38),
                  const SizedBox(width: 4),
                  Text(refreshLabel,
                      style: TextStyle(
                          color: lastRefreshed != null ? Colors.greenAccent : Colors.white38,
                          fontSize: 10, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Text('\$${fmt.format(totalValue)}',
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Row(children: [
            Icon(isPositive ? Icons.trending_up : Icons.trending_down,
                color: pnlColor, size: 16),
            const SizedBox(width: 4),
            Text(
              '${isPositive ? '+' : '-'}\$${fmt.format(totalPnl.abs())} (${pnlPct.toStringAsFixed(2)}%)',
              style: TextStyle(color: pnlColor, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            const Text('vs \$1M start', style: TextStyle(color: Colors.white30, fontSize: 12)),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 12),
          Row(children: [
            _MiniStat('Cash', '\$${_compact(cashBalance)}', Colors.white70),
            const SizedBox(width: 24),
            _MiniStat('Invested', '\$${_compact(holdingsValue)}', Colors.white70),
          ]),
        ],
      ),
    );
  }

  String _compact(double v) {
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(2)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
    return v.toStringAsFixed(2);
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      );
}

// ── Holdings Tab ──────────────────────────────────────────────────────────────

class _HoldingsTab extends StatelessWidget {
  final List<PaperHoldingWithValue> enriched;
  final VoidCallback onRefresh;
  final VoidCallback onReset;

  const _HoldingsTab({required this.enriched, required this.onRefresh, required this.onReset});

  @override
  Widget build(BuildContext context) {
    if (enriched.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox_outlined, size: 56, color: Colors.white24),
            const SizedBox(height: 16),
            const Text('No paper positions yet', style: TextStyle(color: Colors.white54, fontSize: 15)),
            const SizedBox(height: 8),
            const Text('Open any stock and tap Trade to start',
                style: TextStyle(color: Colors.white30, fontSize: 13)),
            const SizedBox(height: 28),
            TextButton.icon(
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text('Reset Account'),
              style: TextButton.styleFrom(foregroundColor: Colors.white30),
              onPressed: onReset,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          ...enriched.map((h) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PaperHoldingCard(holding: h),
          )),
          const SizedBox(height: 16),
          TextButton.icon(
            icon: const Icon(Icons.restart_alt, size: 16),
            label: const Text('Reset Account to \$1M'),
            style: TextButton.styleFrom(foregroundColor: Colors.white30),
            onPressed: onReset,
          ),
        ],
      ),
    );
  }
}

class _PaperHoldingCard extends StatelessWidget {
  final PaperHoldingWithValue holding;
  const _PaperHoldingCard({required this.holding});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF12A28C);
    final pnlColor = holding.isPositive ? green : Colors.redAccent;
    final fmt = NumberFormat('#,##0.00');
    final days = holding.holdingDays;
    final termLabel = days != null
        ? '${days}d · ${holding.isShortTerm ? 'SHORT TERM' : 'LONG TERM'}'
        : null;

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(holding.symbol,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    if (termLabel != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: holding.isShortTerm
                              ? Colors.orange.withValues(alpha: 0.18)
                              : green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(termLabel,
                            style: TextStyle(
                                color: holding.isShortTerm ? Colors.orange : green,
                                fontSize: 9, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ]),
                  Text(holding.name,
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
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
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                ),
                if (holding.unrealizedPnl != null)
                  Text(
                    '${holding.isPositive ? '+' : ''}\$${fmt.format(holding.unrealizedPnl!)} '
                    '(${holding.unrealizedPnlPct!.toStringAsFixed(2)}%)',
                    style: TextStyle(color: pnlColor, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ]),

          const SizedBox(height: 10),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 10),

          // Price row
          Row(children: [
            _D('Shares', holding.shares.toStringAsFixed(4)),
            _D('Avg Cost', '\$${fmt.format(holding.avgCost)}'),
            if (holding.currentPrice != null)
              _D('Live Price', '\$${fmt.format(holding.currentPrice!)}'),
            _D('Cost Basis', '\$${fmt.format(holding.totalCost)}'),
          ]),

          // Tax / profit margin row (only when there's a price and unrealized profit)
          if (holding.unrealizedPnl != null && holding.unrealizedPnl! != 0) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: Colors.white12),
            const SizedBox(height: 8),
            Row(children: [
              _D('Tax Rate',
                  '${(holding.holding.taxRate * 100).toStringAsFixed(0)}%'),
              if (holding.estimatedTax != null)
                _D('Est. Tax',
                    '\$${fmt.format(holding.estimatedTax!)}'),
              if (holding.afterTaxPnl != null)
                _D('After-Tax P&L',
                    '${holding.afterTaxPnl! >= 0 ? '+' : ''}\$${fmt.format(holding.afterTaxPnl!)}'),
              if (holding.profitMarginPct != null)
                _D('Margin',
                    '${holding.profitMarginPct!.toStringAsFixed(1)}%'),
            ]),
          ],
        ],
      ),
    );
  }
}

class _D extends StatelessWidget {
  final String label;
  final String value;
  const _D(this.label, this.value);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white30, fontSize: 10)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      );
}

// ── Transactions Tab ──────────────────────────────────────────────────────────

class _TransactionsTab extends StatelessWidget {
  final AsyncValue<List<PaperTransaction>> txAsync;
  const _TransactionsTab({required this.txAsync});

  @override
  Widget build(BuildContext context) {
    return txAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: Colors.white54))),
      data: (txList) {
        if (txList.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_outlined, size: 56, color: Colors.white24),
                SizedBox(height: 16),
                Text('No transactions yet', style: TextStyle(color: Colors.white54, fontSize: 15)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: txList.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (_, i) => _TxCard(tx: txList[i]),
        );
      },
    );
  }
}

class _TxCard extends StatelessWidget {
  final PaperTransaction tx;
  const _TxCard({required this.tx});

  @override
  Widget build(BuildContext context) {
    final isBuy = tx.isBuy;
    const green = Color(0xFF12A28C);
    final color = isBuy ? green : Colors.redAccent;
    final fmt = NumberFormat('#,##0.00');
    final dateFmt = DateFormat('MMM d, h:mm a');

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(isBuy ? Icons.arrow_downward : Icons.arrow_upward,
                    color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(isBuy ? 'BUY' : 'SELL',
                          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 6),
                      Text(tx.symbol,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                      if (!isBuy && tx.holdingDays != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: tx.isShortTerm
                                ? Colors.orange.withValues(alpha: 0.18)
                                : green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tx.isShortTerm ? 'SHORT' : 'LONG',
                            style: TextStyle(
                                color: tx.isShortTerm ? Colors.orange : green,
                                fontSize: 9, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ]),
                    Text(
                      '${tx.shares.toStringAsFixed(4)} shares @ \$${fmt.format(tx.price)}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    Text(dateFmt.format(tx.timestamp),
                        style: const TextStyle(color: Colors.white30, fontSize: 11)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isBuy ? '-' : '+'}\$${fmt.format(tx.totalValue)}',
                    style: TextStyle(
                        color: isBuy ? Colors.redAccent : green,
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  if (!isBuy && tx.realizedPnl != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Gross P&L: ${tx.realizedPnl! >= 0 ? '+' : ''}\$${fmt.format(tx.realizedPnl!)}',
                      style: TextStyle(
                        color: tx.realizedPnl! >= 0 ? green : Colors.redAccent,
                        fontSize: 11, fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),

          // Tax breakdown for SELL transactions
          if (!isBuy && tx.taxPaid != null && tx.taxPaid! > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _TaxRow(
                    label: 'Capital Gains Tax (${((tx.taxRate ?? 0) * 100).toStringAsFixed(0)}% '
                        '${tx.isShortTerm ? 'short-term' : 'long-term'})',
                    value: '-\$${fmt.format(tx.taxPaid!)}',
                    valueColor: Colors.orange,
                  ),
                  const SizedBox(height: 4),
                  _TaxRow(
                    label: 'After-Tax Profit',
                    value: '${(tx.afterTaxPnl ?? 0) >= 0 ? '+' : ''}\$${fmt.format(tx.afterTaxPnl ?? 0)}',
                    valueColor: (tx.afterTaxPnl ?? 0) >= 0 ? green : Colors.redAccent,
                    bold: true,
                  ),
                  if (tx.profitMarginPct != null) ...[
                    const SizedBox(height: 4),
                    _TaxRow(
                      label: 'Profit Margin',
                      value: '${tx.profitMarginPct!.toStringAsFixed(2)}%',
                      valueColor: (tx.profitMarginPct ?? 0) >= 0 ? green : Colors.redAccent,
                    ),
                  ],
                ],
              ),
            ),
          ],

          // Zero-tax sell (loss) — still show margin
          if (!isBuy && (tx.taxPaid == null || tx.taxPaid == 0) && tx.realizedPnl != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.info_outline, size: 12, color: Colors.white30),
              const SizedBox(width: 4),
              Text(
                tx.realizedPnl! < 0
                    ? 'Loss — no tax applicable. '
                        'Margin: ${tx.profitMarginPct?.toStringAsFixed(2) ?? '—'}%'
                    : 'No tax recorded.',
                style: const TextStyle(color: Colors.white30, fontSize: 11),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _TaxRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final bool bold;
  const _TaxRow({
    required this.label,
    required this.value,
    required this.valueColor,
    this.bold = false,
  });
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: Text(label,
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.normal))),
        Text(value,
            style: TextStyle(
                color: valueColor,
                fontSize: 11,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600)),
      ]);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});
  @override
  Widget build(BuildContext context) =>
      Center(child: Text(message, style: const TextStyle(color: Colors.white54)));
}
