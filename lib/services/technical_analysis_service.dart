import 'dart:math' as math;

import '../models/candle.dart';

class TechnicalAnalysisService {
  /// Calculate Exponential Moving Average
  static List<double?> calculateEMA(List<Candle> candles, int period) {
    final ema = <double?>[];
    if (candles.isEmpty) return ema;

    // First EMA is SMA
    double? prevEMA;
    final multiplier = 2.0 / (period + 1);

    for (int i = 0; i < candles.length; i++) {
      if (i < period - 1) {
        ema.add(null);
      } else if (i == period - 1) {
        // Calculate first EMA as SMA
        double sum = 0;
        for (int j = 0; j < period; j++) {
          sum += candles[i - j].close;
        }
        prevEMA = sum / period;
        ema.add(prevEMA);
      } else {
        // EMA = (Close - EMA(previous)) * multiplier + EMA(previous)
        prevEMA = (candles[i].close - prevEMA!) * multiplier + prevEMA;
        ema.add(prevEMA);
      }
    }

    return ema;
  }

  /// Calculate Simple Moving Average
  static List<double?> calculateSMA(List<Candle> candles, int period) {
    final sma = <double?>[];

    for (int i = 0; i < candles.length; i++) {
      if (i < period - 1) {
        sma.add(null); // Not enough data yet
      } else {
        double sum = 0;
        for (int j = 0; j < period; j++) {
          sum += candles[i - j].close;
        }
        sma.add(sum / period);
      }
    }

    return sma;
  }

  /// Calculate Support level (recent low)
  static double calculateSupport(List<Candle> candles, {int lookback = 20}) {
    if (candles.isEmpty) return 0;

    final recentCandles = candles.length > lookback
        ? candles.sublist(candles.length - lookback)
        : candles;

    return recentCandles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
  }

  /// Calculate Resistance level (recent high)
  static double calculateResistance(List<Candle> candles, {int lookback = 20}) {
    if (candles.isEmpty) return 0;

    final recentCandles = candles.length > lookback
        ? candles.sublist(candles.length - lookback)
        : candles;

    return recentCandles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
  }

  /// Calculate Pivot Points
  static Map<String, double> calculatePivotPoints(List<Candle> candles) {
    if (candles.isEmpty) return {};

    final lastCandle = candles.last;
    final pivot = (lastCandle.high + lastCandle.low + lastCandle.close) / 3;

    return {
      'pivot': pivot,
      'r1': 2 * pivot - lastCandle.low,
      'r2': pivot + (lastCandle.high - lastCandle.low),
      's1': 2 * pivot - lastCandle.high,
      's2': pivot - (lastCandle.high - lastCandle.low),
    };
  }

  /// Calculate Bollinger Bands
  static Map<String, List<double?>> calculateBollingerBands(
    List<Candle> candles,
    {int period = 20, double stdDev = 2.0}
  ) {
    final sma = calculateSMA(candles, period);
    final upper = <double?>[];
    final lower = <double?>[];

    for (int i = 0; i < candles.length; i++) {
      if (sma[i] == null) {
        upper.add(null);
        lower.add(null);
      } else {
        // Calculate standard deviation
        double sumSquares = 0;
        for (int j = 0; j < period; j++) {
          final diff = candles[i - j].close - sma[i]!;
          sumSquares += diff * diff;
        }
        final std = math.sqrt(sumSquares / period);

        upper.add(sma[i]! + (stdDev * std));
        lower.add(sma[i]! - (stdDev * std));
      }
    }

    return {
      'upper': upper,
      'middle': sma,
      'lower': lower,
    };
  }

  /// Detect swing highs (potential resistance points)
  static List<int> detectSwingHighs(List<Candle> candles, {int window = 5}) {
    final swingHighs = <int>[];

    for (int i = window; i < candles.length - window; i++) {
      bool isSwingHigh = true;

      // Check if this is the highest point in the window
      for (int j = i - window; j <= i + window; j++) {
        if (j != i && candles[j].high >= candles[i].high) {
          isSwingHigh = false;
          break;
        }
      }

      if (isSwingHigh) {
        swingHighs.add(i);
      }
    }

    return swingHighs;
  }

  /// Detect swing lows (potential support points)
  static List<int> detectSwingLows(List<Candle> candles, {int window = 5}) {
    final swingLows = <int>[];

    for (int i = window; i < candles.length - window; i++) {
      bool isSwingLow = true;

      // Check if this is the lowest point in the window
      for (int j = i - window; j <= i + window; j++) {
        if (j != i && candles[j].low <= candles[i].low) {
          isSwingLow = false;
          break;
        }
      }

      if (isSwingLow) {
        swingLows.add(i);
      }
    }

    return swingLows;
  }

  /// Calculate Fibonacci Retracement Levels
  static Map<String, double> calculateFibonacci(List<Candle> candles) {
    if (candles.isEmpty) return {};

    // Find highest and lowest points
    double highest = candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    double lowest = candles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    double diff = highest - lowest;

    return {
      '0%': highest,
      '23.6%': highest - (diff * 0.236),
      '38.2%': highest - (diff * 0.382),
      '50%': highest - (diff * 0.5),
      '61.8%': highest - (diff * 0.618),
      '78.6%': highest - (diff * 0.786),
      '100%': lowest,
    };
  }

