import 'package:flutter/material.dart';
import 'glass_card.dart';

/// Educational content for technical indicators and chart features
class EducationalContent {
  static const rsi = {
    'title': 'RSI - Relative Strength Index',
    'icon': '📊',
    'summary': 'Measures momentum by comparing recent gains to recent losses',
    'sections': [
      {
        'heading': 'What is RSI?',
        'content':
            'RSI measures the speed and magnitude of price changes. It oscillates between 0 and 100, helping you identify overbought or oversold conditions.',
      },
      {
        'heading': 'How to Read It',
        'bullets': [
          'RSI > 70: Often means "overbought" - price may pull back',
          'RSI < 30: Often means "oversold" - price may bounce',
          'RSI 40-60: Neutral zone - no extreme pressure',
          'Divergence: RSI moves opposite to price (potential reversal)',
        ],
      },
      {
        'heading': 'Educational Perspective',
        'content':
            'RSI is not a buy/sell signal. It\'s a tool to understand market momentum. High RSI doesn\'t always mean "sell" - strong trends can stay overbought for extended periods.',
      },
    ],
  };

  static const macd = {
    'title': 'MACD - Moving Average Convergence Divergence',
    'icon': '📈',
    'summary': 'Shows relationship between two moving averages of price',
    'sections': [
      {
        'heading': 'What is MACD?',
        'content':
            'MACD compares a fast EMA (12) to a slow EMA (26), then adds a signal line (9-day EMA of MACD). The histogram shows the difference between MACD and signal.',
      },
      {
        'heading': 'How to Read It',
        'bullets': [
          'MACD crosses above Signal: Potential bullish momentum',
          'MACD crosses below Signal: Potential bearish momentum',
          'Histogram expanding: Momentum accelerating',
          'Histogram shrinking: Momentum slowing',
          'Zero line crossover: Change in trend direction',
        ],
      },
      {
        'heading': 'Educational Perspective',
        'content':
            'MACD works best in trending markets. In choppy, sideways markets, it can produce many false signals. Always confirm with price action and volume.',
      },
    ],
  };

  static const chartTypes = {
    'title': 'Chart Types Guide',
    'icon': '📊',
    'summary': 'Different ways to visualize price action',
    'sections': [
      {
        'heading': 'Candlestick',
        'content':
            'Shows open, high, low, close (OHLC) in each period. Green candles = close > open (bullish). Red candles = close < open (bearish). Best for detailed price action analysis.',
      },
      {
        'heading': 'Line',
        'content':
            'Connects closing prices. Cleanest view, great for seeing overall trend without noise. Best for beginners or long-term analysis.',
      },
      {
        'heading': 'Area',
        'content':
            'Line chart with filled area below. Visually emphasizes trend direction. Good for presentations or quick trend identification.',
      },
      {
        'heading': 'Bar',
        'content':
            'Similar to candlestick but without filled body. Shows OHLC with vertical line (high-low) and ticks (open-close). Traditional chart type.',
      },
    ],
  };

  static const supportResistance = {
    'title': 'Support & Resistance',
    'icon': '🎯',
    'summary': 'Key price levels where buyers and sellers often react',
    'sections': [
      {
        'heading': 'What are Support & Resistance?',
        'content':
            'Support is a price "floor" where buying pressure tends to emerge. Resistance is a "ceiling" where selling pressure appears. Think of them as psychological barriers.',
      },
      {
        'heading': 'Types of S/R',
        'bullets': [
          'Simple S/R: Recent highs and lows in the data',
          'Pivot Points: Calculated levels based on previous period',
          'Fibonacci: Retracement levels from recent swing high/low',
        ],
      },
      {
        'heading': 'How to Use Them',
        'content':
            'Watch how price reacts at these levels. Bounces confirm the level. Breaks through on volume may signal a new trend. S/R levels become stronger when tested multiple times.',
      },
    ],
  };

  static const movingAverages = {
    'title': 'Moving Averages',
    'icon': '〰️',
    'summary': 'Smoothed trend lines showing average price over time',
    'sections': [
      {
        'heading': 'What are Moving Averages?',
        'content':
            'MAs smooth out price noise by averaging prices over a period. They help identify trend direction and potential support/resistance.',
      },
      {
        'heading': 'Types',
        'bullets': [
          'SMA (Simple): Equal weight to all prices',
          'EMA (Exponential): More weight to recent prices, faster response',
          'Common periods: 20 (short), 50 (medium), 200 (long-term)',
        ],
      },
      {
        'heading': 'How to Read Them',
        'content':
            'Price above MA = bullish bias. Price below MA = bearish bias. MA crossovers (fast crosses slow) suggest momentum shifts. Multiple MAs together show trend strength.',
      },
    ],
  };

  static const bollingerBands = {
    'title': 'Bollinger Bands',
    'icon': '📉',
    'summary': 'Volatility bands around a moving average',
    'sections': [
      {
        'heading': 'What are Bollinger Bands?',
        'content':
            'Three lines: middle (20 SMA), upper (+2 standard deviations), lower (-2 std dev). Bands expand during volatility, contract during consolidation.',
      },
      {
        'heading': 'How to Read Them',
        'bullets': [
          'Price near upper band: Potentially overbought (but not always)',
          'Price near lower band: Potentially oversold (but not always)',
          'Bands squeezing: Low volatility, potential breakout coming',
          'Bands expanding: High volatility, momentum in play',
          'Bollinger Bounce: Price bounces between bands in range',
        ],
      },
      {
        'heading': 'Educational Perspective',
        'content':
            'Bollinger Bands measure volatility, not direction. Strong trends often "walk the band" - staying near upper band in uptrend or lower band in downtrend.',
      },
    ],
  };
}

/// Shows educational content in a bottom sheet
class EducationalBottomSheet extends StatelessWidget {
  final Map<String, dynamic> content;

  const EducationalBottomSheet({
    super.key,
    required this.content,
  });

  static void show(BuildContext context, Map<String, dynamic> content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EducationalBottomSheet(content: content),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = content['sections'] as List<Map<String, dynamic>>;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Text(
                      content['icon'] as String,
                      style: const TextStyle(fontSize: 32),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            content['title'] as String,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            content['summary'] as String,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Content
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  itemCount: sections.length + 1, // +1 for disclaimer
                  itemBuilder: (context, index) {
                    if (index == sections.length) {
                      // Disclaimer at bottom
                      return Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: GlassCard(
                          color: Colors.orange.withValues(alpha: 0.1),
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.school_outlined,
                                color: Colors.orangeAccent,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Educational content only. Not financial advice.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final section = sections[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _buildSection(context, section),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSection(BuildContext context, Map<String, dynamic> section) {
    final theme = Theme.of(context);
    final heading = section['heading'] as String?;
    final content = section['content'] as String?;
    final bullets = section['bullets'] as List<String>?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (heading != null) ...[
          Text(
            heading,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (content != null)
          Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
              height: 1.6,
            ),
          ),
        if (bullets != null) ...[
          const SizedBox(height: 8),
          ...bullets.map((bullet) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        bullet,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ],
    );
  }
}

/// Quick coaching tip widget for inline help
class CoachingTip extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color? color;

  const CoachingTip({
    super.key,
    required this.message,
    this.icon = Icons.lightbulb_outline,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.primary;

    return GlassCard(
      color: effectiveColor.withValues(alpha: 0.1),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon, color: effectiveColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
