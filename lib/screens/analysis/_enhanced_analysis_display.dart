/// Enhanced Analysis Display - Beautiful structured display of AI analysis
///
/// Shows sentiment scores, recommendations, factors, and risk in clear sections
library;

import 'package:flutter/material.dart';
import '../../models/enhanced_ai_analysis.dart';
import '../../widgets/disclaimer_banner.dart';
import '../../widgets/glass_card.dart';

class EnhancedAnalysisDisplay extends StatelessWidget {
  final EnhancedAIAnalysis analysis;
  final VoidCallback? onRefresh;

  const EnhancedAnalysisDisplay({
    super.key,
    required this.analysis,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sentiment Score Card (Large, Eye-catching)
        _SentimentScoreCard(analysis: analysis),

        const SizedBox(height: 16),

        // Recommendation + Summary
        _RecommendationCard(analysis: analysis, onRefresh: onRefresh),

        const SizedBox(height: 16),

        // Price Target (if available)
        if (analysis.priceTarget != null) ...[
          _PriceTargetCard(analysis: analysis),
          const SizedBox(height: 16),
        ],

        // Bullish Factors
        if (analysis.bullishFactors.isNotEmpty) ...[
          _FactorsCard(
            title: 'Bullish Factors',
            factors: analysis.bullishFactors,
            icon: Icons.trending_up,
            color: Colors.green,
          ),
          const SizedBox(height: 16),
        ],

        // Bearish Factors
        if (analysis.bearishFactors.isNotEmpty) ...[
          _FactorsCard(
            title: 'Bearish Factors',
            factors: analysis.bearishFactors,
            icon: Icons.trending_down,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
        ],

        // Risk Assessment
        _RiskAssessmentCard(analysis: analysis),

        const SizedBox(height: 16),

        // Disclaimer
        _DisclaimerCard(analysis: analysis),

        const SizedBox(height: 8),
        const DisclaimerBanner(),
      ],
    );
  }
}

/// Large sentiment score card with circular indicator
class _SentimentScoreCard extends StatelessWidget {
  final EnhancedAIAnalysis analysis;

  const _SentimentScoreCard({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(
      int.parse('0xFF${analysis.sentimentColorHex.substring(1)}'),
    );

    return GlassCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Circular sentiment indicator
          SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background circle
                SizedBox(
                  width: 180,
                  height: 180,
                  child: CircularProgressIndicator(
                    value: analysis.sentimentScore / 100,
                    strokeWidth: 16,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                // Score in center
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${analysis.sentimentScore}',
                      style: TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.bold,
                        color: color,
                        height: 1.0,
                      ),
                    ),
                    Text(
                      analysis.sentimentText,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Sentiment scale indicator
          _SentimentScale(score: analysis.sentimentScore),
        ],
      ),
    );
  }
}

/// Sentiment scale from 0-100
class _SentimentScale extends StatelessWidget {
  final int score;

  const _SentimentScale({required this.score});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final barWidth = constraints.maxWidth;
            const barH = 12.0;
            const dotW = 4.0;
            const dotH = 20.0;
            final dotLeft = ((score / 100) * barWidth - dotW / 2).clamp(
              0.0,
              barWidth - dotW,
            );

