import 'package:flutter/material.dart';

import '../models/fundamentals.dart';
import 'glass_card.dart';

/// Displays key financial ratios in a clean grid layout.
class FundamentalsCard extends StatelessWidget {
  final FundamentalData data;

  const FundamentalsCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Crypto assets use a different set of fields — equity ratios (P/E, EPS)
    // are meaningless for them.  Show market-cap only when available.
    if (data.isCrypto) return _buildCryptoCard(context, theme);
    if (!data.hasRatios) return const SizedBox.shrink();

    final metrics = _buildMetrics();
    if (metrics.isEmpty) return const SizedBox.shrink();

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_outlined,
                  color: Theme.of(context).colorScheme.primary, size: 18),
              const SizedBox(width: 8),
              Text('Fundamentals',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_hasMetadata)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                  icon: const Icon(Icons.info_outline, size: 16, color: Colors.white38),
                  onPressed: () => _showDataSource(context),
                ),
              if (data.latestQuarterDate != null)
                Text(_quarterLabel(data.latestQuarterDate!),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.white38, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 16),

          // Ratios grid — 2 columns
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.6,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: metrics
                .map((m) => _MetricTile(label: m.label, value: m.value,
                    color: m.color))
                .toList(),
          ),

          if (data.ttmRevenue != null || data.marketCap != null) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 12),
            _TTMRow(data: data, theme: theme),
          ],
        ],
      ),
    );
  }

  List<_Metric> _buildMetrics() {
    final list = <_Metric>[];

    if (data.pe != null && data.pe! > 0) {
      list.add(_Metric('P/E Ratio', '${data.pe!.toStringAsFixed(1)}x',
          _peColor(data.pe!)));
    }
    if (data.ps != null && data.ps! > 0) {
      list.add(_Metric('P/S Ratio', '${data.ps!.toStringAsFixed(1)}x', null));
    }
    if (data.grossMargin != null) {
      list.add(_Metric('Gross Margin',
          '${data.grossMargin!.toStringAsFixed(1)}%', _marginColor(data.grossMargin!)));
    }
    if (data.netMargin != null) {
      list.add(_Metric('Net Margin',
          '${data.netMargin!.toStringAsFixed(1)}%', _marginColor(data.netMargin!)));
    }
    if (data.operatingMargin != null) {
      list.add(_Metric('Op. Margin',
          '${data.operatingMargin!.toStringAsFixed(1)}%',
          _marginColor(data.operatingMargin!)));
    }
    if (data.roe != null) {
      list.add(_Metric(
          'ROE', '${data.roe!.toStringAsFixed(1)}%', _marginColor(data.roe!)));
    }
    if (data.debtEquity != null) {
      list.add(_Metric('Debt/Equity',
          data.debtEquity!.toStringAsFixed(2), _deColor(data.debtEquity!)));
    }
    if (data.currentRatio != null) {
      list.add(_Metric('Current Ratio',
          data.currentRatio!.toStringAsFixed(2), _crColor(data.currentRatio!)));
    }
    return list;
  }

  bool get _hasMetadata =>
      data.source != null ||
      data.period != null ||
      data.fetchedAt != null ||
      data.formulaNote != null;

  void _showDataSource(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111925),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Data source',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (data.source != null) _MetaLine('Source', data.source!),
            if (data.period != null) _MetaLine('Period', data.period!),
            if (data.fetchedAt != null)
              _MetaLine('Last updated', _dateLabel(data.fetchedAt!)),
            if (data.formulaNote != null) _MetaLine('Formula', data.formulaNote!),
          ],
        ),
      ),
    );
  }

  String _dateLabel(String raw) {
    try {
      final d = DateTime.parse(raw).toLocal();
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  String _quarterLabel(String date) {
    try {
      final d = DateTime.parse(date);
      final q = (d.month - 1) ~/ 3 + 1;
      return 'Q$q ${d.year}';
    } catch (_) {
      return date.length > 7 ? date.substring(0, 7) : date;
    }
  }

  Color? _peColor(double pe) {
    if (pe <= 0) return Colors.white54;
    if (pe < 15) return const Color(0xFF00C896);
    if (pe < 30) return Colors.white70;
    return const Color(0xFFFF4D6A);
  }

  Color? _marginColor(double m) {
    if (m >= 20) return const Color(0xFF00C896);
    if (m >= 5)  return Colors.white70;
    return const Color(0xFFFF4D6A);
  }

  Color? _deColor(double de) {
    if (de < 1)  return const Color(0xFF00C896);
    if (de < 2)  return Colors.white70;
    return const Color(0xFFFF4D6A);
  }

  Color? _crColor(double cr) {
    if (cr >= 2) return const Color(0xFF00C896);
    if (cr >= 1) return Colors.white70;
    return const Color(0xFFFF4D6A);
  }

  /// Crypto-specific card — shows market cap only (no equity ratios).
  /// Always renders so the section is visible; shows '—' when data is loading.
  Widget _buildCryptoCard(BuildContext context, ThemeData theme) {
    final cap = data.marketCap;

    String _fmtCap(double v) {
      if (v >= 1e12) return '\$${(v / 1e12).toStringAsFixed(2)}T';
      if (v >= 1e9)  return '\$${(v / 1e9).toStringAsFixed(2)}B';
      if (v >= 1e6)  return '\$${(v / 1e6).toStringAsFixed(2)}M';
      return '\$${v.toStringAsFixed(0)}';
    }

    final capLabel = (cap != null && cap > 0) ? _fmtCap(cap) : '—';

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Icon(Icons.currency_bitcoin,
              color: theme.colorScheme.primary, size: 18),
          const SizedBox(width: 8),
          Text('Market Cap',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: Colors.white54, fontSize: 12)),
          const Spacer(),
          Text(
            capLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric {
  final String label;
  final String value;
  final Color? color;
  const _Metric(this.label, this.value, this.color);
}

class _MetaLine extends StatelessWidget {
  final String label;
  final String value;

  const _MetaLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _MetricTile({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.white38, fontSize: 10)),
          const SizedBox(height: 2),
          Text(value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color ?? Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              )),
        ],
      ),
    );
  }
}

