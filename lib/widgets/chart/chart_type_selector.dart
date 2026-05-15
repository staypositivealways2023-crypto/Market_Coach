import 'package:flutter/material.dart';

enum ChartType { line, candlestick, bar, area }

class ChartTypeSelector extends StatelessWidget {
  final ChartType selectedType;
  final Function(ChartType) onChanged;

  const ChartTypeSelector({
    super.key,
    required this.selectedType,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ChartTypeButton(
            icon: Icons.show_chart,
            label: 'Line',
            isSelected: selectedType == ChartType.line,
            onTap: () => onChanged(ChartType.line),
          ),
          const SizedBox(width: 4),
          _ChartTypeButton(
            icon: Icons.candlestick_chart,
            label: 'Candle',
            isSelected: selectedType == ChartType.candlestick,
            onTap: () => onChanged(ChartType.candlestick),
          ),
          const SizedBox(width: 4),
          _ChartTypeButton(
            icon: Icons.bar_chart,
            label: 'Bar',
            isSelected: selectedType == ChartType.bar,
            onTap: () => onChanged(ChartType.bar),
          ),
          const SizedBox(width: 4),
          _ChartTypeButton(
            icon: Icons.area_chart,
            label: 'Area',
            isSelected: selectedType == ChartType.area,
            onTap: () => onChanged(ChartType.area),
          ),
        ],
      ),
    );
  }
}

class _ChartTypeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ChartTypeButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: isSelected
          ? theme.colorScheme.primary
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
