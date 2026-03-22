/// Analysis Error Card - Display error states
library;

import 'package:flutter/material.dart';
import '../../widgets/glass_card.dart';
import '../../services/claude_analysis_service.dart';

class AnalysisErrorCard extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const AnalysisErrorCard({super.key, required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Determine error message and icon
    final String message;
    final IconData icon;
    final Color errorColor;

    if (error is RateLimitException) {
      message = error.toString().replaceFirst('AnalysisException: ', '');
      icon = Icons.timer_off;
      errorColor = Colors.orange;
    } else if (error is ServiceUnavailableException) {
      message = error.toString().replaceFirst('AnalysisException: ', '');
      icon = Icons.cloud_off;
      errorColor = Colors.red;
    } else if (error is AnalysisException) {
      message = error.toString().replaceFirst('AnalysisException: ', '');
      icon = Icons.error_outline;
      errorColor = Colors.red;
    } else {
      message = 'An unexpected error occurred. Please try again.';
      icon = Icons.warning_amber;
      errorColor = Colors.red;
    }

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Error header
          Row(
            children: [
              Icon(icon, color: errorColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Analysis Unavailable',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: errorColor,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Error message
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withOpacity(0.9),
              height: 1.5,
            ),
          ),

          if (onRetry != null) ...[
            const SizedBox(height: 20),

            // Retry button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                  side: BorderSide(color: colorScheme.primary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Help text
          Divider(color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 12),

          Row(
            children: [
              Icon(Icons.help_outline, size: 16, color: Colors.white60),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'If the problem persists, check your network connection or try a different symbol.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