  /// Calculate RSI (Relative Strength Index) historical values.
  ///
  /// Returns a list of the same length as [candles]. The first (period + 1)
  /// entries are null (warmup); subsequent entries are Wilder-smoothed RSI in
  /// the range [0, 100].  Gracefully handles candles with zero/invalid closes.
  static List<double?> calculateRSIHistory(List<Candle> candles, {int period = 14}) {
    if (candles.isEmpty) return [];
    // Need at least period+1 closes to compute one RSI value.
    if (candles.length < period + 1) {
      return List.filled(candles.length, null);
    }

    // Filter out candles with non-positive or NaN closes before differencing.
    final closes = candles.map((c) => c.close).toList();

    final gains  = <double>[];
    final losses = <double>[];
    for (int i = 1; i < closes.length; i++) {
      final prev = closes[i - 1];
      final curr = closes[i];
      // Skip degenerate bars (e.g. zero-price on sparse crypto markets).
      if (prev <= 0 || curr <= 0 || prev.isNaN || curr.isNaN) {
        gains.add(0);
        losses.add(0);
      } else {
        final change = curr - prev;
        gains.add(change > 0 ? change : 0);
        losses.add(change < 0 ? -change : 0);
      }
    }

    // Seed: Wilder's initial average = simple mean of first [period] changes.
    double avgGain = gains.take(period).fold(0.0, (a, b) => a + b) / period;
    double avgLoss = losses.take(period).fold(0.0, (a, b) => a + b) / period;

    final rsi = <double?>[];
    // Null for candle[0] + candles[1..period] = period+1 nulls total.
    for (int i = 0; i <= period; i++) rsi.add(null);

    // Wilder's smoothing for candles[period+1 .. N-1].
    for (int i = period; i < gains.length; i++) {
      avgGain = (avgGain * (period - 1) + gains[i]) / period;
      avgLoss = (avgLoss * (period - 1) + losses[i]) / period;

      if (avgLoss < 1e-10) {
        rsi.add(100.0); // All gains, no losses
      } else {
        final rs = avgGain / avgLoss;
        final value = 100.0 - (100.0 / (1.0 + rs));
        // Clamp to [0, 100] to guard against floating-point edge cases.
        rsi.add(value.clamp(0.0, 100.0));
      }
    }

    return rsi;
  }

  /// Calculate MACD (Moving Average Convergence Divergence) historical values.
  ///
  /// Returns a map with keys 'macd', 'signal', 'histogram', each a list of
  /// the same length as [candles] with nulls at positions that don't yet have
  /// enough warmup data (first slowPeriod + signalPeriod - 2 positions).
  static Map<String, List<double?>> calculateMACDHistory(
    List<Candle> candles,
    {int fastPeriod = 12, int slowPeriod = 26, int signalPeriod = 9}
  ) {
    final _empty = {
      'macd': List<double?>.filled(candles.length, null),
      'signal': List<double?>.filled(candles.length, null),
      'histogram': List<double?>.filled(candles.length, null),
    };
    // Need at least slowPeriod candles for one valid EMA-slow value.
    if (candles.length < slowPeriod) return _empty;

    final emaFast = calculateEMA(candles, fastPeriod);
    final emaSlow = calculateEMA(candles, slowPeriod);

    // Calculate MACD line
    final macdLine = <double?>[];
    for (int i = 0; i < candles.length; i++) {
      if (emaFast[i] == null || emaSlow[i] == null) {
        macdLine.add(null);
      } else {
        macdLine.add(emaFast[i]! - emaSlow[i]!);
      }
    }

    // Calculate signal line (EMA of MACD)
    final signalLine = <double?>[];
    double? prevSignal;
    final multiplier = 2.0 / (signalPeriod + 1);

    int firstValidIndex = -1;
    for (int i = 0; i < macdLine.length; i++) {
      if (macdLine[i] != null) {
        if (firstValidIndex == -1) firstValidIndex = i;

        if (i < firstValidIndex + signalPeriod - 1) {
          signalLine.add(null);
        } else if (i == firstValidIndex + signalPeriod - 1) {
          // First signal is SMA of MACD
          double sum = 0;
          for (int j = 0; j < signalPeriod; j++) {
            sum += macdLine[i - j]!;
          }
          prevSignal = sum / signalPeriod;
          signalLine.add(prevSignal);
        } else {
          // EMA calculation
          prevSignal = (macdLine[i]! - prevSignal!) * multiplier + prevSignal;
          signalLine.add(prevSignal);
        }
      } else {
        signalLine.add(null);
      }
    }

    // Calculate histogram
    final histogram = <double?>[];
    for (int i = 0; i < candles.length; i++) {
      if (macdLine[i] == null || signalLine[i] == null) {
        histogram.add(null);
      } else {
        histogram.add(macdLine[i]! - signalLine[i]!);
      }
    }

    return {
      'macd': macdLine,
      'signal': signalLine,
      'histogram': histogram,
    };
  }

  /// Volume-Weighted Average Price (VWAP).
  /// Resets cumulatively from the first candle in the supplied list.
  /// Returns null where volume is zero.
  static List<double?> calculateVWAP(List<Candle> candles) {
    final result = <double?>[];
    double cumTypicalVol = 0;
    double cumVol = 0;

    for (final c in candles) {
      if (c.volume <= 0) {
        result.add(null);
        continue;
      }
      final typical = (c.high + c.low + c.close) / 3.0;
      cumTypicalVol += typical * c.volume;
      cumVol += c.volume;
      result.add(cumVol > 0 ? cumTypicalVol / cumVol : null);
    }
    return result;
  }

  /// 20-period Simple Moving Average on volume (for volume sub-pane).
  static List<double?> calculateVolumeSMA(List<Candle> candles,
      {int period = 20}) {
    final result = <double?>[];
    for (int i = 0; i < candles.length; i++) {
      if (i < period - 1) {
        result.add(null);
      } else {
        final slice = candles.sublist(i - period + 1, i + 1);
        final avg = slice.fold(0.0, (s, c) => s + c.volume) / period;
        result.add(avg);
      }
    }
    return result;
  }
}
