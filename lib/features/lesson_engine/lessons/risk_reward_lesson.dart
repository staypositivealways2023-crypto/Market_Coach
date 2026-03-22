import 'package:flutter/material.dart';
import '../models/guided_lesson.dart';
import '../models/lesson_step.dart';
import '../models/demo_models.dart';

// ─── I-12: Risk/Reward Ratio ──────────────────────────────────────────────────
// 10 steps. Prerequisites: B-11 (Risk Basics), I-11 (Entry/Stop/Target).

const _rrSetupCandles = [
  DemoCandle(open: 100, high: 104, low: 98,  close: 103),
  DemoCandle(open: 103, high: 107, low: 101, close: 106),
  DemoCandle(open: 106, high: 110, low: 104, close: 109), // entry
  DemoCandle(open: 109, high: 113, low: 107, close: 112),
  DemoCandle(open: 112, high: 117, low: 110, close: 116),
  DemoCandle(open: 116, high: 121, low: 114, close: 120),
  DemoCandle(open: 120, high: 125, low: 118, close: 124), // near 2:1 target
  DemoCandle(open: 124, high: 130, low: 122, close: 128), // 3:1 target
];

const riskRewardLesson = GuidedLesson(
  id: 'i-12-risk-reward',
  title: 'Risk/Reward Ratio',
  subtitle: 'A 2:1 trade means you only need to win 34% of the time',
  topic: 'risk_reward',
  level: 'Intermediate',
  estimatedMinutes: 8,
  xpTotal: 90,
  prerequisites: ['b-11-risk-basics'],
  steps: [
    // ── Step 1: Intro ─────────────────────────────────────────────────────
    IntroStep(
      title: 'Risk/Reward Ratio',
      subtitle: 'How to profit even when you\'re wrong more than you\'re right',
      accentColor: Color(0xFFFFB74D),
    ),

    // ── Step 2: Theory — what is R:R ─────────────────────────────────────
    TheoryStep(
      badge: 'CONCEPT',
      title: 'What is the R:R ratio?',
      body:
          'Risk/Reward ratio (R:R) compares how much you stand to gain on a trade versus how much you stand to lose.\n\nR:R = Potential reward ÷ Risk taken\n\nA 2:1 R:R means for every \$1 you risk, you aim to make \$2.\nA 3:1 R:R means for every \$1 at risk, you target \$3 profit.',
      callout:
          'Most professional traders require at least 2:1 before they take a trade. Many require 3:1 or better.',
    ),

    // ── Step 3: CandlestickDemo — trade with entry, stop, target ──────────
    CandlestickDemoStep(
      title: 'R:R on a real trade',
      description:
          'Entry at ~\$109. Stop below support at ~\$103 = \$6 risk. First target at ~\$121 = \$12 gain (2:1). Second target at ~\$127 = \$18 gain (3:1).',
      candles: _rrSetupCandles,
      supportLevel: 103,
      resistanceLevel: 127,
      annotations: [
        CandleAnnotation(index: 2, label: 'Entry', color: Color(0xFF26A69A), arrowUp: false),
        CandleAnnotation(index: 6, label: '2:1 target', color: Color(0xFFFFB74D), arrowUp: true),
        CandleAnnotation(index: 7, label: '3:1 target', color: Color(0xFF1DE9B6), arrowUp: true),
      ],
    ),

    // ── Step 4: Theory — the math ─────────────────────────────────────────
    TheoryStep(
      badge: 'MATH',
      title: 'The breakeven win rate',
      body:
          'Every R:R ratio has a breakeven win rate — the minimum percentage of trades you need to win to avoid losing money:\n\n• 1:1 ratio → need 50%+ win rate\n• 2:1 ratio → need 34%+ win rate\n• 3:1 ratio → need 25%+ win rate\n• 5:1 ratio → need 17%+ win rate\n\nHigher R:R gives you more room to be wrong.',
      callout:
          'Formula: Breakeven % = 1 ÷ (1 + R:R)\nFor 2:1: 1 ÷ 3 = 33.3%',
    ),

    // ── Step 5: RangeSlider — assess a 1:1 trade ─────────────────────────
    RangeSliderQuizStep(
      instruction:
          'A trade risks \$500 to gain \$500 (1:1). Where on the quality scale does this trade belong?',
      scaleLabel: 'TRADE QUALITY',
      scaleMin: 0,
      scaleMax: 100,
      correctMin: 0,
      correctMax: 40,
      successMessage:
          'Exactly right. A 1:1 trade is low quality — you need a 50%+ win rate just to break even. Most professional traders avoid anything below 2:1.',
      hintMessage:
          'Remember: at 1:1 you need to win every other trade just to survive. Is that acceptable?',
      zones: [
        RangeZone(min: 0, max: 40, color: Color(0xFFEF5350), label: 'Poor'),
        RangeZone(min: 40, max: 65, color: Color(0xFFFFB74D), label: 'Acceptable'),
        RangeZone(min: 65, max: 100, color: Color(0xFF4CAF50), label: 'Good'),
      ],
    ),

    // ── Step 6: Theory — asymmetry ───────────────────────────────────────
    TheoryStep(
      badge: 'EDGE',
      title: 'Asymmetry is your edge',
      body:
          'Most traders focus on finding "winning" trades. Professionals focus on finding asymmetric trades — where the upside is much larger than the downside.\n\nYou can lose 7 out of 10 trades and still profit if your 3 winners each return 4× what your 7 losers cost.\n\n3 × 4 = 12 units won\n7 × 1 = 7 units lost\nNet: +5 units profit',
    ),

    // ── Step 7: Multiple choice ───────────────────────────────────────────
    MultipleChoiceStep(
      question:
          'You take 10 trades with a consistent 3:1 R:R. You win 4 and lose 6. What is your net result (in R)?',
      options: [
        '+6R profit',
        'Break even',
        '-2R loss',
        '+6R profit',
      ],
      correctIndex: 0,
      explanation:
          '4 winners × 3R = +12R. 6 losers × 1R = -6R. Net = +6R. Even with only a 40% win rate, a consistent 3:1 R:R produces solid profits.',
    ),

    // ── Step 8: Theory — partial exits ───────────────────────────────────
    TheoryStep(
      badge: 'TECHNIQUE',
      title: 'Partial exits: locking in gains',
      body:
          'Many professionals take partial profits at the 2:1 target and let the rest ride to 3:1 or beyond.\n\nStrategy: Close 50% at 2:1, move stop to breakeven, hold the remaining 50% with no risk.\n\nThis creates a "free trade" — worst case is breakeven, best case is a 3:1+ winner.',
    ),

    // ── Step 9: Recap ─────────────────────────────────────────────────────
    RecapStep(
      title: 'R:R ratio essentials',
      points: [
        'R:R = Potential reward ÷ Maximum risk',
        'Always aim for 2:1 minimum — preferably 3:1+',
        'Higher R:R = lower win rate needed to profit',
        'At 3:1 you only need 25% win rate to break even',
        'Asymmetry — big wins, small losses — is your edge',
        'Partial exits lock in gains and create risk-free trades',
      ],
    ),

    // ── Step 10: Completion ───────────────────────────────────────────────
    CompletionStep(
      title: 'R:R mastered!',
      message:
          'You now understand one of the most powerful concepts in trading. Before your next trade, calculate the R:R. If it\'s under 2:1, skip it.',
      xpEarned: 90,
      ctaLabel: 'Find a 3:1 setup on BTC',
      ctaTicker: 'BTCUSDT',
      ctaTickerName: 'Bitcoin',
      ctaIsCrypto: true,
    ),
  ],
);
