import 'package:flutter/material.dart';
import '../models/guided_lesson.dart';
import '../models/lesson_step.dart';
import '../models/demo_models.dart';

// ─── I-02: MACD Explained ────────────────────────────────────────────────────
// 10 steps. Prerequisites: B-07 (Moving Averages), B-08 (RSI).

// Synthetic price data with a bullish then bearish momentum shift
const _priceData = [
  48.0, 49.5, 51.0, 50.0, 49.0, 47.5, 46.0, 44.5, 43.0, 41.5,  // downtrend
  42.0, 43.5, 45.0, 46.5, 48.0, 49.0, 50.5, 52.0, 53.5, 55.0,  // reversal
  56.5, 58.0, 59.0, 60.5, 62.0, 63.0, 62.5, 61.0, 59.5, 58.0,  // top
];

// Approximate MACD line (12-26 EMA difference, simplified)
const _macdLine = [
  -0.8, -1.0, -0.9, -1.1, -1.3, -1.5, -1.7, -1.9, -2.1, -2.2,
  -1.8, -1.3, -0.8, -0.3, 0.2,  0.7,  1.1,  1.4,  1.7,  1.9,
   2.0,  1.9,  1.7,  1.4,  1.1,  0.8,  0.4,  0.0, -0.4, -0.8,
];

// Approximate signal line (9-period EMA of MACD)
const _signalLine = [
  -0.5, -0.7, -0.8, -0.9, -1.1, -1.2, -1.4, -1.6, -1.8, -1.9,
  -1.8, -1.6, -1.3, -1.0, -0.7, -0.3,  0.1,  0.4,  0.7,  1.0,
   1.3,  1.5,  1.6,  1.6,  1.5,  1.3,  1.1,  0.8,  0.5,  0.1,
];

// Histogram = MACD - Signal
const _histogram = [
  -0.3, -0.3, -0.1, -0.2, -0.2, -0.3, -0.3, -0.3, -0.3, -0.3,
   0.0,  0.3,  0.5,  0.7,  0.9,  1.0,  1.0,  1.0,  1.0,  0.9,
   0.7,  0.4,  0.1, -0.2, -0.4, -0.5, -0.7, -0.8, -0.9, -0.9,
];

// Sample candles for TapOnChart
const _candlesForTap = [
  DemoCandle(open: 43.5, high: 44.5, low: 42.0, close: 43.0),
  DemoCandle(open: 43.0, high: 44.2, low: 42.5, close: 44.0), // momentum starts
  DemoCandle(open: 44.0, high: 45.5, low: 43.5, close: 45.3),
  DemoCandle(open: 45.3, high: 47.0, low: 44.8, close: 46.8), // bullish cross area
  DemoCandle(open: 46.8, high: 48.5, low: 46.0, close: 48.2),
  DemoCandle(open: 48.2, high: 50.0, low: 47.5, close: 49.8),
  DemoCandle(open: 49.8, high: 51.5, low: 49.0, close: 51.2),
  DemoCandle(open: 51.2, high: 52.0, low: 50.0, close: 51.0), // topping
];

