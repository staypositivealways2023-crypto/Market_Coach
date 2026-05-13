/// ProbabilisticCard — Phase 4 widget.
///
/// Displays Monte Carlo percentile price fan (p10 / p50 / p90),
/// Value-at-Risk, black-swan badge, Bayesian price target with credible
/// interval, and an optional Reddit sentiment strip.
///
/// Designed for insertion in _buildOverviewTab of AssetChartScreen.
/// Dark theme only — seed #12A28C, bg #0D131A, card #111925.

library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/probabilistic_data.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public entry point
// ─────────────────────────────────────────────────────────────────────────────

class ProbabilisticCard extends StatelessWidget {
  final ProbabilisticData data;

  const ProbabilisticCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111925),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(data: data),
          const Divider(height: 1, color: Color(0xFF1E2A38)),
          _PercentileFan(data: data),
          const Divider(height: 1, color: Color(0xFF1E2A38)),
          _MetricsRow(data: data),
          if (data.reddit != null) ...[
            const Divider(height: 1, color: Color(0xFF1E2A38)),
            _RedditStrip(reddit: data.reddit!),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final ProbabilisticData data;
  const _Header({required this.data});

  @override
  Widget build(BuildContext context) {
    final conviction = data.overallConviction;
    final convColor  = conviction >= 65
        ? const Color(0xFF12A28C)
        : conviction >= 45
            ? const Color(0xFFF5A623)
            : const Color(0xFFE05252);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          const Text(
            'Probabilistic Outlook',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          if (data.monteCarlo.blackSwanProne) ...[
            const _BlackSwanBadge(),
            const SizedBox(width: 8),
          ],
          _ConvictionBadge(conviction: conviction, color: convColor),
        ],
      ),
    );
  }
}