            return SizedBox(
              height: dotH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Track
                  Positioned(
                    left: 0,
                    right: 0,
                    top: (dotH - barH) / 2,
                    height: barH,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFD32F2F),
                            Color(0xFFFF5722),
                            Color(0xFFFFC107),
                            Color(0xFF4CAF50),
                            Color(0xFF00C853),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Indicator dot
                  Positioned(
                    left: dotLeft,
                    top: 0,
                    child: Container(
                      width: dotW,
                      height: dotH,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 8),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Bearish',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            Text(
              'Neutral',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            Text(
              'Bullish',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Recommendation and summary card
class _RecommendationCard extends StatelessWidget {
  final EnhancedAIAnalysis analysis;
  final VoidCallback? onRefresh;

  const _RecommendationCard({required this.analysis, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recColor = Color(
      int.parse('0xFF${analysis.recommendation.colorHex.substring(1)}'),
    );

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Recommendation badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: recColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: recColor, width: 2),
                ),
                child: Text(
                  analysis.recommendation.displayName.toUpperCase(),
                  style: TextStyle(
                    color: recColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.2,
                  ),
                ),
              ),

              const Spacer(),

              // Timestamp + Cache indicator
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (analysis.isCached)
                      Icon(
                        Icons.cached,
                        size: 14,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    if (analysis.isCached) const SizedBox(width: 4),
                    Text(
                      analysis.timeAgo,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Refresh button
              if (onRefresh != null)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  color: theme.colorScheme.primary,
                  onPressed: onRefresh,
                  tooltip: 'Refresh Analysis',
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Summary text — AI-generated, visually signed with teal border
          AiTextBlock(
            child: Text(
              analysis.summaryText,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white.withOpacity(0.9),
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Price target card
class _PriceTargetCard extends StatelessWidget {
  final EnhancedAIAnalysis analysis;

  const _PriceTargetCard({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = analysis.priceTarget!;
    final changePercent =
        ((target.target - analysis.currentPrice) / analysis.currentPrice * 100);
    final isPositive = changePercent >= 0;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.show_chart,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Educational Price Simulation (${target.timeframeDays}d)',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Current price
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                  Text(
                    '\$${analysis.currentPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 24),
              Icon(Icons.arrow_forward, color: Colors.white.withOpacity(0.4)),
              const SizedBox(width: 24),

              // Target price
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Target',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$${target.target.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: isPositive ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${isPositive ? '+' : ''}${changePercent.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isPositive ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          if (target.lowerBound != null && target.upperBound != null) ...[
            const SizedBox(height: 20),
            _PriceTargetBar(
              low: target.lowerBound!,
              target: target.target,
              high: target.upperBound!,
            ),
          ],
        ],
      ),
    );
  }
}

/// Visual bar showing low → target → high range for AI price target
class _PriceTargetBar extends StatelessWidget {
  final double low;
  final double target;
  final double high;

  const _PriceTargetBar({
    required this.low,
    required this.target,
    required this.high,
  });

  @override
  Widget build(BuildContext context) {
    final span = high - low;
    final targetRatio = span > 0
        ? ((target - low) / span).clamp(0.0, 1.0)
        : 0.5;

    String fmt(double v) =>
        v >= 1000 ? '\$${v.toStringAsFixed(0)}' : '\$${v.toStringAsFixed(2)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Target Range',
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.5),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            const barH = 6.0;
            const dotR = 6.0;
            final dotLeft = (targetRatio * width - dotR).clamp(
              0.0,
              width - dotR * 2,
            );

            return Column(
              children: [
                SizedBox(
                  height: dotR * 2,
                  child: Stack(
                    children: [
                      // Track
                      Positioned(
                        left: 0,
                        right: 0,
                        top: dotR - barH / 2,
                        height: barH,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF4D6A), Color(0xFF00C896)],
                            ),
                          ),
                        ),
                      ),
                      // Target dot
                      Positioned(
                        left: dotLeft,
                        child: Container(
                          width: dotR * 2,
                          height: dotR * 2,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      fmt(low),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.redAccent.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '▲ ${fmt(target)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      fmt(high),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.greenAccent.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Bullish/Bearish factors card
class _FactorsCard extends StatelessWidget {
  final String title;
  final List<String> factors;
  final IconData icon;
  final Color color;

  const _FactorsCard({
    required this.title,
    required this.factors,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          ...factors.map(
            (factor) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      factor,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withOpacity(0.9),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Risk assessment card
class _RiskAssessmentCard extends StatelessWidget {
  final EnhancedAIAnalysis analysis;

  const _RiskAssessmentCard({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final riskColor = Color(
      int.parse('0xFF${analysis.riskLevel.colorHex.substring(1)}'),
    );

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: riskColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Risk Assessment',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Risk level badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: riskColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: riskColor),
            ),
            child: Text(
              analysis.riskLevel.displayName.toUpperCase(),
              style: TextStyle(
                color: riskColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.1,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Risk explanation
          Text(
            analysis.riskExplanation,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withOpacity(0.9),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Disclaimer card
class _DisclaimerCard extends StatelessWidget {
  final EnhancedAIAnalysis analysis;

  const _DisclaimerCard({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: Colors.white.withOpacity(0.6),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'AI-generated analysis for educational purposes only. Not financial advice. Always do your own research before making investment decisions.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withOpacity(0.6),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
