import 'package:flutter/material.dart';
import '../models/guided_lesson.dart';
import '../models/lesson_step.dart';
import '../models/demo_models.dart';

// ─── B-11: Risk Basics ────────────────────────────────────────────────────────
// 10 steps. Prerequisites: B-10 (or none for pilot).

// Trade setup showing entry, stop-loss, and target
const _tradeSetupCandles = [
  DemoCandle(open: 100, high: 104, low: 98,  close: 102),
  DemoCandle(open: 102, high: 106, low: 100, close: 105),
  DemoCandle(open: 105, high: 109, low: 103, close: 108), // entry candle
  DemoCandle(open: 108, high: 113, low: 106, close: 111),
  DemoCandle(open: 111, high: 116, low: 109, close: 114),
  DemoCandle(open: 114, high: 120, low: 112, close: 118),
  DemoCandle(open: 118, high: 122, low: 116, close: 121),
  DemoCandle(open: 121, high: 125, low: 119, close: 123), // near target
];

const riskBasicsLesson = GuidedLesson(
  id: 'b-11-risk-basics',
  title: 'Risk Basics',
  subtitle: 'You can be wrong half the time and still make money',
  topic: 'risk_management',
  level: 'Beginner',
  estimatedMinutes: 7,
  xpTotal: 80,
  prerequisites: [],
  steps: [
    // ── Step 1: Intro ─────────────────────────────────────────────────────
    IntroStep(
      title: 'Risk Basics',
      subtitle: 'The secret is not being right — it\'s managing when you\'re wrong',
      accentColor: Color(0xFFFFB74D),
    ),

    // ── Step 2: Theory — what is risk ────────────────────────────────────
    TheoryStep(
      badge: 'CONCEPT',
      title: 'What is trading risk?',
      body:
          'In trading, risk means the amount of money you are willing to lose on a single trade before you exit.\n\nEvery professional trader decides their maximum loss before they enter a trade — not after. This predetermined exit point is called a stop-loss.',
      callout:
          '"Define your risk before you enter. Never let a trade become an investment."',
    ),

    // ── Step 3: Theory — stop-loss ───────────────────────────────────────
    TheoryStep(
      badge: 'TOOL',
      title: 'The stop-loss',
      body:
          'A stop-loss is an automatic order that closes your trade if price moves against you by a set amount.\n\nExample: You buy at \$108. You place a stop at \$103. Your maximum loss is \$5 per share — no matter what happens, your loss is capped.\n\nThis turns an unknown loss into a known, planned loss.',
      callout:
          'A stop-loss converts unlimited risk into defined risk. It\'s the most important tool in risk management.',
      accentColor: Color(0xFFEF5350),
    ),

    // ── Step 4: CandlestickDemo — entry, stop, target ─────────────────────
    CandlestickDemoStep(
      title: 'Trade anatomy: Entry, Stop, Target',
      description:
          'Entry at the breakout candle (~108). Stop-loss below recent support (~103). Target at the next resistance (~123). This is a \$5 risk for a \$15 reward.',
      candles: _tradeSetupCandles,
      supportLevel: 103,
      resistanceLevel: 123,
      annotations: [
        CandleAnnotation(index: 2, label: 'Entry ≈108', color: Color(0xFF26A69A), arrowUp: false),
        CandleAnnotation(index: 7, label: 'Target ≈123', color: Color(0xFFFFB74D), arrowUp: true),
      ],
    ),

    // ── Step 5: Theory — position sizing ─────────────────────────────────
    TheoryStep(
      badge: 'RULE',
      title: 'The 1% rule',
      body:
          'Professional traders typically risk no more than 1–2% of their total account on any single trade.\n\nIf your account is \$10,000, that\'s a maximum loss of \$100–\$200 per trade.\n\nYou then calculate position size: if your stop is \$5 away and you can lose \$100, you can buy 20 shares.',
      callout:
          'Position size = (Account × Risk%) ÷ Stop distance\n\nExample: (\$10,000 × 1%) ÷ \$5 = 20 shares',
    ),

    // ── Step 6: RangeSlider quiz — acceptable risk/reward ─────────────────
    RangeSliderQuizStep(
      instruction:
          'A trade risks \$200 to potentially gain \$600. Where does this trade sit on the quality scale?',
      scaleLabel: 'TRADE QUALITY',
      scaleMin: 0,
      scaleMax: 100,
      correctMin: 65,
      correctMax: 100,
      successMessage:
          'Correct zone! A \$200 risk for \$600 reward is a 3:1 ratio — generally considered a good trade. Most professionals look for at least 2:1.',
      hintMessage: 'Drag the slider to where you think this trade falls: poor, acceptable, or good?',
      zones: [
        RangeZone(min: 0, max: 35, color: Color(0xFFEF5350), label: 'Poor'),
        RangeZone(min: 35, max: 65, color: Color(0xFFFFB74D), label: 'Acceptable'),
        RangeZone(min: 65, max: 100, color: Color(0xFF4CAF50), label: 'Good'),
      ],
    ),

    // ── Step 7: Theory — why risk matters ────────────────────────────────
    TheoryStep(
      badge: 'MATH',
      title: 'Why you can lose 50% of trades and profit',
      body:
          'Imagine 10 trades: 5 winners and 5 losers. Each loser costs you \$100. Each winner earns you \$300 (3:1 reward).\n\nResult: −\$500 + \$1,500 = +\$1,000 profit despite a 50% win rate.\n\nThis is why reward-to-risk ratio matters more than win rate. A 3:1 ratio means you only need to win 25% of the time to break even.',
      callout:
          'At 2:1 R:R you break even at 34% win rate. At 3:1 you break even at just 25%.',
    ),

    // ── Step 8: Multiple choice ───────────────────────────────────────────
    MultipleChoiceStep(
      question:
          'You have a \$5,000 account and follow the 1% rule. Your stop is \$2 away from your entry. What is the maximum position size?',
      options: [
        '25 shares',
        '100 shares',
        '50 shares',
        '250 shares',
      ],
      correctIndex: 0,
      explanation:
          '1% of \$5,000 = \$50 max risk. \$50 ÷ \$2 stop = 25 shares. Position sizing protects your account from any single loss.',
    ),

    // ── Step 9: Recap ─────────────────────────────────────────────────────
    RecapStep(
      title: 'Risk essentials',
      points: [
        'Always define your maximum loss before entering a trade',
        'A stop-loss converts unknown risk into defined, planned risk',
        'Risk 1–2% of your account per trade maximum',
        'Position size = (Account × Risk%) ÷ Stop distance',
        'A 2:1 reward/risk ratio means you only need 34% win rate to profit',
        'Risk management matters more than being "right" on every trade',
      ],
    ),

    // ── Step 10: Completion ───────────────────────────────────────────────
    CompletionStep(
      title: 'Risk mindset unlocked!',
      message:
          'You now understand the foundation of professional trading. Open ETH and identify a sensible entry, stop-loss, and target level.',
      xpEarned: 80,
      ctaLabel: 'Practice on ETH',
      ctaTicker: 'ETHUSDT',
      ctaTickerName: 'Ethereum',
      ctaIsCrypto: true,
    ),
  ],
);
