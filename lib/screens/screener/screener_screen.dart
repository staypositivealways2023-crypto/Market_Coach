import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/stock_summary.dart';
import '../../providers/usage_analytics_provider.dart';
import '../../services/backend_service.dart';
import '../../services/usage_analytics_service.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/subscription_gate.dart';
import '../../features/chart/screens/asset_chart_screen.dart';

// ── Theme constants ───────────────────────────────────────────────────────────
const _bg       = Color(0xFF0D131A);
const _cardBg   = Color(0xFF111925);
const _accent   = Color(0xFF12A28C);
const _textDim  = Color(0xFF8A9BB5);

Widget _spacedGlassCard({
  required EdgeInsetsGeometry margin,
  EdgeInsetsGeometry? padding,
  required Widget child,
}) {
  return Padding(
    padding: margin,
    child: GlassCard(
      padding: padding,
      child: child,
    ),
  );
}

class ScreenerScreen extends ConsumerStatefulWidget {
  const ScreenerScreen({super.key});

  @override
  ConsumerState<ScreenerScreen> createState() => _ScreenerScreenState();
}

class _ScreenerScreenState extends ConsumerState<ScreenerScreen> {
  final _backend = BackendService();

  // ── Filter state ─────────────────────────────────────────────────────────
  String   _assetType = 'all';       // all | stock | crypto
  String?  _sector;                  // null = all sectors
  String?  _signal;                  // null | OVERSOLD | OVERBOUGHT | NEUTRAL
  String   _sortBy    = 'change_percent'; // change_percent | volume | rsi

  List<Map<String, dynamic>> _results = [];
  bool   _loading = false;
  String? _error;

  // ── Request versioning — prevents a stale earlier request from overwriting
  // a newer one when the user changes filters quickly.
  int _requestVersion = 0;

  static const _sectors = ['Tech', 'Finance', 'Healthcare', 'Energy', 'Consumer', 'ETF', 'Crypto'];

  @override
  void initState() {
    super.initState();
    _runScreener();
  }

