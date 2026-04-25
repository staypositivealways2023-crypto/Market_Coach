import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Sentiment classifications shown on stock/crypto cards.
///
/// Maps to the pill labels in the redesign: BULLISH / MILD BULL / NEUTRAL /
/// MILD BEAR / BEARISH. Use [SentimentBadge.fromScore] to derive from a
/// 0–100 score produced by [EnhancedAIAnalysis.sentimentScore].
enum Sentiment { bullish, mildBull, neutral, mildBear, bearish }

extension SentimentLabels on Sentiment {
  String get label {
    switch (this) {
      case Sentiment.bullish:
        return 'BULLISH';
      case Sentiment.mildBull:
        return 'MILD BULL';
      case Sentiment.neutral:
        return 'NEUTRAL';
      case Sentiment.mildBear:
        return 'MILD BEAR';
      case Sentiment.bearish:
        return 'BEARISH';
    }
  }

  Color get fg {
    switch (this) {
      case Sentiment.bullish:
      case Sentiment.mildBull:
        return AppColors.bullish;
      case Sentiment.neutral:
        return AppColors.neutral;
      case Sentiment.mildBear:
      case Sentiment.bearish:
        return AppColors.bearish;
    }
  }

  Color get bg {
    switch (this) {
      case Sentiment.bullish:
      case Sentiment.mildBull:
        return AppColors.bullishBg;
      case Sentiment.neutral:
        return AppColors.neutralBg;
      case Sentiment.mildBear:
      case Sentiment.bearish:
        return AppColors.bearishBg;
    }
  }
}

/// Pill-shaped badge that communicates bullish / neutral / bearish stance.
class SentimentBadge extends StatelessWidget {
  final Sentiment sentiment;
  final EdgeInsets padding;

  const SentimentBadge({
    super.key,
    required this.sentiment,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  });

  /// Derive sentiment from a 0–100 score. Mirrors the bucketing used by
  /// [EnhancedAIAnalysis.sentimentScore] in the rest of the app.
  factory SentimentBadge.fromScore(double score, {Key? key}) {
    final Sentiment s;
    if (score >= 75) {
      s = Sentiment.bullish;
    } else if (score >= 60) {
      s = Sentiment.mildBull;
    } else if (score >= 40) {
      s = Sentiment.neutral;
    } else if (score >= 25) {
      s = Sentiment.mildBear;
    } else {
      s = Sentiment.bearish;
    }
    return SentimentBadge(key: key, sentiment: s);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: sentiment.bg,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: sentiment.fg.withOpacity(0.35), width: 0.5),
      ),
      child: Text(
        sentiment.label,
        style: AppText.micro.copyWith(color: sentiment.fg),
      ),
    );
  }
}

/// Small "● LIVE" badge used on hero cards to signal real-time data.
class LiveBadge extends StatelessWidget {
  final String label;
  final Color color;

  const LiveBadge({
    super.key,
    this.label = 'LIVE',
    this.color = AppColors.bullish,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: color.withOpacity(0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: AppText.micro.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Warning badge like "CAUTION" shown on overview cards.
class AlertBadge extends StatelessWidget {
  final String label;
  final Color color;

  const AlertBadge({
    super.key,
    required this.label,
    this.color = AppColors.caution,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: color.withOpacity(0.45), width: 0.5),
      ),
      child: Text(label, style: AppText.micro.copyWith(color: color)),
    );
  }
}
