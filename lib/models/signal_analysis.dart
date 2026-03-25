// Signal Engine response from /api/analyse/{symbol}
// Mirrors python-backend/app/models/signals.py

/// Maps raw backend signal labels to user-facing display strings.
/// Raw values (STRONG_BUY etc.) stay untouched for color-matching logic.
String signalDisplayLabel(String raw) {
  switch (raw.toUpperCase()) {
    case 'STRONG_BUY':  return 'Bullish signal (high confidence)';
    case 'BUY':         return 'Bullish signal';
    case 'STRONG_SELL': return 'Bearish signal (high confidence)';
    case 'SELL':        return 'Bearish signal';
    default:            return 'Neutral';
  }
}

class SignalAnalysis {
  final String symbol;
  final String interval;
  final ComputedSignals signals;
  final PredictionResult? prediction;
  final CorrelationResult? correlation;
  final PatternScanResult? patterns;
  final String analysis;
  final String timestamp;
  final bool isCached;
  final int tokensUsed;

  const SignalAnalysis({
    required this.symbol,
    required this.interval,
    required this.signals,
    this.prediction,
    this.correlation,
    this.patterns,
    required this.analysis,
    required this.timestamp,
    this.isCached = false,
    this.tokensUsed = 0,
  });

  factory SignalAnalysis.fromJson(Map<String, dynamic> json) {
    return SignalAnalysis(
      symbol:      json['symbol'] as String,
      interval:    json['interval'] as String,
      signals:     ComputedSignals.fromJson(json['signals'] as Map<String, dynamic>),
      prediction:  json['prediction'] != null
          ? PredictionResult.fromJson(json['prediction'] as Map<String, dynamic>)
          : null,
      correlation: json['correlation'] != null
          ? CorrelationResult.fromJson(json['correlation'] as Map<String, dynamic>)
          : null,
      patterns:    json['patterns'] != null
          ? PatternScanResult.fromJson(json['patterns'] as Map<String, dynamic>)
          : null,
      analysis:    json['analysis'] as String,
      timestamp:   json['timestamp'] as String,
      isCached:    json['is_cached'] as bool? ?? false,
      tokensUsed:  json['tokens_used'] as int? ?? 0,
    );
  }

  String get signalLabel => signals.signalLabel;
  double get compositeScore => signals.compositeScore;
}

// ── Phase 5: Correlation Result ───────────────────────────────────────────────

class CorrelationResult {
  final double newsSentimentScore;
  final String sentimentLabel;
  final List<String> topHeadlines;
  final List<String> highImpactFlags;
  final String priceDirection;
  final String scenario;
  final String scenarioLabel;
  final String scenarioDescription;
  final int? fundamentalScore;
  final String? fundamentalGrade;
  final List<String> fundamentalSignals;
  final List<String> macroFlags;

  const CorrelationResult({
    required this.newsSentimentScore,
    required this.sentimentLabel,
    required this.topHeadlines,
    required this.highImpactFlags,
    required this.priceDirection,
    required this.scenario,
    required this.scenarioLabel,
    required this.scenarioDescription,
    this.fundamentalScore,
    this.fundamentalGrade,
    this.fundamentalSignals = const [],
    this.macroFlags = const [],
  });

  factory CorrelationResult.fromJson(Map<String, dynamic> json) {
    return CorrelationResult(
      newsSentimentScore: (json['news_sentiment_score'] as num).toDouble(),
      sentimentLabel:     json['sentiment_label'] as String,
      topHeadlines:       (json['top_headlines'] as List<dynamic>).cast<String>(),
      highImpactFlags:    (json['high_impact_flags'] as List<dynamic>).cast<String>(),
      priceDirection:     json['price_direction'] as String,
      scenario:           json['scenario'] as String,
      scenarioLabel:      json['scenario_label'] as String,
      scenarioDescription: json['scenario_description'] as String,
      fundamentalScore:   json['fundamental_score'] as int?,
      fundamentalGrade:   json['fundamental_grade'] as String?,
      fundamentalSignals: json['fundamental_signals'] != null
          ? (json['fundamental_signals'] as List<dynamic>).cast<String>()
          : [],
      macroFlags: json['macro_flags'] != null
          ? (json['macro_flags'] as List<dynamic>).cast<String>()
          : [],
    );
  }
}

class ComputedSignals {
  final CandlestickSignal candlestick;
  final IndicatorSignals indicators;
  final double compositeScore;
  final String signalLabel; // STRONG_BUY | BUY | NEUTRAL | SELL | STRONG_SELL

  const ComputedSignals({
    required this.candlestick,
    required this.indicators,
    required this.compositeScore,
    required this.signalLabel,
  });

  factory ComputedSignals.fromJson(Map<String, dynamic> json) {
    return ComputedSignals(
      candlestick:    CandlestickSignal.fromJson(json['candlestick'] as Map<String, dynamic>),
      indicators:     IndicatorSignals.fromJson(json['indicators'] as Map<String, dynamic>),
      compositeScore: (json['composite_score'] as num).toDouble(),
      signalLabel:    json['signal_label'] as String,
    );
  }
}

class CandlestickSignal {
  final String? pattern;
  final String signal;      // BULLISH | BEARISH | NEUTRAL
  final double confidence;  // 0.0 – 1.0

  const CandlestickSignal({
    this.pattern,
    required this.signal,
    required this.confidence,
  });

