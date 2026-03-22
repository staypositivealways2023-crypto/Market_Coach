import 'package:flutter/material.dart';

class TimeframeSelector extends StatelessWidget {
  final String selectedTimeframe;
  final ValueChanged<String> onChanged;
  final bool isCrypto;

  const TimeframeSelector({
    super.key,
    required this.selectedTimeframe,
    required this.onChanged,
    this.isCrypto = false,
  });

  static const _timeframes = [
    '1m', '5m', '15m', '30m',
    '1h', '2h', '4h', '12h',
    '1D', '1W', '4W',
    '1M', '3M', '6M', '1Y', '5Y',
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _timeframes.map((tf) {
          final isSelected = tf == selectedTimeframe;
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: GestureDetector(
              onTap: () => onChanged(tf),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF12A28C) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF12A28C) : Colors.white12,
                  ),
                ),
                child: Text(
                  tf,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white54,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
