import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/enhanced_analysis_provider.dart';
import '_analysis_error_card.dart';
import '_analysis_loading_state.dart';
import '_enhanced_analysis_display.dart';
import '_stock_selector.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  String _selectedSymbol = 'AAPL';

  void _onSymbolChanged(String symbol) {
    setState(() => _selectedSymbol = symbol);
  }

  void _refresh() {
    ref.invalidate(enhancedAnalysisProvider(_selectedSymbol));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final analysisAsync = ref.watch(enhancedAnalysisProvider(_selectedSymbol));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Analysis',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'AI-powered market insights and educational analysis.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 14),
                    StockSelector(
                      selectedSymbol: _selectedSymbol,
                      onChanged: _onSymbolChanged,
                    ),
                  ],
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              sliver: SliverToBoxAdapter(
                child: analysisAsync.when(
                  loading: () => AnalysisLoadingState(symbol: _selectedSymbol),
                  error: (error, _) => AnalysisErrorCard(
                    error: error,
                    onRetry: _refresh,
                  ),
                  data: (analysis) => EnhancedAnalysisDisplay(
                    analysis: analysis,
                    onRefresh: _refresh,
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}
