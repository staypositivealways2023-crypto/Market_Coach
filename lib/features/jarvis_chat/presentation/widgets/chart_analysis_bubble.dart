import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../theme/app_tokens.dart';
import '../../data/vision_repository.dart';

/// Rich card bubble rendered when an assistant message has
/// [MessageType.chartAnalysis]. Shows trend badge, patterns, S/R levels,
/// key signals, scenario card, and full summary — all in one scrollable card.
class ChartAnalysisBubble extends StatefulWidget {
  const ChartAnalysisBubble({
    super.key,
    required this.analysis,
    this.imageB64Preview,
  });

  final ChartAnalysis analysis;

  /// Optional thumbnail from the user's upload (first ~40 KB of base64).
  final String? imageB64Preview;

  @override
  State<ChartAnalysisBubble> createState() => _ChartAnalysisBubbleState();
}

class _ChartAnalysisBubbleState extends State<ChartAnalysisBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.analysis;
    final isBullish = a.trend.toLowerCase() == 'bullish';
    final isBearish = a.trend.toLowerCase() == 'bearish';

    final Color trendColor = isBullish
        ? AppColors.bullish
        : isBearish
            ? AppColors.bearish
            : AppColors.neutral;
    final Color trendBg = isBullish
        ? AppColors.bullishBg
        : isBearish
            ? AppColors.bearishBg
            : AppColors.neutralBg;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm, right: 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(AppRadius.card),
          bottomLeft: Radius.circular(AppRadius.card),
          bottomRight: Radius.circular(AppRadius.card),
        ),
        border: Border.all(color: trendColor.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────────
          _buildHeader(a, trendColor, trendBg),
          const Divider(color: AppColors.divider, height: 1),

          // ── Thumbnail (if available) ────────────────────────────────────
          if (widget.imageB64Preview != null) _buildThumbnail(),

          // ── Key signals row ─────────────────────────────────────────────
          if (a.patterns.isNotEmpty || a.keySignals.isNotEmpty)
            _buildSignalsRow(a),

          // ── S/R levels ──────────────────────────────────────────────────
          if (a.supportLevels.isNotEmpty || a.resistanceLevels.isNotEmpty)
            _buildLevels(a),

          // ── Summary (collapsible) ────────────────────────────────────────
          _buildSummary(a),

          // ── Scenario card (collapsible) ──────────────────────────────────
          if (_expanded) _buildScenarioCard(a),

          // ── Expand / collapse toggle ────────────────────────────────────
          _buildExpandButton(),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader(ChartAnalysis a, Color trendColor, Color trendBg) {
    final pct = (a.confidence * 100).toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          // Icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [trendColor.withValues(alpha: 0.8), trendColor.withValues(alpha: 0.5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.candlestick_chart_rounded,
                size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),

          // Symbol + timeframe
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.symbol == 'Unknown' ? 'Chart Analysis' : a.symbol,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (a.timeframe != 'Unknown')
                  Text(
                    a.timeframe,
                    style: AppText.micro
                        .copyWith(color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),

          // Trend badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: trendBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: trendColor.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  a.trend.toLowerCase() == 'bullish'
                      ? Icons.trending_up_rounded
                      : a.trend.toLowerCase() == 'bearish'
                          ? Icons.trending_down_rounded
                          : Icons.trending_flat_rounded,
                  size: 12,
                  color: trendColor,
                ),
                const SizedBox(width: 4),
                Text(
                  a.trend,
                  style: TextStyle(
                    color: trendColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '$pct%',
                  style: TextStyle(
                    color: trendColor.withValues(alpha: 0.7),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Thumbnail ────────────────────────────────────────────────────────────────

  Widget _buildThumbnail() {
    try {
      final bytes = base64Decode(widget.imageB64Preview!);
      return Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  // ── Signals row (patterns + key signals) ─────────────────────────────────────

  Widget _buildSignalsRow(ChartAnalysis a) {
    final all = [...a.patterns.map((p) => ('pattern', p)),
                  ...a.keySignals.map((s) => ('signal', s))];
    if (all.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: all.map((item) {
          final isPattern = item.$1 == 'pattern';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isPattern
                  ? AppColors.accentWash
                  : AppColors.cautionBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isPattern
                    ? AppColors.accent.withValues(alpha: 0.3)
                    : AppColors.caution.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              item.$2,
              style: TextStyle(
                color: isPattern ? AppColors.accent : AppColors.caution,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Support / Resistance levels ────────────────────────────────────────────

  Widget _buildLevels(ChartAnalysis a) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Row(
        children: [
          if (a.supportLevels.isNotEmpty)
            Expanded(child: _levelGroup('Support', a.supportLevels, AppColors.bullish)),
          if (a.supportLevels.isNotEmpty && a.resistanceLevels.isNotEmpty)
            const SizedBox(width: 8),
          if (a.resistanceLevels.isNotEmpty)
            Expanded(
                child: _levelGroup('Resistance', a.resistanceLevels, AppColors.bearish)),
        ],
      ),
    );
  }

  Widget _levelGroup(String label, List<String> levels, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          ...levels.take(3).map((l) => Text(
                l,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              )),
        ],
      ),
    );
  }

  // ── Summary ──────────────────────────────────────────────────────────────────

  Widget _buildSummary(ChartAnalysis a) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Text(
        a.summary,
        style: AppText.body.copyWith(
          color: AppColors.textSecondary,
          height: 1.55,
        ),
        maxLines: _expanded ? null : 4,
        overflow: _expanded ? null : TextOverflow.ellipsis,
      ),
    );
  }

  // ── Scenario card ────────────────────────────────────────────────────────────

  Widget _buildScenarioCard(ChartAnalysis a) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: AppColors.divider, height: 16),
          Text('Scenario Card',
              style: AppText.micro.copyWith(
                  color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (a.scenario.bull.isNotEmpty)
            _scenarioRow('Bull', a.scenario.bull, AppColors.bullish),
          if (a.scenario.base.isNotEmpty)
            _scenarioRow('Base', a.scenario.base, AppColors.neutral),
          if (a.scenario.bear.isNotEmpty)
            _scenarioRow('Bear', a.scenario.bear, AppColors.bearish),
          if (a.volumeAnalysis.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(color: AppColors.divider, height: 8),
            Text('Volume',
                style: AppText.micro.copyWith(
                    color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(a.volumeAnalysis,
                style: AppText.body
                    .copyWith(color: AppColors.textSecondary, height: 1.5)),
          ],
          if (a.indicatorReadings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Indicators',
                style: AppText.micro.copyWith(
                    color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            ...a.indicatorReadings.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ',
                          style: TextStyle(
                              color: AppColors.accent, fontSize: 12)),
                      Expanded(
                          child: Text(r,
                              style: AppText.body.copyWith(
                                  color: AppColors.textSecondary,
                                  height: 1.45))),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _scenarioRow(String label, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(label,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: AppText.body.copyWith(
                      color: AppColors.textSecondary, height: 1.45))),
        ],
      ),
    );
  }

  // ── Expand / collapse ────────────────────────────────────────────────────────

  Widget _buildExpandButton() {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          color: AppColors.cardInner,
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(AppRadius.card),
            bottomRight: Radius.circular(AppRadius.card),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _expanded ? 'Show less' : 'Full analysis',
              style: AppText.micro
                  .copyWith(color: AppColors.accent, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: 14,
              color: AppColors.accent,
            ),
          ],
        ),
      ),
    );
  }
}
