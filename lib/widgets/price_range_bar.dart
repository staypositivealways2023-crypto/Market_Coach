import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/market_detail.dart';

/// Shows day range and 52-week range bars with current price indicator dot.
class PriceRangeBars extends StatelessWidget {
  final MarketRange range;

  const PriceRangeBars({super.key, required this.range});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (range.dayHigh != null && range.dayLow != null && range.currentPrice != null)
          _RangeRow(
            label: "Day Range",
            low: range.dayLow!,
            high: range.dayHigh!,
            current: range.currentPrice!,
            theme: theme,
          ),
        if (range.yearHigh != null && range.yearLow != null && range.currentPrice != null) ...[
          const SizedBox(height: 14),
          _RangeRow(
            label: "52-Week Range",
            low: range.yearLow!,
            high: range.yearHigh!,
            current: range.currentPrice!,
            theme: theme,
          ),
        ],
        if (range.volume != null || range.open != null || range.previousClose != null) ...[
          const SizedBox(height: 16),
          _StatsRow(range: range, theme: theme),
        ],
      ],
    );
  }
}

class _RangeRow extends StatelessWidget {
  final String label;
  final double low;
  final double high;
  final double current;
  final ThemeData theme;

  const _RangeRow({
    required this.label,
    required this.low,
    required this.high,
    required this.current,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final span = high - low;
    final ratio = span > 0 ? ((current - low) / span).clamp(0.0, 1.0) : 0.5;
    final fmt = _priceFormatter(current);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white54,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(fmt.format(low),
                style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white70, fontSize: 11)),
            const SizedBox(width: 8),
            Expanded(child: _Bar(ratio: ratio)),
            const SizedBox(width: 8),
            Text(fmt.format(high),
                style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white70, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final double ratio; // 0.0–1.0

  const _Bar({required this.ratio});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      const barH = 4.0;
      const dotR = 5.0;

      return SizedBox(
        height: dotR * 2,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            // Track
            Positioned(
              left: 0,
              right: 0,
              top: dotR - barH / 2,
              height: barH,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF4D6A), Color(0xFF00C896)],
                  ),
                ),
              ),
            ),
            // Dot
            Positioned(
              left: (ratio * width - dotR).clamp(0, width - dotR * 2),
              child: Container(
                width: dotR * 2,
                height: dotR * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _StatsRow extends StatelessWidget {
  final MarketRange range;
  final ThemeData theme;

  const _StatsRow({required this.range, required this.theme});

  @override
  Widget build(BuildContext context) {
    final items = <_StatItem>[];
    if (range.open != null) {
      items.add(_StatItem('Open', _priceFormatter(range.open!).format(range.open)));
    }
    if (range.previousClose != null) {
      items.add(_StatItem('Prev Close', _priceFormatter(range.previousClose!).format(range.previousClose)));
    }
    if (range.volume != null) {
      items.add(_StatItem('Volume', _formatVolume(range.volume!)));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Row(
      children: items
          .map((item) => Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white38, fontSize: 10)),
                    const SizedBox(height: 2),
                    Text(item.value,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.87),
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

class _StatItem {
  final String label;
  final String value;
  const _StatItem(this.label, this.value);
}

NumberFormat _priceFormatter(double price) {
  if (price >= 1000) return NumberFormat('#,##0.00');
  if (price >= 1)    return NumberFormat('#,##0.00');
  return NumberFormat('#,##0.0000');
}

String _formatVolume(int v) {
  if (v >= 1000000000) return '${(v / 1000000000).toStringAsFixed(1)}B';
  if (v >= 1000000)    return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000)       return '${(v / 1000).toStringAsFixed(1)}K';
  return v.toString();
}
