import 'package:flutter/material.dart';
import 'demo_models.dart';

// ─── Sealed step hierarchy ────────────────────────────────────────────────────
// Every screen in the guided lesson engine is one of these step types.
// The Dart 3 sealed class guarantees exhaustive switch at compile time.

sealed class LessonStep {
  const LessonStep();
}

// ─── Intro ────────────────────────────────────────────────────────────────────
final class IntroStep extends LessonStep {
  final String title;
  final String subtitle;
  final Color accentColor;

  const IntroStep({
    required this.title,
    required this.subtitle,
    this.accentColor = const Color(0xFF12A28C),
  });
}

// ─── Theory ───────────────────────────────────────────────────────────────────
final class TheoryStep extends LessonStep {
  final String badge;      // short uppercase label, e.g. "CONCEPT"
  final String title;
  final String body;
  final String? callout;   // highlighted insight box below the body
  final Color? accentColor;

  const TheoryStep({
    required this.badge,
    required this.title,
    required this.body,
    this.callout,
    this.accentColor,
  });
}

// ─── Visual explainer ─────────────────────────────────────────────────────────
// Renders a fixed RSI spectrum bar visual with animated annotation.
final class VisualExplainerStep extends LessonStep {
  final String title;
  final String explanation;

  const VisualExplainerStep({
    required this.title,
    required this.explanation,
  });
}

// ─── Chart highlight ──────────────────────────────────────────────────────────
// Shows a mini RSI chart with a zone highlighted and description.
final class ChartHighlightStep extends LessonStep {
  final String title;
  final String description;
  final List<double> rsiData;      // 0–100 values
  final bool highlightOverbought;
  final bool highlightOversold;

  const ChartHighlightStep({
    required this.title,
    required this.description,
    required this.rsiData,
    this.highlightOverbought = false,
    this.highlightOversold = false,
  });
}

// ─── Tap to identify ──────────────────────────────────────────────────────────
// User taps the correct zone on an interactive RSI gauge.
// targetZone: 'overbought' | 'oversold' | 'neutral'
final class TapToIdentifyStep extends LessonStep {
  final String instruction;
  final String targetZone;
  final String successMessage;

  const TapToIdentifyStep({
    required this.instruction,
    required this.targetZone,
    required this.successMessage,
  });
}

// ─── Multiple choice ──────────────────────────────────────────────────────────
final class MultipleChoiceStep extends LessonStep {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const MultipleChoiceStep({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });
}

// ─── Compare examples ─────────────────────────────────────────────────────────
final class CompareCard {
  final String label;
  final double rsiValue;
  final String scenario;
  final String interpretation;
  final Color color;

  const CompareCard({
    required this.label,
    required this.rsiValue,
    required this.scenario,
    required this.interpretation,
    required this.color,
  });
}

final class CompareExamplesStep extends LessonStep {
  final String instruction;
  final CompareCard left;
  final CompareCard right;

  const CompareExamplesStep({
    required this.instruction,
    required this.left,
    required this.right,
  });
}

// ─── Recap ────────────────────────────────────────────────────────────────────
final class RecapStep extends LessonStep {
  final String title;
  final List<String> points;

  const RecapStep({required this.title, required this.points});
}

// ─── Completion ───────────────────────────────────────────────────────────────
final class CompletionStep extends LessonStep {
  final String title;
  final String message;
  final int xpEarned;
  final String ctaLabel;
  final String ctaTicker;
  final String ctaTickerName;
  final bool ctaIsCrypto;
  final bool ctaShowRSI;
  final bool ctaShowMACD;

  const CompletionStep({
    required this.title,
    required this.message,
    this.xpEarned = 50,
    required this.ctaLabel,
    required this.ctaTicker,
    required this.ctaTickerName,
    this.ctaIsCrypto = false,
    this.ctaShowRSI = false,
    this.ctaShowMACD = false,
  });
}

// ─── ST-1: CandlestickDemoStep ────────────────────────────────────────────────
// Shows a mini candlestick chart with optional S/R lines and labelled arrows.
// Read-only / passive.
final class CandlestickDemoStep extends LessonStep {
  final String title;
  final String description;
  final List<DemoCandle> candles;
  final List<CandleAnnotation> annotations;
  final bool highlightBullish;
  final bool highlightBearish;
  final double? supportLevel;
  final double? resistanceLevel;

  const CandlestickDemoStep({
    required this.title,
    required this.description,
    required this.candles,
    this.annotations = const [],
    this.highlightBullish = false,
    this.highlightBearish = false,
    this.supportLevel,
    this.resistanceLevel,
  });
}

// ─── ST-2: IndicatorDemoStep ──────────────────────────────────────────────────
// Shows a price line + one indicator overlay (MA, MACD, Bollinger). Read-only.
final class IndicatorDemoStep extends LessonStep {
  final String title;
  final String description;
  final IndicatorDemoType demoType;
  final List<double> priceData;
  final List<double>? line1;        // MA fast / MACD line / Bollinger upper
  final List<double>? line2;        // MA slow / Signal line / Bollinger lower
  final List<double>? line3;        // Bollinger mid
  final List<double>? histogram;    // MACD histogram bars
  final List<IndicatorAnnotation> annotations;

  const IndicatorDemoStep({
    required this.title,
    required this.description,
    required this.demoType,
    required this.priceData,
    this.line1,
    this.line2,
    this.line3,
    this.histogram,
    this.annotations = const [],
  });
}

// ─── ST-3: TapOnChartStep ─────────────────────────────────────────────────────
// User taps a specific candle. Shake + red on wrong, green on correct.
// Annotations are revealed after success.
final class TapOnChartStep extends LessonStep {
  final String instruction;
  final List<DemoCandle> candles;
  final int correctIndex;
  final String targetLabel;
  final String successMessage;
  final List<CandleAnnotation> revealAnnotations;

  const TapOnChartStep({
    required this.instruction,
    required this.candles,
    required this.correctIndex,
    required this.targetLabel,
    required this.successMessage,
    this.revealAnnotations = const [],
  });
}

// ─── ST-4: RangeSliderQuizStep ────────────────────────────────────────────────
// User drags a slider on a labelled 0–100 spectrum. Submit reveals correct zone.
final class RangeSliderQuizStep extends LessonStep {
  final String instruction;
  final String scaleLabel;       // e.g. "Risk/Reward Ratio"
  final double scaleMin;
  final double scaleMax;
  final double correctMin;
  final double correctMax;
  final String successMessage;
  final String hintMessage;
  final List<RangeZone> zones;

  const RangeSliderQuizStep({
    required this.instruction,
    required this.scaleLabel,
    this.scaleMin = 0,
    this.scaleMax = 100,
    required this.correctMin,
    required this.correctMax,
    required this.successMessage,
    required this.hintMessage,
    this.zones = const [],
  });
}

// ─── ST-5: LabelMatchStep ─────────────────────────────────────────────────────
// User assigns draggable label chips to diagram drop targets.
// On mobile: tap label to select, tap target to assign.
final class LabelMatchStep extends LessonStep {
  final String instruction;
  final List<MatchItem> items;
  final List<MatchTarget> targets;
  final Map<String, String> correctMapping; // itemId → targetId
  final String backgroundDescription; // text description of the diagram

  const LabelMatchStep({
    required this.instruction,
    required this.items,
    required this.targets,
    required this.correctMapping,
    this.backgroundDescription = '',
  });
}
