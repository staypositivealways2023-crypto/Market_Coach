import 'package:flutter/material.dart';

class IndicatorControls extends StatelessWidget {
  final bool showMovingAverages;
  final bool showBollingerBands;
  final bool showSupport;
  final bool showResistance;
  final Function(bool) onMovingAveragesChanged;
  final Function(bool) onBollingerBandsChanged;
  final Function(bool) onSupportChanged;
  final Function(bool) onResistanceChanged;

  const IndicatorControls({
    super.key,
    required this.showMovingAverages,
    required this.showBollingerBands,
    required this.showSupport,
    required this.showResistance,
    required this.onMovingAveragesChanged,
    required this.onBollingerBandsChanged,
    required this.onSupportChanged,
    required this.onResistanceChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chart Indicators',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _IndicatorChip(
                label: 'Moving Averages',
                icon: Icons.trending_up,
                isActive: showMovingAverages,
                color: const Color(0xFFFFEB3B),
                onChanged: onMovingAveragesChanged,
              ),
              _IndicatorChip(
                label: 'Bollinger Bands',
                icon: Icons.analytics,
                isActive: showBollingerBands,
                color: Colors.blue,
                onChanged: onBollingerBandsChanged,
              ),
              _IndicatorChip(
                label: 'Support',
                icon: Icons.horizontal_rule,
                isActive: showSupport,
                color: Colors.green,
                onChanged: onSupportChanged,
              ),
              _IndicatorChip(
                label: 'Resistance',
                icon: Icons.horizontal_rule,
                isActive: showResistance,
                color: Colors.red,
                onChanged: onResistanceChanged,
              ),
            ],
          ),

          if (showMovingAverages) ...[
            const SizedBox(height: 12),
            _LegendRow(
              items: [
                _LegendItem(color: Color(0xFFFFEB3B), label: 'SMA 20'),
                _LegendItem(color: Color(0xFFFF9800), label: 'SMA 50'),
                _LegendItem(color: Color(0xFFE91E63), label: 'SMA 200'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _IndicatorChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color color;
  final Function(bool) onChanged;

  const _IndicatorChip({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isActive ? Colors.white : color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? Colors.white : Colors.white70,
            ),
          ),
        ],
      ),
      selected: isActive,
      onSelected: onChanged,
      selectedColor: color.withValues(alpha: 0.8),
      backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.5),
      checkmarkColor: Colors.white,
      side: BorderSide(
        color: isActive ? color : color.withValues(alpha: 0.5),
        width: 1,
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final List<_LegendItem> items;

  const _LegendRow({required this.items});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      children: items.map((item) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 2,
              color: item.color,
            ),
            const SizedBox(width: 6),
            Text(
              item.label,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white70,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class _LegendItem {
  final Color color;
  final String label;

  _LegendItem({required this.color, required this.label});
}