class _BlackSwanBadge extends StatelessWidget {
  const _BlackSwanBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF3A1A1A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE05252).withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Text('🦢', style: TextStyle(fontSize: 10)),
          SizedBox(width: 4),
          Text(
            'Fat Tail',
            style: TextStyle(
              color: Color(0xFFE05252),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConvictionBadge extends StatelessWidget {
  final int conviction;
  final Color color;
  const _ConvictionBadge({required this.conviction, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        'Conviction $conviction/100',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Percentile fan bar
// ─────────────────────────────────────────────────────────────────────────────

class _PercentileFan extends StatelessWidget {
  final ProbabilisticData data;
  const _PercentileFan({required this.data});

  @override
  Widget build(BuildContext context) {
    final mc      = data.monteCarlo;
    final current = data.currentPrice;

    final p10 = mc.p10 ?? current;
    final p50 = mc.p50 ?? current;
    final p90 = mc.p90 ?? current;

    // Horizon label
    final horizonLabel = '${data.horizonDays}d';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Price Fan ($horizonLabel horizon)',
                style: const TextStyle(
                  color: Color(0xFF8A9BB0),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                'MC · 1,000 paths',
                style: const TextStyle(
                  color: Color(0xFF4A5A6E),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _FanBar(current: current, p10: p10, p50: p50, p90: p90),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _PctLabel('Bear\n\$${p10.toStringAsFixed(2)}', const Color(0xFFE05252)),
              _PctLabel('Median\n\$${p50.toStringAsFixed(2)}', const Color(0xFF8A9BB0), center: true),
              _PctLabel('Bull\n\$${p90.toStringAsFixed(2)}', const Color(0xFF12A28C), right: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _FanBar extends StatelessWidget {
  final double current, p10, p50, p90;
  const _FanBar({
    required this.current,
    required this.p10,
    required this.p50,
    required this.p90,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      final width = constraints.maxWidth;

      // Map prices to x-positions (0..1) within the bar
      final lo  = math.min(p10, current) * 0.97;
      final hi  = math.max(p90, current) * 1.03;
      final rng = hi - lo;

      double xOf(double price) => ((price - lo) / rng).clamp(0.0, 1.0);

      final xCurrent = xOf(current);
      final xP10     = xOf(p10);
      final xP50     = xOf(p50);
      final xP90     = xOf(p90);

      return SizedBox(
        height: 28,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            // Background rail
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            // p10–p90 range fill (bear zone: p10→p50)
            Positioned(
              left: xP10 * width,
              width: (xP50 - xP10) * width,
              top: 0, bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0x33E05252), Color(0x228A9BB0)],
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            // p50–p90 bull zone
            Positioned(
              left: xP50 * width,
              width: (xP90 - xP50) * width,
              top: 0, bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0x228A9BB0), Color(0x2212A28C)],
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            // p10 marker
            Positioned(
              left: xP10 * width - 1,
              child: Container(
                width: 2,
                height: 28,
                color: const Color(0xFFE05252),
              ),
            ),
            // p90 marker
            Positioned(
              left: xP90 * width - 1,
              child: Container(
                width: 2,
                height: 28,
                color: const Color(0xFF12A28C),
              ),
            ),
            // p50 marker
            Positioned(
              left: xP50 * width - 1,
              child: Container(
                width: 2,
                height: 28,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
            // Current price diamond
            Positioned(
              left: xCurrent * width - 6,
              top: 6, bottom: 6,
              child: Container(
                width: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFF12A28C),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF12A28C).withOpacity(0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _PctLabel extends StatelessWidget {
  final String text;
  final Color color;
  final bool center;
  final bool right;
  const _PctLabel(this.text, this.color, {this.center = false, this.right = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: center
          ? TextAlign.center
          : right
              ? TextAlign.right
              : TextAlign.left,
      style: TextStyle(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Metrics row: VaR, CVaR, Bayesian target
// ─────────────────────────────────────────────────────────────────────────────

class _MetricsRow extends StatelessWidget {
  final ProbabilisticData data;
  const _MetricsRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final mc    = data.monteCarlo;
    final bayes = data.bayesian;

    final varStr  = mc.var95  != null ? '${mc.var95!.toStringAsFixed(1)}%' : '—';
    final cvarStr = mc.cvar95 != null ? '${mc.cvar95!.toStringAsFixed(1)}%' : '—';
    final bayesStr = '\$${bayes.posteriorMean.toStringAsFixed(2)}';

    // Bayesian credible interval
    final ci    = bayes.credibleInterval90;
    final ciStr = ci.length >= 2
        ? '\$${ci[0].toStringAsFixed(1)} – \$${ci[1].toStringAsFixed(1)}'
        : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          _Metric(
            label: 'VaR 95',
            value: varStr,
            sub: 'max downside',
            valueColor: const Color(0xFFE05252),
          ),
          _divider(),
          _Metric(
            label: 'CVaR 95',
            value: cvarStr,
            sub: 'tail loss',
            valueColor: const Color(0xFFE05252),
          ),
          _divider(),
          _Metric(
            label: 'Bayesian Target',
            value: bayesStr,
            sub: ciStr,
            valueColor: const Color(0xFF12A28C),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 36,
        color: const Color(0xFF1E2A38),
        margin: const EdgeInsets.symmetric(horizontal: 12),
      );
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color valueColor;
  const _Metric({
    required this.label,
    required this.value,
    required this.sub,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8A9BB0),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (sub.isNotEmpty)
            Text(
              sub,
              style: const TextStyle(
                color: Color(0xFF4A5A6E),
                fontSize: 9,
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reddit sentiment strip
// ─────────────────────────────────────────────────────────────────────────────

class _RedditStrip extends StatelessWidget {
  final RedditSentimentData reddit;
  const _RedditStrip({required this.reddit});

  @override
  Widget build(BuildContext context) {
    final label = reddit.sentimentLabel;
    final score = reddit.sentimentScore;
    final mentions = reddit.mentionCount;

    final labelColor = label == 'bullish'
        ? const Color(0xFF12A28C)
        : label == 'bearish'
            ? const Color(0xFFE05252)
            : const Color(0xFF8A9BB0);

    final labelText = label[0].toUpperCase() + label.substring(1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Row(
        children: [
          const Text(
            'Reddit  ',
            style: TextStyle(
              color: Color(0xFF8A9BB0),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            labelText,
            style: TextStyle(
              color: labelColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            score >= 0
                ? '+${score.toStringAsFixed(2)}'
                : score.toStringAsFixed(2),
            style: TextStyle(color: labelColor, fontSize: 10),
          ),
          const Spacer(),
          Text(
            '$mentions mention${mentions == 1 ? '' : 's'}',
            style: const TextStyle(
              color: Color(0xFF4A5A6E),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
