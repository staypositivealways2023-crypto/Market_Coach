/// Analysis Loading State - Shimmer skeleton while generating analysis
library;

import 'package:flutter/material.dart';
import '../../widgets/glass_card.dart';

class AnalysisLoadingState extends StatefulWidget {
  final String symbol;

  const AnalysisLoadingState({super.key, required this.symbol});

  @override
  State<AnalysisLoadingState> createState() => _AnalysisLoadingStateState();
}

class _AnalysisLoadingStateState extends State<AnalysisLoadingState>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(
      begin: 0.3,
      end: 0.7,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with loading icon
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Analyzing ${widget.symbol}...',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
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
                    Icon(
                      Icons.psychology,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'AI',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Shimmer skeleton lines
          ...List.generate(8, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  return Container(
                    height: 12,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: Colors.white.withOpacity(_animation.value * 0.15),
                    ),
                  );
                },
              ),
            );
          }),

          const SizedBox(height: 8),

          // Loading message
          Center(
            child: Text(
              'This may take 10-15 seconds...',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white60,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