class _TTMRow extends StatelessWidget {
  final FundamentalData data;
  final ThemeData theme;

  const _TTMRow({required this.data, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (data.ttmRevenue != null)
          Expanded(child: _TTMStat('TTM Revenue', _fmt(data.ttmRevenue!), theme)),
        if (data.ttmNetIncome != null)
          Expanded(child: _TTMStat('TTM Net Income', _fmt(data.ttmNetIncome!), theme)),
        if (data.marketCap != null)
          Expanded(child: _TTMStat('Market Cap', _fmt(data.marketCap!), theme)),
        if (data.volume != null)
          Expanded(child: _TTMStat('Volume', _fmtNumber(data.volume!), theme)),
        if (data.turnover != null)
          Expanded(child: _TTMStat('Turnover', _fmt(data.turnover!), theme)),
      ],
    );
  }
  String _fmt(double v) {
    if (v.abs() >= 1e12) return '\$${(v / 1e12).toStringAsFixed(2)}T';
    if (v.abs() >= 1e9)  return '\$${(v / 1e9).toStringAsFixed(1)}B';
    if (v.abs() >= 1e6)  return '\$${(v / 1e6).toStringAsFixed(1)}M';
    return '\$${v.toStringAsFixed(0)}';
  }

  String _fmtNumber(double v) {
    if (v.abs() >= 1e9) return '${(v / 1e9).toStringAsFixed(1)}B';
    if (v.abs() >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
    if (v.abs() >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

class _TTMStat extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;

  const _TTMStat(this.label, this.value, this.theme);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }
}
