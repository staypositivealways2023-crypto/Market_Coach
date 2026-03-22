/// AI Analysis Card - Display AI-generated market analysis
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/ai_analysis.dart';
import '../../widgets/glass_card.dart';
import '../../providers/analysis_provider.dart';

class AIAnalysisCard extends ConsumerWidget {
  final AIAnalysis analysis;

  const AIAnalysisCard({super.key, required this.analysis});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.psychology, color: colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'AI Analysis',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: ShapeDecoration(
                  color: colorScheme.primary.withOpacity(0.12),
                  shape: const StadiumBorder(),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (analysis.isCached)
                      Icon(Icons.cached, size: 14, color: colorScheme.primary),
                    if (analysis.isCached) const SizedBox(width: 4),
                    Text(
                      analysis.isCached
                          ? '${analysis.timeAgo} • Cached'
                          : analysis.timeAgo,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Symbol subtitle
          Text(
            analysis.symbol,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 16),

          // Refresh button
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                // Clear cache on backend
                await ref.read(refreshAnalysisProvider(analysis.symbol).future);
                // Invalidate provider to trigger re-fetch
                ref.invalidate(aiAnalysisProvider(analysis.symbol));
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.primary,
                textStyle: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Markdown-formatted analysis
          _MarkdownAnalysis(analysisText: analysis.analysisText),

          const SizedBox(height: 16),

          // Footer
          Divider(color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 12),

          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.white60),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI-generated analysis for educational purposes. Not financial advice.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),

          if (analysis.tokensUsed != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Tokens: ${analysis.tokensUsed}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Simple markdown parser for analysis text
class _MarkdownAnalysis extends StatelessWidget {
  final String analysisText;

  const _MarkdownAnalysis({required this.analysisText});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Split by lines and parse
    final lines = analysisText.split('\n');
    final widgets = <Widget>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      // H2 headers (## Header)
      if (line.startsWith('## ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              line.substring(3),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        );
        continue;
      }

      // H3 headers (### Header)
      if (line.startsWith('### ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Text(
              line.substring(4),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        );
        continue;
      }

      // Bullet points (- Item or * Item)
      if (line.trim().startsWith('- ') || line.trim().startsWith('* ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• ',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Expanded(
                  child: Text(
                    line.trim().substring(2),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      // Bold text (**text**)
      if (line.contains('**')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: _parseBoldText(line, theme),
          ),
        );
        continue;
      }

      // Regular paragraph
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text(
            line,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withOpacity(0.9),
              height: 1.5,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  /// Parse bold text with ** markers
  Widget _parseBoldText(String line, ThemeData theme) {
    final spans = <TextSpan>[];
    final parts = line.split('**');

    for (var i = 0; i < parts.length; i++) {
      if (i.isOdd) {
        // Bold text
        spans.add(
          TextSpan(
            text: parts[i],
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
        );
      } else {
        // Regular text
        spans.add(TextSpan(text: parts[i]));
      }
    }

    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodyMedium?.copyWith(
          color: Colors.white.withOpacity(0.9),
          height: 1.5,
        ),
        children: spans,
      ),
    );
  }
}
