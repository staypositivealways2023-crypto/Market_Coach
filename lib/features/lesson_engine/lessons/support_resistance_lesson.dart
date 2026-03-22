import 'package:flutter/material.dart';
import '../models/guided_lesson.dart';
import '../models/lesson_step.dart';
import '../models/demo_models.dart';

// ─── B-04: Support & Resistance ───────────────────────────────────────────────
// 10 steps. Prerequisites: B-01.

// Price bouncing off support at ~100
const _supportBounceCandles = [
  DemoCandle(open: 115, high: 118, low: 112, close: 116),
  DemoCandle(open: 116, high: 117, low: 108, close: 110),
  DemoCandle(open: 110, high: 112, low: 101, close: 103),
  DemoCandle(open: 103, high: 105, low: 99,  close: 102), // touches support
  DemoCandle(open: 102, high: 110, low: 100, close: 108), // bounce
  DemoCandle(open: 108, high: 116, low: 106, close: 114), // recovery
  DemoCandle(open: 114, high: 118, low: 110, close: 112),
  DemoCandle(open: 112, high: 114, low: 103, close: 104), // touches support again
  DemoCandle(open: 104, high: 112, low: 100, close: 111), // bounce again
  DemoCandle(open: 111, high: 119, low: 109, close: 117),
];

// Price hitting resistance at ~120
const _resistanceBounceCandles = [
  DemoCandle(open: 105, high: 110, low: 103, close: 108),
  DemoCandle(open: 108, high: 115, low: 106, close: 113),
  DemoCandle(open: 113, high: 120, low: 111, close: 118), // near resistance
  DemoCandle(open: 118, high: 121, low: 112, close: 113), // rejected at resistance
  DemoCandle(open: 113, high: 116, low: 105, close: 107),
  DemoCandle(open: 107, high: 112, low: 103, close: 110),
  DemoCandle(open: 110, high: 119, low: 108, close: 117), // approaches again
  DemoCandle(open: 117, high: 121, low: 110, close: 111), // rejected again
  DemoCandle(open: 111, high: 114, low: 104, close: 106),
  DemoCandle(open: 106, high: 109, low: 101, close: 103),
];

