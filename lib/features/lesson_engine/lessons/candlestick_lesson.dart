import 'package:flutter/material.dart';
import '../models/guided_lesson.dart';
import '../models/lesson_step.dart';
import '../models/demo_models.dart';

// ─── B-01: What is a Candlestick? ─────────────────────────────────────────────
// 9 steps. Prerequisites: none.

// Sample candles used throughout this lesson
const _singleBullish = DemoCandle(open: 100, high: 112, low: 96, close: 110);
const _singleBearish = DemoCandle(open: 110, high: 114, low: 97, close: 100);

const _mixedCandles = [
  DemoCandle(open: 100, high: 108, low: 97,  close: 106), // bullish
  DemoCandle(open: 106, high: 110, low: 100, close: 103), // bearish
  DemoCandle(open: 103, high: 111, low: 101, close: 110), // bullish
  DemoCandle(open: 110, high: 115, low: 107, close: 108), // bearish
  DemoCandle(open: 108, high: 118, low: 106, close: 117), // bullish (big)
  DemoCandle(open: 117, high: 120, low: 109, close: 111), // bearish
  DemoCandle(open: 111, high: 116, low: 109, close: 115), // bullish
  DemoCandle(open: 115, high: 118, low: 104, close: 106), // bearish (big)
];

const _ohlcCandle = [
  DemoCandle(open: 105, high: 118, low: 99, close: 115),
];

const candlestickLesson = GuidedLesson(
  id: 'b-01-candlestick',
  title: 'What is a Candlestick?',
  subtitle: 'One candle tells the whole story of a session',
  topic: 'candlestick',
  level: 'Beginner',
  estimatedMinutes: 6,
  xpTotal: 75,
  prerequisites: [],
  steps: [
    // ── Step 1: Intro ─────────────────────────────────────────────────────
    IntroStep(
      title: 'What is a Candlestick?',
      subtitle: 'Every candle hides the full story of a trading session',
      accentColor: Color(0xFF26A69A),
    ),

    // ── Step 2: Theory — one session, four prices ─────────────────────────
    TheoryStep(
      badge: 'CONCEPT',
      title: 'One candle = one session',
      body:
          'A candlestick records exactly four prices from a single trading session: the price when trading opened, the highest price reached, the lowest price reached, and the price when trading closed.\n\nEvery bar on your chart — whether it covers 1 minute or 1 month — holds those four numbers.',
      callout:
          'A daily candlestick on AAPL shows everything that happened in a full day of trading, compressed into a single shape.',
    ),

    // ── Step 3: CandlestickDemo — labelled OHLC ───────────────────────────
    CandlestickDemoStep(
      title: 'The anatomy of a candle',
      description:
          'Every candle has a body (the thick rectangle) and two wicks (the thin lines). The body spans Open to Close. The wicks mark the High and Low.',
      candles: _ohlcCandle,
      annotations: [
        CandleAnnotation(index: 0, label: 'HIGH', color: Color(0xFFFFB74D), arrowUp: true),
        CandleAnnotation(index: 0, label: 'LOW', color: Color(0xFF90CAF9), arrowUp: false),
      ],
    ),

    // ── Step 4: Theory — color = direction ───────────────────────────────
    TheoryStep(
      badge: 'RULE',
      title: 'Color = Direction',
      body:
          'A green (or hollow) candle means the session closed higher than it opened — buyers were in control. A red (or filled) candle means the session closed lower — sellers dominated.',
      callout:
          'You can always tell who won a session without reading any numbers — just look at the color.',
      accentColor: Color(0xFF26A69A),
    ),

    // ── Step 5: CandlestickDemo — bullish vs bearish side-by-side ─────────
    CandlestickDemoStep(
      title: 'Bullish and Bearish candles',
      description:
          'The green candle closed higher than it opened. The red candle closed lower. Notice how the body length reflects how decisive the move was.',
      candles: [_singleBullish, _singleBearish],
      highlightBullish: true,
      highlightBearish: true,
    ),

    // ── Step 6: Theory — wicks matter ────────────────────────────────────
    TheoryStep(
      badge: 'KEY INSIGHT',
      title: 'Wicks tell the real story',
      body:
          'A long upper wick means buyers pushed price high, but sellers pushed it back down before the close. A long lower wick means sellers drove price low, but buyers fought back.\n\nThe wick tells you what the market tried but failed to hold.',
      callout: 'A candle with a tiny body and long wicks shows indecision — neither side won.',
    ),

    // ── Step 7: TapOnChart — identify a bullish candle ────────────────────
    TapOnChartStep(
      instruction: 'Tap the candle where buyers clearly won the session.',
      candles: _mixedCandles,
      correctIndex: 4, // the big bullish candle
      targetLabel: 'a green candle',
      successMessage:
          'Correct! The tall green body shows strong buying pressure — buyers pushed price up and held the gains.',
      revealAnnotations: [
        CandleAnnotation(
          index: 4,
          label: 'Strong buying',
          color: Color(0xFF1DE9B6),
          arrowUp: true,
        ),
      ],
    ),

    // ── Step 8: Recap ─────────────────────────────────────────────────────
    RecapStep(
      title: 'Candlestick essentials',
      points: [
        'Each candle records Open, High, Low, and Close for one session',
        'Green = close above open (buyers won), Red = close below open (sellers won)',
        'The body spans Open → Close; wicks show the High and Low extremes',
        'Long wicks = price was rejected; they reveal failed attempts',
        'Body size shows conviction — a small body = neither side dominated',
      ],
    ),

    // ── Step 9: Completion ────────────────────────────────────────────────
    CompletionStep(
      title: 'Candlesticks unlocked!',
      message:
          'You can now read what every single candle on a chart is saying. Practice spotting bullish and bearish candles on the BTC live chart.',
      xpEarned: 75,
      ctaLabel: 'See BTC candles live',
      ctaTicker: 'BTCUSDT',
      ctaTickerName: 'Bitcoin',
      ctaIsCrypto: true,
    ),
  ],
);