  factory CandlestickSignal.fromJson(Map<String, dynamic> json) {
    return CandlestickSignal(
      pattern:    json['pattern'] as String?,
      signal:     json['signal'] as String? ?? 'NEUTRAL',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class IndicatorSignals {
  final double? rsiValue;
  final String rsiSignal;    // OVERSOLD | NEUTRAL | OVERBOUGHT
  final String macdSignal;   // BULLISH | BEARISH | BULLISH_CROSS | BEARISH_CROSS | NEUTRAL
  final double? macdHistogram;
  final String emaStack;     // PRICE_ABOVE_ALL | PRICE_ABOVE_20_50 | MIXED | PRICE_BELOW_ALL …
  final String volume;       // ABOVE_AVERAGE | AVERAGE | BELOW_AVERAGE
  final String bbPosition;   // ABOVE_UPPER | UPPER | MIDDLE | LOWER | BELOW_LOWER

  const IndicatorSignals({
    this.rsiValue,
    required this.rsiSignal,
    required this.macdSignal,
    this.macdHistogram,
    required this.emaStack,
    required this.volume,
    required this.bbPosition,
  });

  factory IndicatorSignals.fromJson(Map<String, dynamic> json) {
    return IndicatorSignals(
      rsiValue:      (json['rsi_value'] as num?)?.toDouble(),
      rsiSignal:     json['rsi_signal'] as String? ?? 'NEUTRAL',
      macdSignal:    json['macd_signal'] as String? ?? 'NEUTRAL',
      macdHistogram: (json['macd_histogram'] as num?)?.toDouble(),
      emaStack:      json['ema_stack'] as String? ?? 'MIXED',
      volume:        json['volume'] as String? ?? 'AVERAGE',
      bbPosition:    json['bb_position'] as String? ?? 'MIDDLE',
    );
  }
}

// ── Prediction Engine result (Phase 4) ──────────────────────────────────────

class PredictionResult {
  final String direction;         // BULLISH | BEARISH | NEUTRAL
  final double probability;       // 0.50 – 0.85
  final String horizon;           // "5 trading days"
  final double priceCurrent;
  final double priceTargetBase;   // central projection
  final double priceTargetHigh;   // bull case
  final double priceTargetLow;    // bear case
  final double expectedReturnPct;
  final double riskRewardRatio;
  final double stopLossSuggestion;
  final String modelConsensus;
  final double atr14;

  const PredictionResult({
    required this.direction,
    required this.probability,
    required this.horizon,
    required this.priceCurrent,
    required this.priceTargetBase,
    required this.priceTargetHigh,
    required this.priceTargetLow,
    required this.expectedReturnPct,
    required this.riskRewardRatio,
    required this.stopLossSuggestion,
    required this.modelConsensus,
    required this.atr14,
  });

  factory PredictionResult.fromJson(Map<String, dynamic> json) {
    return PredictionResult(
      direction:          json['direction'] as String,
      probability:        (json['probability'] as num).toDouble(),
      horizon:            json['horizon'] as String,
      priceCurrent:       (json['price_current'] as num).toDouble(),
      priceTargetBase:    (json['price_target_base'] as num).toDouble(),
      priceTargetHigh:    (json['price_target_high'] as num).toDouble(),
      priceTargetLow:     (json['price_target_low'] as num).toDouble(),
      expectedReturnPct:  (json['expected_return_pct'] as num).toDouble(),
      riskRewardRatio:    (json['risk_reward_ratio'] as num).toDouble(),
      stopLossSuggestion: (json['stop_loss_suggestion'] as num).toDouble(),
      modelConsensus:     json['model_consensus'] as String,
      atr14:              (json['atr_14'] as num).toDouble(),
    );
  }
}

// ── Phase 6: Chart Patterns ───────────────────────────────────────────────────

class ChartPatternResult {
  final String type;
  final String signal;
  final double confidence;
  final String description;
  final double? keyPrice;
  final int formedAtIndex;

  const ChartPatternResult({
    required this.type,
    required this.signal,
    required this.confidence,
    required this.description,
    this.keyPrice,
    this.formedAtIndex = -1,
  });

  factory ChartPatternResult.fromJson(Map<String, dynamic> json) {
    return ChartPatternResult(
      type:          json['type'] as String,
      signal:        json['signal'] as String,
      confidence:    (json['confidence'] as num).toDouble(),
      description:   json['description'] as String,
      keyPrice:      (json['key_price'] as num?)?.toDouble(),
      formedAtIndex: json['formed_at_index'] as int? ?? -1,
    );
  }

  String get displayName => type
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

class SupportResistanceLevel {
  final double price;
  final String type;   // SUPPORT | RESISTANCE
  final int strength;
  final String description;

  const SupportResistanceLevel({
    required this.price,
    required this.type,
    required this.strength,
    required this.description,
  });

  factory SupportResistanceLevel.fromJson(Map<String, dynamic> json) {
    return SupportResistanceLevel(
      price:       (json['price'] as num).toDouble(),
      type:        json['type'] as String,
      strength:    json['strength'] as int,
      description: json['description'] as String,
    );
  }
}

class PatternScanResult {
  final List<ChartPatternResult> patterns;
  final List<SupportResistanceLevel> supportResistance;
  final String trend;
  final String trendStrength;

  const PatternScanResult({
    this.patterns = const [],
    this.supportResistance = const [],
    this.trend = 'SIDEWAYS',
    this.trendStrength = 'WEAK',
  });

  factory PatternScanResult.fromJson(Map<String, dynamic> json) {
    return PatternScanResult(
      patterns: (json['patterns'] as List<dynamic>? ?? [])
          .map((p) => ChartPatternResult.fromJson(p as Map<String, dynamic>))
          .toList(),
      supportResistance: (json['support_resistance'] as List<dynamic>? ?? [])
          .map((s) => SupportResistanceLevel.fromJson(s as Map<String, dynamic>))
          .toList(),
      trend:         json['trend'] as String? ?? 'SIDEWAYS',
      trendStrength: json['trend_strength'] as String? ?? 'WEAK',
    );
  }
}
