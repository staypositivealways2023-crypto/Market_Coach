/// Stock Selector Widget - Dropdown for selecting symbols
library;

import 'package:flutter/material.dart';
import '../../widgets/glass_card.dart';

class StockSelector extends StatelessWidget {
  final String selectedSymbol;
  final ValueChanged<String> onChanged;

  const StockSelector({
    super.key,
    required this.selectedSymbol,
    required this.onChanged,
  });

  // Common symbols for analysis
  static const List<Map<String, String>> symbols = [
    {'symbol': 'AAPL', 'name': 'Apple'},
    {'symbol': 'TSLA', 'name': 'Tesla'},
    {'symbol': 'NVDA', 'name': 'NVIDIA'},
    {'symbol': 'MSFT', 'name': 'Microsoft'},
    {'symbol': 'GOOGL', 'name': 'Google'},
    {'symbol': 'AMZN', 'name': 'Amazon'},
    {'symbol': 'META', 'name': 'Meta'},
    {'symbol': 'BTC-USD', 'name': 'Bitcoin'},
    {'symbol': 'ETH-USD', 'name': 'Ethereum'},
    {'symbol': 'SPY', 'name': 'S&P 500 ETF'},
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.show_chart, color: colorScheme.primary, size: 20),
          const SizedBox(width: 12),
          Text(
            'Analyze:',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedSymbol,
                onChanged: (newSymbol) {
                  if (newSymbol != null) {
                    onChanged(newSymbol);
                  }
                },
                dropdownColor: const Color(0xFF1E293B),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ),
                icon: Icon(Icons.arrow_drop_down, color: colorScheme.primary),
                isExpanded: true,
                items: symbols.map((item) {
                  final symbol = item['symbol']!;
                  final name = item['name']!;

                  return DropdownMenuItem<String>(
                    value: symbol,
                    child: Row(
                      children: [
                        Text(
                          symbol,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '- $name',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