const supportResistanceLesson = GuidedLesson(
  id: 'b-04-support-resistance',
  title: 'Support & Resistance',
  subtitle: 'Price bounces off the same levels again and again',
  topic: 'support_resistance',
  level: 'Beginner',
  estimatedMinutes: 7,
  xpTotal: 80,
  prerequisites: ['b-01-candlestick'],
  steps: [
    // ── Step 1: Intro ─────────────────────────────────────────────────────
    IntroStep(
      title: 'Support & Resistance',
      subtitle: 'Price has memory — it remembers where it turned before',
      accentColor: Color(0xFFFFB74D),
    ),

    // ── Step 2: Theory — Support ──────────────────────────────────────────
    TheoryStep(
      badge: 'CONCEPT',
      title: 'Support — The Floor',
      body:
          'A support level is a price zone where buyers repeatedly step in and stop the price from falling further. It acts like a floor.\n\nEvery time price drops to that level and bounces back up, the support gets stronger. Traders remember it and place buy orders there in anticipation.',
      callout:
          'Support forms where demand exceeds supply — buyers outnumber sellers at that price.',
      accentColor: Color(0xFF4CAF50),
    ),

    // ── Step 3: CandlestickDemo — support bounce ──────────────────────────
    CandlestickDemoStep(
      title: 'Support in action',
      description:
          'Price drops to the ~100 level twice and bounces both times. The green dashed line marks the support zone. Notice how buyers step in every time price touches it.',
      candles: _supportBounceCandles,
      supportLevel: 100,
      annotations: [
        CandleAnnotation(index: 3, label: 'Support touch', color: Color(0xFF4CAF50), arrowUp: false),
        CandleAnnotation(index: 7, label: 'Support touch again', color: Color(0xFF4CAF50), arrowUp: false),
      ],
    ),

    // ── Step 4: Theory — Resistance ───────────────────────────────────────
    TheoryStep(
      badge: 'CONCEPT',
      title: 'Resistance — The Ceiling',
      body:
          'A resistance level is a price zone where sellers repeatedly push price back down. It acts like a ceiling.\n\nTraders who bought lower sell near resistance to lock in profits. This flood of sell orders stops the advance.',
      callout:
          'Resistance forms where supply exceeds demand — sellers outnumber buyers at that price.',
      accentColor: Color(0xFFEF5350),
    ),

    // ── Step 5: CandlestickDemo — resistance rejection ────────────────────
    CandlestickDemoStep(
      title: 'Resistance in action',
      description:
          'Price tries to break ~121 twice and fails both times, creating long upper wicks. The red dashed line marks the resistance zone.',
      candles: _resistanceBounceCandles,
      resistanceLevel: 121,
      annotations: [
        CandleAnnotation(index: 3, label: 'Rejected', color: Color(0xFFEF5350), arrowUp: true),
        CandleAnnotation(index: 7, label: 'Rejected again', color: Color(0xFFEF5350), arrowUp: true),
      ],
    ),

    // ── Step 6: Theory — why levels work ─────────────────────────────────
    TheoryStep(
      badge: 'KEY INSIGHT',
      title: 'Why do these levels hold?',
      body:
          'Price levels repeat because traders remember them. When price reaches a level where it previously reversed, many traders act on that memory simultaneously:\n\n• Bulls place buy orders at support\n• Bears place sell orders at resistance\n• Stop-losses cluster near these zones\n\nThis self-fulfilling effect makes the levels self-reinforcing.',
    ),

    // ── Step 7: TapOnChart — tap a support bounce ─────────────────────────
    TapOnChartStep(
      instruction: 'Tap the candle where price bounced off support.',
      candles: _supportBounceCandles,
      correctIndex: 4,
      targetLabel: 'a bounce candle',
      successMessage:
          'Correct! After touching support, buyers pushed price back up. The long lower wick + green close shows the rejection.',
      revealAnnotations: [
        CandleAnnotation(index: 4, label: 'Bounce', color: Color(0xFF1DE9B6), arrowUp: false),
      ],
    ),

    // ── Step 8: LabelMatch — name the S/R components ─────────────────────
    LabelMatchStep(
      instruction: 'Match each description to the correct term.',
      backgroundDescription:
          'Assign each label chip to the trading concept it describes.',
      items: [
        MatchItem(id: 'support', label: 'Support'),
        MatchItem(id: 'resistance', label: 'Resistance'),
        MatchItem(id: 'wick', label: 'Upper wick'),
      ],
      targets: [
        MatchTarget(id: 'floor', hint: 'A level where buyers repeatedly stop a decline'),
        MatchTarget(id: 'ceiling', hint: 'A level where sellers repeatedly stop a rally'),
        MatchTarget(id: 'rejection', hint: 'Visual sign of price rejection at a high'),
      ],
      correctMapping: {
        'support': 'floor',
        'resistance': 'ceiling',
        'wick': 'rejection',
      },
    ),

    // ── Step 9: Recap ─────────────────────────────────────────────────────
    RecapStep(
      title: 'Support & Resistance essentials',
      points: [
        'Support is a price floor — buyers defend it repeatedly',
        'Resistance is a price ceiling — sellers block advances there',
        'More tests = stronger level (up to a point)',
        'Long wicks at a level = strong rejection',
        'These levels work because many traders act on the same memory',
        'Broken support often becomes resistance (and vice versa)',
      ],
    ),

    // ── Step 10: Completion ───────────────────────────────────────────────
    CompletionStep(
      title: 'S/R levels unlocked!',
      message:
          'You can now identify key support and resistance levels on any chart. Open BTC and spot the price floors and ceilings that have held.',
      xpEarned: 80,
      ctaLabel: 'Find S/R levels on BTC',
      ctaTicker: 'BTCUSDT',
      ctaTickerName: 'Bitcoin',
      ctaIsCrypto: true,
    ),
  ],
);