  Future<void> _runScreener() async {
    final myVersion = ++_requestVersion;
    setState(() { _loading = true; _error = null; });
    // Log feature usage
    ref.read(usageAnalyticsProvider)?.logFeatureUsed(UsageFeature.screener);
    try {
      final results = await _backend.getScreenerResults(
        assetType: _assetType,
        sector: _sector,
        signal: _signal,
        sortBy: _sortBy,
        limit: 30,
      );
      // Discard results if a newer request was issued while we were waiting.
      if (!mounted || myVersion != _requestVersion) return;
      setState(() { _results = results; _loading = false; });
    } catch (e) {
      if (!mounted || myVersion != _requestVersion) return;
      setState(() { _error = 'Failed to load screener results.'; _loading = false; });
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Color _changeColor(double? v) =>
      v == null ? _textDim : (v >= 0 ? const Color(0xFF26C96F) : const Color(0xFFEF4444));

  Color _rsiColor(double? rsi) {
    if (rsi == null) return _textDim;
    if (rsi <= 35) return const Color(0xFF26C96F);   // oversold → green
    if (rsi >= 65) return const Color(0xFFEF4444);   // overbought → red
    return _textDim;
  }

  Color _signalColor(String? signal) {
    switch (signal) {
      case 'OVERSOLD':   return const Color(0xFF26C96F);
      case 'OVERBOUGHT': return const Color(0xFFEF4444);
      default:           return _textDim;
    }
  }

  // ── Navigate to chart ──────────────────────────────────────────────────────

  void _openChart(Map<String, dynamic> row) {
    final sym      = row['symbol'] as String? ?? '';
    final isCrypto = (row['asset_type'] as String?) == 'crypto';
    final stock = StockSummary(
      ticker:      sym,
      name:        sym,
      price:       (row['price'] as num?)?.toDouble() ?? 0.0,
      changePercent: (row['change_percent'] as num?)?.toDouble() ?? 0.0,
      volume:      (row['volume'] as num?)?.toDouble(),
      isCrypto:    isCrypto,
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AssetChartScreen(stock: stock)),
    );
  }

  // ── Widgets ────────────────────────────────────────────────────────────────

  Widget _filterRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Asset type
          _chip('All',    _assetType == 'all',    () => setState(() { _assetType = 'all';    _runScreener(); })),
          const SizedBox(width: 6),
          _chip('Stocks', _assetType == 'stock',  () => setState(() { _assetType = 'stock';  _runScreener(); })),
          const SizedBox(width: 6),
          _chip('Crypto', _assetType == 'crypto', () => setState(() { _assetType = 'crypto'; _runScreener(); })),
          const SizedBox(width: 12),
          // Signal
          _chip('Oversold',   _signal == 'OVERSOLD',   () => setState(() { _signal = _signal == 'OVERSOLD'   ? null : 'OVERSOLD';   _runScreener(); })),
          const SizedBox(width: 6),
          _chip('Overbought', _signal == 'OVERBOUGHT', () => setState(() { _signal = _signal == 'OVERBOUGHT' ? null : 'OVERBOUGHT'; _runScreener(); })),
          const SizedBox(width: 12),
          // Sort
          _chip('Top Movers',  _sortBy == 'change_percent', () => setState(() { _sortBy = 'change_percent'; _runScreener(); })),
          const SizedBox(width: 6),
          _chip('Volume',      _sortBy == 'volume',         () => setState(() { _sortBy = 'volume';         _runScreener(); })),
          const SizedBox(width: 6),
          _chip('RSI',         _sortBy == 'rsi',            () => setState(() { _sortBy = 'rsi';            _runScreener(); })),
        ],
      ),
    );
  }

  Widget _sectorRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: Row(
        children: [
          _chip('All Sectors', _sector == null, () => setState(() { _sector = null; _runScreener(); })),
          ..._sectors.map((s) => Padding(
            padding: const EdgeInsets.only(left: 6),
            child: _chip(s, _sector == s, () => setState(() { _sector = _sector == s ? null : s; _runScreener(); })),
          )),
        ],
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color:        active ? _accent.withOpacity(0.18) : _cardBg,
          border:       Border.all(color: active ? _accent : Colors.white12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:      active ? _accent : _textDim,
            fontSize:   12,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _resultCard(Map<String, dynamic> row) {
    final sym     = row['symbol']         as String?  ?? '';
    final sector  = row['sector']         as String?  ?? '';
    final price   = row['price']          as num?;
    final chgPct  = row['change_percent'] as num?;
    final vol     = row['volume']         as num?;
    final rsi     = row['rsi']            as num?;
    final signal  = row['signal']         as String?;

    String _fmtVol(num? v) {
      if (v == null) return '-';
      if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(1)}B';
      if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
      if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(0)}K';
      return v.toStringAsFixed(0);
    }

    return GestureDetector(
      onTap: () => _openChart(row),
      child: _spacedGlassCard(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Symbol + sector
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sym, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(sector, style: const TextStyle(color: _textDim, fontSize: 11)),
                ],
              ),
            ),
            // Price + change
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    price != null ? '\$${price.toStringAsFixed(price >= 1000 ? 0 : 2)}' : '-',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    chgPct != null ? '${chgPct >= 0 ? '+' : ''}${chgPct.toStringAsFixed(2)}%' : '-',
                    style: TextStyle(color: _changeColor(chgPct?.toDouble()), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // RSI + signal + volume
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // RSI badge
                if (rsi != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _rsiColor(rsi.toDouble()).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _rsiColor(rsi.toDouble()).withOpacity(0.4)),
                    ),
                    child: Text(
                      'RSI ${rsi.toStringAsFixed(0)}',
                      style: TextStyle(color: _rsiColor(rsi.toDouble()), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                const SizedBox(height: 4),
                // Signal label
                Text(
                  signal ?? '-',
                  style: TextStyle(color: _signalColor(signal), fontSize: 10),
                ),
                const SizedBox(height: 2),
                // Volume
                Text(
                  'Vol ${_fmtVol(vol)}',
                  style: const TextStyle(color: _textDim, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: _textDim.withOpacity(0.5)),
            const SizedBox(height: 12),
            const Text('No results match your filters.',
                style: TextStyle(color: _textDim, fontSize: 15), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('Try removing the signal or sector filter.',
                style: TextStyle(color: _textDim, fontSize: 12), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SubscriptionGateScreen(
      feature: 'Smart Screener',
      description:
          'Filter thousands of stocks and crypto by signal, sector, RSI, and more.',
      child: Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Smart Screener',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _accent),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _runScreener,
          ),
        ],
      ),
      body: Column(
        children: [
          _filterRow(),
          _sectorRow(),
          const Divider(color: Colors.white10, height: 1),
          // Results count + loading indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                if (_loading)
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
                  )
                else
                  Text(
                    '${_results.length} results',
                    style: const TextStyle(color: _textDim, fontSize: 12),
                  ),
                const Spacer(),
                if (_loading)
                  const Text('Scanning + computing RSI...',
                      style: TextStyle(color: _textDim, fontSize: 11)),
              ],
            ),
          ),
          // Body
          Expanded(
            child: _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: Color(0xFFEF4444))))
                : _results.isEmpty && !_loading
                    ? _emptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 120),
                        itemCount: _results.length,
                        itemBuilder: (_, i) => _resultCard(_results[i]),
                      ),
          ),
        ],
      ),
    ), // Scaffold
    ); // SubscriptionGateScreen
  }
}
