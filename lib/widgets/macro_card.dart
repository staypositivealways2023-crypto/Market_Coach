import 'package:flutter/material.dart';

import '../models/market_detail.dart';
import '../models/signal_analysis.dart';
import 'glass_card.dart';

/// MacroCard — shows FRED macro indicators + correlation macro_flags.
/// Accepts either raw [MacroOverview] data (for the number tiles)
/// or [CorrelationResult.macroFlags] (plain-English flags from the engine).
class MacroCard extends StatelessWidget {
  final MacroOverview? macro;
  final List<String> macroFlags;

  const MacroCard({
    super.key,
    this.macro,
    this.macroFlags = const [],
  });

  @override
  Widget build(BuildContext context) {
    final hasTiles = macro != null;
    final hasFlags = macroFlags.isNotEmpty;

    if (!hasTiles && !hasFlags) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.public,
                  color: theme.colorScheme.primary, size: 18),
              const SizedBox(width: 8),
              Text('Macro Environment',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),

          if (hasTiles) ...[
            const SizedBox(height: 16),
            _buildTilesRow(context, macro!),
          ],

          if (hasFlags) ...[
            if (hasTiles) ...[
              const SizedBox(height: 14),
              const Divider(color: Colors.white12),
              const SizedBox(height: 10),
            ] else
              const SizedBox(height: 16),
            Text('Market Context',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.white38, fontSize: 10)),
            const SizedBox(height: 8),
            ...macroFlags.map((flag) => _FlagRow(flag: flag)),
          ],
        ],
      ),
    );
  }

  Widget _buildTilesRow(BuildContext context, MacroOverview m) {
    return Row(
      children: [
        Expanded(child: _MacroTile(
          label: 'Fed Rate',
          value: m.fedFundsRate.value != null
              ? '${m.fedFundsRate.value!.toStringAsFixed(2)}%'
              : '--',
          badge: _fedBadge(m.fedFundsRate.value),
        )),
        const SizedBox(width: 8),
        Expanded(child: _MacroTile(
          label: 'Yield Curve',
          value: m.yieldCurve.value != null
              ? '${m.yieldCurve.value! >= 0 ? '+' : ''}${m.yieldCurve.value!.toStringAsFixed(2)}%'
              : '--',
          badge: _yieldBadge(m.yieldCurve.value),
        )),
        const SizedBox(width: 8),
        Expanded(child: _MacroTile(
          label: 'DXY',
          value: m.dxy.value != null
              ? m.dxy.value!.toStringAsFixed(1)
              : '--',
          badge: _dxyBadge(m.dxy.value),
        )),
        const SizedBox(width: 8),
        Expanded(child: _MacroTile(
          label: 'Inflation',
          value: m.inflationYoy.value != null
              ? '${m.inflationYoy.value!.toStringAsFixed(1)}%'
              : '--',
          badge: _inflationBadge(m.inflationYoy.value),
        )),
      ],
    );
  }

  _BadgeSpec _fedBadge(double? v) {
    if (v == null) return const _BadgeSpec('--', Colors.white38);
    if (v >= 5.0) return const _BadgeSpec('HIGH', Color(0xFFFF4D6A));
    if (v >= 3.0) return const _BadgeSpec('MODERATE', Color(0xFFFFB300));
    return const _BadgeSpec('LOW', Color(0xFF00C896));
  }

  _BadgeSpec _yieldBadge(double? v) {
    if (v == null) return const _BadgeSpec('--', Colors.white38);
    if (v < -0.5) return const _BadgeSpec('INVERTED', Color(0xFFFF4D6A));
    if (v < 0) return const _BadgeSpec('FLAT', Color(0xFFFFB300));
    if (v < 0.5) return const _BadgeSpec('FLAT', Color(0xFFFFB300));
    return const _BadgeSpec('NORMAL', Color(0xFF00C896));
  }

  _BadgeSpec _dxyBadge(double? v) {
    if (v == null) return const _BadgeSpec('--', Colors.white38);
    if (v >= 108) return const _BadgeSpec('STRONG', Color(0xFFFF4D6A));
    if (v >= 104) return const _BadgeSpec('FIRM', Color(0xFFFFB300));
    if (v <= 96)  return const _BadgeSpec('WEAK', Color(0xFF00C896));
    return const _BadgeSpec('NEUTRAL', Colors.white54);
  }

  _BadgeSpec _inflationBadge(double? v) {
    if (v == null) return const _BadgeSpec('--', Colors.white38);
    if (v >= 5.0) return const _BadgeSpec('HIGH', Color(0xFFFF4D6A));
    if (v >= 3.5) return const _BadgeSpec('ELEVATED', Color(0xFFFFB300));
    if (v >= 2.0) return const _BadgeSpec('TARGET', Color(0xFF00C896));
    return const _BadgeSpec('LOW', Colors.white54);
  }
}

class _BadgeSpec {
  final String label;
  final Color color;
  const _BadgeSpec(this.label, this.color);
}

class _MacroTile extends StatelessWidget {
  final String label;
  final String value;
  final _BadgeSpec badge;

  const _MacroTile({
    required this.label,
    required this.value,
    required this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.white38, fontSize: 9)),
          const SizedBox(height: 4),
          Text(value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              )),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: badge.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: badge.color.withValues(alpha: 0.4)),
            ),
            child: Text(badge.label,
                style: TextStyle(
                  color: badge.color,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                )),
          ),
        ],
      ),
    );
  }
}

class _FlagRow extends StatelessWidget {
  final String flag;
  const _FlagRow({required this.flag});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Determine flag severity from first word
    Color dotColor = Colors.white38;
    if (flag.toLowerCase().contains('inverted') ||
        flag.toLowerCase().contains('contrac') ||
        flag.toLowerCase().contains('high') ||
        flag.toLowerCase().contains('strong dollar') ||
        flag.toLowerCase().contains('deep')) {
      dotColor = const Color(0xFFFF4D6A);
    } else if (flag.toLowerCase().contains('elevated') ||
        flag.toLowerCase().contains('firm') ||
        flag.toLowerCase().contains('flat') ||
        flag.toLowerCase().contains('sluggish')) {
      dotColor = const Color(0xFFFFB300);
    } else if (flag.toLowerCase().contains('tailwind') ||
        flag.toLowerCase().contains('weak dollar')) {
      dotColor = const Color(0xFF00C896);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(flag,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                  fontSize: 11,
                  height: 1.4,
                )),
          ),
        ],
      ),
    );
  }
}
