import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/chart/screens/asset_chart_screen.dart';
import '../../models/stock_summary.dart';
import '../../providers/market_data_provider.dart';

class MarketCategoryScreen extends ConsumerWidget {
  final bool isCrypto;

  const MarketCategoryScreen({super.key, required this.isCrypto});

  Color _changeColor(double? pct) {
    if (pct == null) return Colors.white54;
    return pct >= 0 ? Colors.greenAccent : Colors.redAccent;
  }

  String _fmt(double? v, {int decimals = 2, String prefix = ''}) {
    if (v == null) return '—';
    return '$prefix${v.toStringAsFixed(decimals)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final category = isCrypto ? 'crypto' : 'stock';

    final indicesAsync   = ref.watch(indicesProvider(category));
    final heatmapAsync   = ref.watch(sectorHeatmapProvider);
    final topMoversAsync = ref.watch(topMoversProvider(category));

    return Scaffold(
      appBar: AppBar(
        title: Text(isCrypto ? 'Crypto Markets' : 'Stock Markets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(indicesProvider(category));
              ref.invalidate(sectorHeatmapProvider);
              ref.invalidate(topMoversProvider(category));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        physics: const BouncingScrollPhysics(),
        children: [

          // ── Feature chips card ───────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        'AI-powered analysis',
                        style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: ShapeDecoration(
                        color: colorScheme.primary.withOpacity(0.12),
                        shape: const StadiumBorder(),
                      ),
                      child: Text(
                        isCrypto ? 'Crypto' : 'Stocks',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'Tap any ticker to see a deep chart, fundamentals, and AI coaching.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _Chip(label: 'Live prices'),
                      _Chip(label: 'Signal engine'),
                      _Chip(label: 'AI coaching'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Indices / Crypto benchmarks ──────────────────────────────────
          Text(
            isCrypto ? 'Crypto benchmarks' : 'Major indices',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),

          indicesAsync.when(
            loading: () => const _SectionLoader(),
            error:   (_, __) => _ErrorRetry(
              label: 'Could not load indices',
              onRetry: () => ref.invalidate(indicesProvider(category)),
            ),
            data: (indices) => Column(
              children: indices.map((idx) {
                final pct = (idx['change_percent'] as num?)?.toDouble();
                final price = (idx['price'] as num?)?.toDouble();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              idx['symbol'] as String? ?? '—',
                              style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              idx['name'] as String? ?? '',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: Colors.white70),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _fmt(price),
                              style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${pct != null && pct >= 0 ? '+' : ''}${_fmt(pct)}%',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _changeColor(pct),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ]),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // ── Sector heatmap (stocks only) ─────────────────────────────────
          if (!isCrypto) ...[
            const SizedBox(height: 20),
            Text(
              'Sector performance',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            heatmapAsync.when(
              loading: () => const _SectionLoader(),
              error:   (_, __) => _ErrorRetry(
                label: 'Could not load heatmap',
                onRetry: () => ref.invalidate(sectorHeatmapProvider),
              ),
              data: (sectors) => _SectorHeatmap(sectors: sectors),
            ),
          ],

          // ── Top movers ───────────────────────────────────────────────────
          const SizedBox(height: 20),
          Text(
            isCrypto ? 'Top crypto movers' : 'Top stock movers',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),

          topMoversAsync.when(
            loading: () => const _SectionLoader(),
            error:   (_, __) => _ErrorRetry(
              label: 'Could not load movers',
              onRetry: () => ref.invalidate(topMoversProvider(category)),
            ),
            data: (movers) => Column(
              children: movers.map((m) {
                final sym = m['symbol'] as String? ?? '';
                final price = (m['price'] as num?)?.toDouble();
                final pct   = (m['change_percent'] as num?)?.toDouble();

                // Build a minimal StockSummary to reuse AssetChartScreen
                final stock = StockSummary(
                  ticker: sym,
                  name: sym,
                  price: price ?? 0,
                  changePercent: pct ?? 0,
                  sector: '',
                  industry: '',
                  fundamentals: const {},
                  technicalHighlights: const [],
                );

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      title: Text(
                        sym,
                        style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        m['asset_type'] as String? ?? '',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white54),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '\$${_fmt(price)}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${pct != null && pct >= 0 ? '+' : ''}${_fmt(pct)}%',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _changeColor(pct),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AssetChartScreen(stock: stock),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sector Heatmap Grid ───────────────────────────────────────────────────────

class _SectorHeatmap extends StatelessWidget {
  final List<Map<String, dynamic>> sectors;
  const _SectorHeatmap({required this.sectors});

  Color _heatColor(double? pct) {
    if (pct == null) return Colors.white12;
    if (pct >= 2.0)  return const Color(0xFF0C9E6A).withOpacity(0.85);
    if (pct >= 0.5)  return const Color(0xFF0C9E6A).withOpacity(0.45);
    if (pct >= -0.5) return Colors.white12;
    if (pct >= -2.0) return const Color(0xFFCF3B2E).withOpacity(0.45);
    return const Color(0xFFCF3B2E).withOpacity(0.85);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: sectors.length,
      itemBuilder: (context, i) {
        final s   = sectors[i];
        final pct = (s['change_percent'] as num?)?.toDouble();
        return Container(
          decoration: BoxDecoration(
            color: _heatColor(pct),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                s['sector'] as String? ?? '',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                pct == null
                    ? '—'
                    : '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: pct == null
                      ? Colors.white38
                      : pct >= 0 ? Colors.greenAccent : Colors.redAccent,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _SectionLoader extends StatelessWidget {
  const _SectionLoader();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(Color(0xFF12A28C)),
            strokeWidth: 2,
          ),
        ),
      );
}

class _ErrorRetry extends StatelessWidget {
  final String label;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.label, required this.onRetry});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style:
                    const TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(width: 12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: Colors.white.withOpacity(0.06),
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
