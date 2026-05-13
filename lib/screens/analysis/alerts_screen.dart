import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/stock_summary.dart';
import '../../providers/market_data_provider.dart';
import '../../providers/usage_analytics_provider.dart';
import '../../services/backend_service.dart';
import '../../services/usage_analytics_service.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/subscription_gate.dart';
import '../../features/chart/screens/asset_chart_screen.dart';

// ── Theme ─────────────────────────────────────────────────────────────────────
const _bg      = Color(0xFF0D131A);
const _cardBg  = Color(0xFF111925);
const _accent  = Color(0xFF12A28C);
const _textDim = Color(0xFF8A9BB5);

// ─────────────────────────────────────────────────────────────────────────────
// ALERTS SCREEN
// Phase 7.1: AI-triggered technical alerts (RSI cross + volume spike)
// Phase 7.2: Watchlist-aware — scans user's saved symbols
// ─────────────────────────────────────────────────────────────────────────────
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  final _backend = BackendService();

  List<Map<String, dynamic>> _alerts = [];
  bool   _loading = false;
  String? _error;
  DateTime? _lastFetched;

  // Default symbols scanned when watchlist is empty
  static const _defaultSymbols =
      'AAPL,MSFT,NVDA,GOOGL,AMZN,META,TSLA,NFLX,AMD,INTC,QCOM,AVGO,BTC,ETH,SOL,XRP';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    // Build symbol list: watchlist ∪ defaults (capped at 20)
    final watchlist = ref.read(watchlistProvider).valueOrNull ?? [];
    final extra = _defaultSymbols.split(',');
    final symbols = <String>{...watchlist, ...extra}.take(20).join(',');

    ref.read(usageAnalyticsProvider)?.logFeatureUsed(UsageFeature.alerts);
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _backend.getTechnicalAlerts(symbols: symbols);
      if (mounted) {
        setState(() {
          _alerts      = (data['alerts'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>();
          _loading     = false;
          _lastFetched = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Failed to load alerts.'; });
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Color _typeColor(String type) {
    switch (type) {
      case 'OVERSOLD':      return const Color(0xFF26C96F);
      case 'OVERBOUGHT':    return const Color(0xFFEF4444);
      case 'VOLUME_SPIKE':  return const Color(0xFFFFB547);
      default:              return _textDim;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'OVERSOLD':      return Icons.arrow_downward_rounded;
      case 'OVERBOUGHT':    return Icons.arrow_upward_rounded;
      case 'VOLUME_SPIKE':  return Icons.bar_chart_rounded;
      default:              return Icons.notifications_rounded;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'OVERSOLD':      return 'Oversold';
      case 'OVERBOUGHT':    return 'Overbought';
      case 'VOLUME_SPIKE':  return 'Volume Spike';
      default:              return type;
    }
  }

  Color _severityBorderColor(String severity) =>
      severity == 'high' ? const Color(0xFFEF4444).withOpacity(0.4) : Colors.white12;

  void _openChart(Map<String, dynamic> alert) {
    final sym   = alert['symbol'] as String? ?? '';
    final price = (alert['price'] as num?)?.toDouble() ?? 0.0;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssetChartScreen(
          stock: StockSummary(
            ticker: sym, name: sym, price: price, changePercent: 0.0,
            isCrypto: _isCrypto(sym),
          ),
        ),
      ),
    );
  }

  bool _isCrypto(String sym) {
    const crypto = {'BTC','ETH','BNB','SOL','ADA','XRP','DOT','AVAX','DOGE'};
    return crypto.contains(sym.toUpperCase());
  }

  // ── Widgets ────────────────────────────────────────────────────────────────

  Widget _alertCard(Map<String, dynamic> alert) {
    final sym       = alert['symbol']    as String? ?? '';
    final type      = alert['type']      as String? ?? '';
    final condition = alert['condition'] as String? ?? '';
    final severity  = alert['severity']  as String? ?? 'medium';
    final price     = (alert['price']    as num?)?.toDouble();
    final rsi       = (alert['rsi']      as num?)?.toDouble();
    final mult      = (alert['multiplier'] as num?)?.toDouble();

    final typeColor = _typeColor(type);
    final typeIcon  = _typeIcon(type);
    final typeLabel = _typeLabel(type);

    return GestureDetector(
      onTap: () => _openChart(alert),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _severityBorderColor(severity)),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Icon badge
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: typeColor.withOpacity(0.3)),
              ),
              child: Icon(typeIcon, color: typeColor, size: 20),
            ),
            const SizedBox(width: 12),
            // Symbol + condition
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(sym,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: typeColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(typeLabel,
                            style: TextStyle(
                                color: typeColor, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                      if (severity == 'high') ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('HIGH',
                              style: TextStyle(
                                  color: Color(0xFFEF4444), fontSize: 9,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(condition,
                      style: const TextStyle(color: _textDim, fontSize: 12)),
                ],
              ),
            ),
            // Price + extra stat
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (price != null)
                  Text(
                    '\$${price >= 1000 ? price.toStringAsFixed(0) : price.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                const SizedBox(height: 3),
                if (rsi != null)
                  Text('RSI ${rsi.toStringAsFixed(0)}',
                      style: TextStyle(color: typeColor, fontSize: 11))
                else if (mult != null)
                  Text('${mult.toStringAsFixed(1)}× vol',
                      style: TextStyle(color: typeColor, fontSize: 11)),
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
            Icon(Icons.check_circle_outline_rounded,
                size: 52, color: _accent.withOpacity(0.5)),
            const SizedBox(height: 14),
            const Text('No alerts triggered',
                style: TextStyle(color: Colors.white70, fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'Markets look calm — no RSI extremes\nor unusual volume spikes right now.',
              style: TextStyle(color: _textDim, fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendRow() {
    const items = [
      ('OVERSOLD',     Color(0xFF26C96F), 'RSI < 30'),
      ('OVERBOUGHT',   Color(0xFFEF4444), 'RSI > 70'),
      ('VOLUME SPIKE', Color(0xFFFFB547), 'Vol > 2× avg'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: items.map((item) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8,
                decoration: BoxDecoration(color: item.$2, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text('${item.$1}  ${item.$3}',
                style: const TextStyle(color: _textDim, fontSize: 11)),
          ],
        )).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lastFetchedStr = _lastFetched != null
        ? 'Updated ${_lastFetched!.hour.toString().padLeft(2, '0')}:${_lastFetched!.minute.toString().padLeft(2, '0')}'
        : '';

    return SubscriptionGateScreen(
      feature: 'Technical Alerts',
      description:
          'Real-time RSI crossovers and volume spikes across your entire watchlist.',
      child: Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Technical Alerts',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18)),
        actions: [
          if (lastFetchedStr.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(lastFetchedStr,
                    style: const TextStyle(color: _textDim, fontSize: 11)),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _accent),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _legendRow(),
          const Divider(color: Colors.white10, height: 1),
          // Alert count row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                if (_loading)
                  const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _accent))
                else
                  Text(
                    _alerts.isEmpty ? 'No alerts' : '${_alerts.length} alert${_alerts.length == 1 ? "" : "s"}',
                    style: const TextStyle(color: _textDim, fontSize: 12),
                  ),
                const Spacer(),
                if (_loading)
                  const Text('Scanning RSI + volume...',
                      style: TextStyle(color: _textDim, fontSize: 11)),
              ],
            ),
          ),
          // Body
          Expanded(
            child: _error != null
                ? Center(child: Text(_error!,
                    style: const TextStyle(color: Color(0xFFEF4444))))
                : _loading
                    ? const Center(child: CircularProgressIndicator(color: _accent))
                    : _alerts.isEmpty
                        ? _emptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                            itemCount: _alerts.length,
                            itemBuilder: (_, i) => _alertCard(_alerts[i]),
                          ),
          ),
        ],
      ),
    ), // Scaffold
    ); // SubscriptionGateScreen
  }
}
