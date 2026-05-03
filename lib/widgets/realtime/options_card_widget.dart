import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/market_flow.dart';
import '../../providers/realtime_providers.dart';

/// Options summary card — PCR gauge, max pain, ATM IV, top OI strikes.
///
/// For crypto symbols (or any symbol where the backend returns
/// [OptionsData.available] == false) the card renders a graceful
/// "not available" placeholder instead of data.
class OptionsCardWidget extends ConsumerWidget {
  final String symbol;
  final bool isCrypto;

  const OptionsCardWidget({
    super.key,
    required this.symbol,
    required this.isCrypto,
  });

  static const _bgCard = Color(0xFF111925);
  static const _green = Color(0xFF26A69A);
  static const _red = Color(0xFFEF5350);
  static const _amber = Color(0xFFFFB300);
  static const _label = Color(0xFF8A95A3);
  static const _divider = Color(0xFF1E2A38);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Crypto never has options — skip the network call entirely.
    if (isCrypto) return _buildUnavailable('Options data not available for crypto assets.');

    final async = ref.watch(optionsProvider(symbol));
    return async.when(
      loading: () => _buildShimmer(),
      error: (_, __) => _buildUnavailable('Could not load options data.'),
      data: (data) {
        if (data == null || !data.available) {
          return _buildUnavailable(
              data?.note ?? 'Options data not available for $symbol.');
        }
        return _buildCard(data);
      },
    );
  }

  // ── Card ────────────────────────────────────────────────────────────────────

  Widget _buildCard(OptionsData data) {
    return Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(data),
          const Divider(color: _divider, height: 1),
          _metricsRow(data),
          if (data.maxPain != null) ...[
            const Divider(color: _divider, height: 1),
            _maxPainRow(data),
          ],
          if (data.topCallStrikes.isNotEmpty ||
              data.topPutStrikes.isNotEmpty) ...[
            const Divider(color: _divider, height: 1),
            _strikesSection(data),
          ],
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _header(OptionsData data) {
    final pcrColor = _pcrColor(data.pcrSignal);
    final pcrLabel = _pcrLabel(data.pcrSignal);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(
        children: [
          const Text('Options',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          const Spacer(),
          if (data.expiry != null)
            Text('Exp ${_fmtExpiry(data.expiry!)}',
                style: const TextStyle(color: _label, fontSize: 11)),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: pcrColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: pcrColor.withValues(alpha: 0.4)),
            ),
            child: Text(pcrLabel,
                style: TextStyle(
                    color: pcrColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Metrics row: PCR vol, PCR OI, ATM IV, IV skew ──────────────────────────

  Widget _metricsRow(OptionsData data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _metric('PCR Vol',
              data.pcrVolume != null ? data.pcrVolume!.toStringAsFixed(2) : '—',
              _pcrColor(data.pcrSignal)),
          _metric('PCR OI',
              data.pcrOi != null ? data.pcrOi!.toStringAsFixed(2) : '—',
              _label),
          _metric(
              'ATM IV',
              data.atmIv != null
                  ? '${(data.atmIv! * 100).toStringAsFixed(1)}%'
                  : '—',
              _amber),
          _metric(
              'IV Skew',
              data.ivSkew != null
                  ? '${data.ivSkew! >= 0 ? '+' : ''}${(data.ivSkew! * 100).toStringAsFixed(1)}%'
                  : '—',
              data.ivSkew != null && data.ivSkew! > 0 ? _red : _green),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: _label, fontSize: 10)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: valueColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Max Pain ────────────────────────────────────────────────────────────────

  Widget _maxPainRow(OptionsData data) {
    final fmt = NumberFormat('#,##0.##');
    final distStr = data.maxPainDistancePct != null
        ? '${data.maxPainDistancePct! >= 0 ? '+' : ''}${data.maxPainDistancePct!.toStringAsFixed(1)}% from price'
        : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          const Text('Max Pain',
              style: TextStyle(color: _label, fontSize: 12)),
          const Spacer(),
          Text('\$${fmt.format(data.maxPain)}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          if (distStr.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(distStr,
                style: const TextStyle(color: _label, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  // ── Top Strikes ─────────────────────────────────────────────────────────────

  Widget _strikesSection(OptionsData data) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Top OI Strikes',
              style: TextStyle(
                  color: _label, fontSize: 11, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: _strikeColumn('Calls', data.topCallStrikes, _green)),
              const SizedBox(width: 16),
              Expanded(
                  child: _strikeColumn('Puts', data.topPutStrikes, _red)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _strikeColumn(
      String title, List<OptionsStrike> strikes, Color color) {
    if (strikes.isEmpty) return const SizedBox.shrink();
    final fmt = NumberFormat('#,##0.##');
    final oiFmt = NumberFormat.compact();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        ...strikes.take(3).map((s) {
          final oi = title == 'Calls' ? s.callOi : s.putOi;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('\$${fmt.format(s.strike)}',
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
                Text('OI ${oiFmt.format(oi)}',
                    style:
                        const TextStyle(color: _label, fontSize: 11)),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ── Unavailable state ───────────────────────────────────────────────────────

  Widget _buildUnavailable(String message) {
    return Container(
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider, width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: _label, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: _label, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ── Shimmer loading placeholder ─────────────────────────────────────────────

  Widget _buildShimmer() {
    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider, width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(_label),
          ),
        ),
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Color _pcrColor(String? signal) {
    switch (signal) {
      case 'bearish':
        return _red;
      case 'bullish':
        return _green;
      default:
        return _amber;
    }
  }

  String _pcrLabel(String? signal) {
    switch (signal) {
      case 'bearish':
        return 'PUT HEAVY';
      case 'bullish':
        return 'CALL HEAVY';
      default:
        return 'BALANCED';
    }
  }

  String _fmtExpiry(String expiry) {
    try {
      final dt = DateTime.parse(expiry);
      return DateFormat('MMM d').format(dt);
    } catch (_) {
      return expiry;
    }
  }
}