const macdLesson = GuidedLesson(
  id: 'i-02-macd',
  title: 'MACD Explained',
  subtitle: 'When two moving averages cross, momentum shifts',
  topic: 'macd',
  level: 'Intermediate',
  estimatedMinutes: 8,
  xpTotal: 90,
  prerequisites: ['b-08-rsi-basics'],
  steps: [
    // ── Step 1: Intro ─────────────────────────────────────────────────────
    IntroStep(
      title: 'MACD Explained',
      subtitle: 'The most popular momentum indicator — and why it works',
      accentColor: Color(0xFF7C4DFF),
    ),

    // ── Step 2: Theory — what is MACD ────────────────────────────────────
    TheoryStep(
      badge: 'CONCEPT',
      title: 'What is MACD?',
      body:
          'MACD stands for Moving Average Convergence Divergence. It shows the relationship between two exponential moving averages: a fast (12-period) and a slow (26-period).\n\nMACD line = Fast EMA − Slow EMA\n\nWhen the fast EMA is above the slow EMA, the MACD line is positive, showing upward momentum. When below, it\'s negative.',
      callout:
          'MACD doesn\'t predict price — it measures how fast price is moving and whether momentum is increasing or fading.',
    ),

    // ── Step 3: IndicatorDemo — MACD histogram ────────────────────────────
    IndicatorDemoStep(
      title: 'The MACD histogram',
      description:
          'The histogram (bars below) shows the difference between the MACD line and the Signal line. Growing bars = momentum is building. Shrinking bars = momentum is fading.',
      demoType: IndicatorDemoType.macd,
      priceData: _priceData,
      line1: _macdLine,
      line2: _signalLine,
      histogram: _histogram,
      annotations: [
        IndicatorAnnotation(index: 14, label: 'Cross', color: Color(0xFF26A69A)),
        IndicatorAnnotation(index: 25, label: 'Cross', color: Color(0xFFEF5350)),
      ],
    ),

    // ── Step 4: Theory — the signal line ─────────────────────────────────
    TheoryStep(
      badge: 'TOOL',
      title: 'The Signal line',
      body:
          'The Signal line is a 9-period EMA of the MACD line itself. It smooths out the MACD\'s movements.\n\nWhen the MACD line crosses above the Signal line → bullish signal (buying momentum increasing).\n\nWhen the MACD line crosses below the Signal line → bearish signal (selling momentum increasing).',
      callout:
          'Crossovers are the most common MACD signal. They work best when they align with the overall trend direction.',
      accentColor: Color(0xFF7C4DFF),
    ),

    // ── Step 5: IndicatorDemo — crossover ─────────────────────────────────
    IndicatorDemoStep(
      title: 'Bullish and bearish crossovers',
      description:
          'Watch the MACD line (teal) cross above the Signal line (pink) during the uptrend. Later it crosses back below — confirming the momentum shift.',
      demoType: IndicatorDemoType.macross,
      priceData: _priceData,
      line1: _macdLine,
      line2: _signalLine,
    ),

    // ── Step 6: Theory — zero line ───────────────────────────────────────
    TheoryStep(
      badge: 'KEY INSIGHT',
      title: 'The zero line matters',
      body:
          'When MACD is above zero, the fast EMA is above the slow EMA — overall bullish momentum. Below zero = overall bearish momentum.\n\nA crossover above the zero line is stronger than one below it. A crossover below zero confirms a downtrend is likely continuing.',
    ),

    // ── Step 7: TapOnChart — identify momentum peak ───────────────────────
    TapOnChartStep(
      instruction:
          'Tap the candle where upward momentum was strongest (before it began to fade).',
      candles: _candlesForTap,
      correctIndex: 5,
      targetLabel: 'the momentum peak candle',
      successMessage:
          'Good instinct! The tall green body with strong follow-through is where momentum peaked. After this, candles started showing less conviction.',
      revealAnnotations: [
        CandleAnnotation(
          index: 5,
          label: 'Peak momentum',
          color: Color(0xFF7C4DFF),
          arrowUp: true,
        ),
      ],
    ),

    // ── Step 8: Multiple choice ───────────────────────────────────────────
    MultipleChoiceStep(
      question: 'MACD crosses above the signal line while both are below zero. What does this suggest?',
      options: [
        'Strong bullish signal — buy immediately',
        'A potential bounce but remain cautious (weak signal)',
        'Bearish — MACD below zero means sell',
        'No signal — MACD only works above zero',
      ],
      correctIndex: 1,
      explanation:
          'A crossover below zero is a weaker bullish signal. It may indicate a short-term bounce within a broader downtrend. Prefer crossovers above zero for higher-probability bullish setups.',
    ),

    // ── Step 9: Recap ─────────────────────────────────────────────────────
    RecapStep(
      title: 'MACD essentials',
      points: [
        'MACD = Fast EMA (12) minus Slow EMA (26)',
        'Signal line = 9-period EMA of MACD',
        'Bullish crossover: MACD crosses above Signal line',
        'Bearish crossover: MACD crosses below Signal line',
        'Histogram shows the gap between MACD and Signal',
        'Crossovers above zero are stronger bullish signals',
      ],
    ),

    // ── Step 10: Completion ───────────────────────────────────────────────
    CompletionStep(
      title: 'MACD unlocked!',
      message:
          'You can now read MACD crossovers and histogram divergence. Open BTC with MACD enabled to practice spotting signals.',
      xpEarned: 90,
      ctaLabel: 'Practice MACD on BTC',
      ctaTicker: 'BTCUSDT',
      ctaTickerName: 'Bitcoin',
      ctaIsCrypto: true,
      ctaShowMACD: true,
    ),
  ],
);
