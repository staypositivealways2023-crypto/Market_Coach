import '../models/candle.dart';
import '../utils/performance_utils.dart';
import 'technical_analysis_service.dart';

/// Service for recognizing chart patterns and generating educational insights
class PatternRecognitionService {
  /// Detects double top pattern
  static bool detectDoubleTop(List<Candle> candles) {
    if (candles.length < 20) return false;

    final recentCandles = candles.sublist(candles.length - 20);
    final highs = recentCandles.map((c) => c.high).toList();

    // Find two peaks with similar heights
    for (int i = 2; i < highs.length - 2; i++) {
      if (highs[i] > highs[i - 1] &&
          highs[i] > highs[i - 2] &&
          highs[i] > highs[i + 1] &&
          highs[i] > highs[i + 2]) {
        // Found first peak
        for (int j = i + 3; j < highs.length - 2; j++) {
          if (highs[j] > highs[j - 1] &&
              highs[j] > highs[j - 2] &&
              highs[j] > highs[j + 1] &&
              highs[j] > highs[j + 2]) {
            // Found second peak
            final diff = (highs[i] - highs[j]).abs();
            final avgHeight = (highs[i] + highs[j]) / 2;
            if (diff / avgHeight < 0.03) {
              // Peaks are within 3% of each other
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  /// Detects double bottom pattern
  static bool detectDoubleBottom(List<Candle> candles) {
    if (candles.length < 20) return false;

    final recentCandles = candles.sublist(candles.length - 20);
    final lows = recentCandles.map((c) => c.low).toList();

    // Find two troughs with similar depths
    for (int i = 2; i < lows.length - 2; i++) {
      if (lows[i] < lows[i - 1] &&
          lows[i] < lows[i - 2] &&
          lows[i] < lows[i + 1] &&
          lows[i] < lows[i + 2]) {
        // Found first trough
        for (int j = i + 3; j < lows.length - 2; j++) {
          if (lows[j] < lows[j - 1] &&
              lows[j] < lows[j - 2] &&
              lows[j] < lows[j + 1] &&
              lows[j] < lows[j + 2]) {
            // Found second trough
            final diff = (lows[i] - lows[j]).abs();
            final avgDepth = (lows[i] + lows[j]) / 2;
            if (diff / avgDepth < 0.03) {
              // Troughs are within 3% of each other
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  /// Detects if price is approaching support
  static bool isApproachingSupport(List<Candle> candles) {
    if (candles.length < 10) return false;

    final support = TechnicalAnalysisService.calculateSupport(candles);
    final currentPrice = candles.last.close;
    final distance = ((currentPrice - support) / support * 100).abs();

    return distance < 2; // Within 2% of support
  }

  /// Detects if price is approaching resistance
  static bool isApproachingResistance(List<Candle> candles) {
    if (candles.length < 10) return false;

    final resistance = TechnicalAnalysisService.calculateResistance(candles);
    final currentPrice = candles.last.close;
    final distance = ((currentPrice - resistance) / resistance * 100).abs();

    return distance < 2; // Within 2% of resistance
  }

  /// Detects bullish divergence (price makes lower low, RSI makes higher low)
  static bool detectBullishDivergence(List<Candle> candles, List<double?> rsi) {
    if (candles.length < 20 || rsi.length < 20) return false;

    final recentCandles = candles.sublist(candles.length - 20);
    final recentRsi = rsi.sublist(rsi.length - 20);

    // Find last two significant lows
    final priceLows = <int>[];
    for (int i = 2; i < recentCandles.length - 2; i++) {
      if (recentCandles[i].low < recentCandles[i - 1].low &&
          recentCandles[i].low < recentCandles[i - 2].low &&
          recentCandles[i].low < recentCandles[i + 1].low &&
          recentCandles[i].low < recentCandles[i + 2].low) {
        priceLows.add(i);
      }
    }

    if (priceLows.length < 2) return false;

    final lastTwo = priceLows.sublist(priceLows.length - 2);
    final price1 = recentCandles[lastTwo[0]].low;
    final price2 = recentCandles[lastTwo[1]].low;
    final rsi1 = recentRsi[lastTwo[0]];
    final rsi2 = recentRsi[lastTwo[1]];

    if (rsi1 == null || rsi2 == null) return false;

    // Bullish divergence: price lower, RSI higher
    return price2 < price1 && rsi2 > rsi1;
  }

  /// Detects bearish divergence (price makes higher high, RSI makes lower high)
  static bool detectBearishDivergence(List<Candle> candles, List<double?> rsi) {
    if (candles.length < 20 || rsi.length < 20) return false;

    final recentCandles = candles.sublist(candles.length - 20);
    final recentRsi = rsi.sublist(rsi.length - 20);

    // Find last two significant highs
    final priceHighs = <int>[];
    for (int i = 2; i < recentCandles.length - 2; i++) {
      if (recentCandles[i].high > recentCandles[i - 1].high &&
          recentCandles[i].high > recentCandles[i - 2].high &&
          recentCandles[i].high > recentCandles[i + 1].high &&
          recentCandles[i].high > recentCandles[i + 2].high) {
        priceHighs.add(i);
      }
    }

    if (priceHighs.length < 2) return false;

    final lastTwo = priceHighs.sublist(priceHighs.length - 2);
    final price1 = recentCandles[lastTwo[0]].high;
    final price2 = recentCandles[lastTwo[1]].high;
    final rsi1 = recentRsi[lastTwo[0]];
    final rsi2 = recentRsi[lastTwo[1]];

    if (rsi1 == null || rsi2 == null) return false;

    // Bearish divergence: price higher, RSI lower
    return price2 > price1 && rsi2 < rsi1;
  }

  /// Generates educational insights based on current chart state
  /// Results are cached for performance
  static List<MarketInsight> generateInsights(
    List<Candle> candles,
    List<double?> rsi,
    Map<String, List<double?>> macd,
  ) {
    if (candles.isEmpty) return [];

    // Create cache key from candle timestamps
    final cacheKey = 'insights_${candles.last.time.millisecondsSinceEpoch}';

    return PerformanceUtils.cacheComputation(cacheKey, () {
      return _generateInsightsInternal(candles, rsi, macd);
    });
  }

  static List<MarketInsight> _generateInsightsInternal(
    List<Candle> candles,
    List<double?> rsi,
    Map<String, List<double?>> macd,
  ) {
    final insights = <MarketInsight>[];

    final currentRsi = rsi.lastWhere((r) => r != null, orElse: () => null);
    final currentMacdLine = macd['macd']!.lastWhere((m) => m != null, orElse: () => null);
    final currentSignalLine = macd['signal']!.lastWhere((s) => s != null, orElse: () => null);

    // RSI Insights
    if (currentRsi != null) {
      if (currentRsi > 70) {
        insights.add(MarketInsight(
          icon: '🔥',
          title: 'RSI in Overbought Zone',
          description:
              'RSI is above 70, suggesting strong buying pressure. This often precedes a pullback, but strong trends can stay overbought for extended periods.',
          type: InsightType.technical,
          relatedLessonId: 'lesson_support_resistance',
        ));
      } else if (currentRsi < 30) {
        insights.add(MarketInsight(
          icon: '❄️',
          title: 'RSI in Oversold Zone',
          description:
              'RSI is below 30, suggesting strong selling pressure. This often precedes a bounce, but watch for confirmation from price action.',
          type: InsightType.technical,
          relatedLessonId: 'lesson_support_resistance',
        ));
      }
    }

    // MACD Insights
    if (currentMacdLine != null && currentSignalLine != null) {
      if (currentMacdLine > currentSignalLine &&
          macd['macd']![macd['macd']!.length - 2] != null &&
          macd['signal']![macd['signal']!.length - 2] != null &&
          macd['macd']![macd['macd']!.length - 2]! <= macd['signal']![macd['signal']!.length - 2]!) {
        insights.add(MarketInsight(
          icon: '🚀',
          title: 'MACD Bullish Crossover',
          description:
              'MACD line just crossed above the signal line, suggesting potential bullish momentum. This works best when confirmed by increasing volume.',
          type: InsightType.technical,
          relatedLessonId: 'lesson_volatility',
        ));
      } else if (currentMacdLine < currentSignalLine &&
          macd['macd']![macd['macd']!.length - 2] != null &&
          macd['signal']![macd['signal']!.length - 2] != null &&
          macd['macd']![macd['macd']!.length - 2]! >= macd['signal']![macd['signal']!.length - 2]!) {
        insights.add(MarketInsight(
          icon: '📉',
          title: 'MACD Bearish Crossover',
          description:
              'MACD line just crossed below the signal line, suggesting potential bearish momentum. Watch for confirmation from price breaking support.',
          type: InsightType.technical,
          relatedLessonId: 'lesson_volatility',
        ));
      }
    }

    // Pattern Insights
    if (detectDoubleTop(candles)) {
      insights.add(MarketInsight(
        icon: '⚠️',
        title: 'Double Top Pattern Detected',
        description:
            'Price has tested resistance twice and failed to break through. This pattern often signals a potential reversal from uptrend to downtrend.',
        type: InsightType.pattern,
        relatedLessonId: 'lesson_support_resistance',
      ));
    }

    if (detectDoubleBottom(candles)) {
      insights.add(MarketInsight(
        icon: '✅',
        title: 'Double Bottom Pattern Detected',
        description:
            'Price has tested support twice and bounced. This pattern often signals a potential reversal from downtrend to uptrend.',
        type: InsightType.pattern,
        relatedLessonId: 'lesson_support_resistance',
      ));
    }

    // Support/Resistance Insights
    if (isApproachingSupport(candles)) {
      final support = TechnicalAnalysisService.calculateSupport(candles);
      insights.add(MarketInsight(
        icon: '🛡️',
        title: 'Approaching Support Level',
        description:
            'Price is nearing support at \$${support.toStringAsFixed(2)}. Watch for a bounce or break. Breaks on high volume are more significant.',
        type: InsightType.supportResistance,
        relatedLessonId: 'lesson_support_resistance',
      ));
    }

    if (isApproachingResistance(candles)) {
      final resistance = TechnicalAnalysisService.calculateResistance(candles);
      insights.add(MarketInsight(
        icon: '🎯',
        title: 'Approaching Resistance Level',
        description:
            'Price is nearing resistance at \$${resistance.toStringAsFixed(2)}. Watch for rejection or breakout. Volume confirms the move.',
        type: InsightType.supportResistance,
        relatedLessonId: 'lesson_support_resistance',
      ));
    }

    // Divergence Insights
    if (detectBullishDivergence(candles, rsi)) {
      insights.add(MarketInsight(
        icon: '🔄',
        title: 'Bullish Divergence Detected',
        description:
            'Price made a lower low, but RSI made a higher low. This divergence often signals weakening selling pressure and potential reversal.',
        type: InsightType.divergence,
        relatedLessonId: 'lesson_volatility',
      ));
    }

    if (detectBearishDivergence(candles, rsi)) {
      insights.add(MarketInsight(
        icon: '🔄',
        title: 'Bearish Divergence Detected',
        description:
            'Price made a higher high, but RSI made a lower high. This divergence often signals weakening buying pressure and potential reversal.',
        type: InsightType.divergence,
        relatedLessonId: 'lesson_volatility',
      ));
    }

    return insights;
  }
}

/// Represents a market insight
class MarketInsight {
  final String icon;
  final String title;
  final String description;
  final InsightType type;
  final String? relatedLessonId;

  MarketInsight({
    required this.icon,
    required this.title,
    required this.description,
    required this.type,
    this.relatedLessonId,
  });
}

enum InsightType {
  technical,
  pattern,
  supportResistance,
  divergence,
}
