import 'package:flutter/material.dart';
import '../models/lesson_step.dart';
import '../models/guided_lesson.dart';

// ─── Synthetic RSI data arrays ─────────────────────────────────────────────
// Overbought scenario: RSI climbs from neutral → pushes above 70
const _overboughtRsiData = [
  48.0, 51.2, 54.8, 57.1, 59.6, 63.2, 65.0, 67.4, 70.1, 73.5,
  76.2, 74.8, 78.3, 75.1, 72.6, 70.4, 68.9, 65.3, 62.0, 58.5,
];

// Oversold scenario: RSI drops from neutral → dips below 30
const _oversoldRsiData = [
  52.0, 49.3, 46.1, 43.5, 40.8, 37.2, 34.0, 31.5, 28.9, 25.4,
  22.1, 24.7, 21.3, 26.5, 29.8, 32.4, 35.7, 38.1, 41.2, 45.0,
];

// ─── RSI Pilot Lesson ──────────────────────────────────────────────────────
final rsiLesson = GuidedLesson(
  id: 'rsi_intro_v1',
  title: 'Reading RSI',
  subtitle: 'Know when a stock is overheated or oversold',
  topic: 'Technical Analysis',
  level: 'Beginner',
  estimatedMinutes: 5,
  xpTotal: 100,
  steps: const [
    // 1. Intro
    IntroStep(
      title: 'Reading RSI',
      subtitle:
          'Learn how to spot when a stock is running too hot — or getting ready to bounce.',
      accentColor: Color(0xFF12A28C),
    ),

    // 2. What is RSI?
    TheoryStep(
      badge: 'CONCEPT',
      title: 'What is RSI?',
      body:
          'RSI stands for Relative Strength Index. It measures how fast a stock\'s price has been moving — up or down — over the last 14 days.\n\nThe result is a number between 0 and 100.',
      callout:
          'Think of RSI like a speedometer: it tells you how fast the market is moving, not which direction.',
    ),

    // 3. The three zones
    TheoryStep(
      badge: 'THE ZONES',
      title: 'Three zones to know',
      body:
          'RSI splits the 0–100 scale into three meaningful zones:\n\n'
          '• Above 70 → Overbought\n'
          '• 30 to 70 → Neutral\n'
          '• Below 30 → Oversold',
      callout:
          'Overbought doesn\'t mean "sell now" — it means the recent move has been unusually fast. Slow-down risk is higher.',
      accentColor: Color(0xFFEF5350),
    ),

    // 4. Visual explainer — animated RSI bar
    VisualExplainerStep(
      title: 'See RSI in action',
      explanation:
          'Watch the indicator move through each zone. The colours change as RSI enters overbought (red) or oversold (green) territory.',
    ),

    // 5. Chart highlight — overbought
    ChartHighlightStep(
      title: 'BTC hits overbought',
      description:
          'RSI climbed above 70 after a strong rally. Historically, this is where momentum slows and profit-taking begins. It\'s not a guaranteed reversal — but it\'s a yellow flag.',
      rsiData: _overboughtRsiData,
      highlightOverbought: true,
    ),

    // 6. Chart highlight — oversold
    ChartHighlightStep(
      title: 'BTC drops to oversold',
      description:
          'RSI fell below 30 after a sharp sell-off. Sellers have been dominant. This zone often sees bounces — especially when combined with a support level or positive news catalyst.',
      rsiData: _oversoldRsiData,
      highlightOversold: true,
    ),

    // 7. Tap to identify — oversold
    TapToIdentifyStep(
      instruction: 'RSI is at 24.\nWhich zone does that fall in?',
      targetZone: 'oversold',
      successMessage:
          'RSI 24 is clearly in the oversold zone (below 30). Sellers have pushed too hard — a bounce is possible.',
    ),

    // 8. Multiple choice
    MultipleChoiceStep(
      question:
          'A stock\'s RSI reads 82. What does this most likely mean for a short-term trader?',
      options: [
        'Strong buy — momentum is building',
        'Caution — the stock may be overbought',
        'Sell immediately — RSI never lies',
        'RSI of 82 is in the neutral zone',
      ],
      correctIndex: 1,
      explanation:
          'RSI above 70 signals the recent move may have been too fast. Traders use it as a caution flag to tighten stops or reduce size — not as an automatic sell signal.',
    ),

    // 9. Compare examples
    CompareExamplesStep(
      instruction: 'Same sector, different signals.\nWhich stock looks more interesting for a bounce?',
      left: CompareCard(
        label: 'STOCK A',
        rsiValue: 78,
        scenario: 'Up 14% in 5 days after earnings beat',
        interpretation: 'Overbought — wait for pullback',
        color: Color(0xFFEF5350),
      ),
      right: CompareCard(
        label: 'STOCK B',
        rsiValue: 26,
        scenario: 'Down 18% on sector rotation fears',
        interpretation: 'Oversold — bounce potential',
        color: Color(0xFF4CAF50),
      ),
    ),

    // 10. Recap
    RecapStep(
      title: 'Key takeaways',
      points: [
        'RSI measures the speed of recent price moves, not direction',
        'Above 70 = overbought. Below 30 = oversold. In between = neutral',
        'Overbought/oversold are caution flags, not automatic signals',
        'Always confirm RSI with price action and context',
      ],
    ),

    // 11. Completion
    CompletionStep(
      title: 'RSI unlocked 🎯',
      message:
          'You can now read RSI on any chart. Put it to work — open a live BTC chart with RSI enabled and find the current zone yourself.',
      xpEarned: 100,
      ctaLabel: 'Practice RSI on BTC',
      ctaTicker: 'BTC',
      ctaTickerName: 'Bitcoin',
      ctaIsCrypto: true,
      ctaShowRSI: true,
      ctaShowMACD: false,
    ),
  ],
);
