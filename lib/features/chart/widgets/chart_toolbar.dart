import 'package:flutter/material.dart';
import '../../../widgets/chart/chart_type_selector.dart';

class ChartToolbar extends StatelessWidget {
  final ChartType chartType;
  final ValueChanged<ChartType> onChartTypeChanged;
  final VoidCallback onSettingsTap;
  final VoidCallback? onZoomReset;

  const ChartToolbar({
    super.key,
    required this.chartType,
    required this.onChartTypeChanged,
    required this.onSettingsTap,
    this.onZoomReset,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ChartTypeButton(
          chartType: chartType,
          onChanged: onChartTypeChanged,
        ),
        const SizedBox(width: 2),
        if (onZoomReset != null)
          IconButton(
            icon: const Icon(Icons.fit_screen, size: 16, color: Colors.white54),
            onPressed: onZoomReset,
            tooltip: 'Reset zoom',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
          ),
        IconButton(
          icon: const Icon(Icons.tune, size: 18, color: Colors.white54),
          onPressed: onSettingsTap,
          tooltip: 'Indicators',
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(4),
        ),
      ],
    );
  }
}

class _ChartTypeButton extends StatelessWidget {
  final ChartType chartType;
  final ValueChanged<ChartType> onChanged;

  const _ChartTypeButton({required this.chartType, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Explicit cycle: candlestick → line → area → candlestick
        final next = switch (chartType) {
          ChartType.candlestick => ChartType.line,
          ChartType.line => ChartType.area,
          ChartType.area => ChartType.candlestick,
          ChartType.bar => ChartType.candlestick,
        };
        onChanged(next);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_iconFor(chartType), size: 14, color: Colors.white70),
            const SizedBox(width: 4),
            Text(
              _labelFor(chartType),
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(ChartType t) {
    switch (t) {
      case ChartType.candlestick: return Icons.candlestick_chart;
      case ChartType.line: return Icons.show_chart;
      case ChartType.area: return Icons.area_chart;
      case ChartType.bar: return Icons.bar_chart;
    }
  }

  String _labelFor(ChartType t) {
    switch (t) {
      case ChartType.candlestick: return 'Candle';
      case ChartType.line: return 'Line';
      case ChartType.area: return 'Area';
      case ChartType.bar: return 'Bar';
    }
  }
}
