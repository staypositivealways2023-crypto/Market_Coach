/// Analysis Screen — AI-powered stock analysis with symbol search.
///
/// Users can search any symbol or pick from their watchlist to trigger
/// a full EnhancedAIAnalysis via ClaudeAnalysisService.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enhanced_ai_analysis.dart';
import '../../providers/analysis_provider.dart';
import '../../providers/market_data_provider.dart';
import './_enhanced_analysis_display.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  final _controller = TextEditingController();
  String? _activeSymbol;

  static const _suggestions = ['AAPL', 'MSFT', 'NVDA', 'TSLA', 'BTC', 'ETH', 'AMZN', 'GOOGL'];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _analyze(String symbol) {
    final s = symbol.trim().toUpperCase();
    if (s.isEmpty) return;
    setState(() => _activeSymbol = s);
    _controller.text = s;
    FocusScope.of(context).unfocus();
  }

  void _refresh() {
    if (_activeSymbol == null) return;
    ref.invalidate(aiAnalysisProvider(_activeSymbol!));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'AI Analysis',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20),
        ),
        actions: [
          if (_activeSymbol != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              tooltip: 'Refresh analysis',
              onPressed: _refresh,
            ),
        ],
      ),
      body: Column(
        children: [
          _SearchBar(controller: _controller, onSubmit: _analyze),
          _WatchlistChips(onTap: _analyze),
          const SizedBox(height: 4),
          Expanded(
            child: _activeSymbol == null
                ? _SuggestionGrid(onTap: _analyze, suggestions: _suggestions)
                : _AnalysisBody(symbol: _activeSymbol!, onRefresh: _refresh),
          ),
        ],
      ),
    );
  }
}

// ── Search bar ────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onSubmit});
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: controller,
        textCapitalization: TextCapitalization.characters,
        style: const TextStyle(color: Colors.white),
        onSubmitted: onSubmit,
        decoration: InputDecoration(
          hintText: 'Enter symbol — AAPL, BTC, TSLA…',
          hintStyle: const TextStyle(color: Colors.white38),
          filled: true,
          fillColor: const Color(0xFF1A2232),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          prefixIcon: const Icon(Icons.search, color: Colors.white38),
          suffixIcon: IconButton(
            icon: const Icon(Icons.arrow_forward_rounded, color: Color(0xFF12A28C)),
            onPressed: () => onSubmit(controller.text),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

// ── Watchlist chips ───────────────────────────────────────────────────────────

class _WatchlistChips extends ConsumerWidget {
  const _WatchlistChips({required this.onTap});
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watchlistAsync = ref.watch(watchlistProvider);
    return watchlistAsync.when(
      data: (symbols) {
        if (symbols.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: symbols.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => ActionChip(
              label: Text(symbols[i], style: const TextStyle(fontSize: 12, color: Colors.white70)),
              backgroundColor: const Color(0xFF1A2232),
              side: const BorderSide(color: Color(0xFF2A3444)),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              onPressed: () => onTap(symbols[i]),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// ── Suggestion grid (empty state) ─────────────────────────────────────────────

class _SuggestionGrid extends StatelessWidget {
  const _SuggestionGrid({required this.onTap, required this.suggestions});
  final ValueChanged<String> onTap;
  final List<String> suggestions;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Popular symbols',
            style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 0.5),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: suggestions.map((s) => _SymbolTile(symbol: s, onTap: onTap)).toList(),
          ),
          const SizedBox(height: 32),
          const Center(
            child: Column(
              children: [
                Icon(Icons.auto_awesome, color: Color(0xFF12A28C), size: 40),
                SizedBox(height: 12),
                Text(
                  'AI-powered analysis',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 6),
                Text(
                  'Sentiment score · Price target · Bull/Bear factors\nRisk assessment · Technical summary',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SymbolTile extends StatelessWidget {
  const _SymbolTile({required this.symbol, required this.onTap});
  final String symbol;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(symbol),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2232),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2A3444)),
        ),
        child: Text(symbol, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ── Analysis body ─────────────────────────────────────────────────────────────

class _AnalysisBody extends ConsumerWidget {
  const _AnalysisBody({required this.symbol, required this.onRefresh});
  final String symbol;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysisAsync = ref.watch(aiAnalysisProvider(symbol));
    return analysisAsync.when(
      loading: () => const _LoadingState(),
      error: (e, _) => _ErrorState(symbol: symbol, error: e.toString(), onRetry: onRefresh),
      data: (analysis) => SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          children: [
            _SymbolHeader(symbol: symbol, analysis: analysis),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: EnhancedAnalysisDisplay(analysis: analysis, onRefresh: onRefresh),
            ),
          ],
        ),
      ),
    );
  }
}

class _SymbolHeader extends StatelessWidget {
  const _SymbolHeader({required this.symbol, required this.analysis});
  final String symbol;
  final EnhancedAIAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(symbol, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                Text(
                  analysis.isCached ? 'Cached · ${_ago(analysis.timestamp)}' : 'Live analysis',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _sentimentColor(analysis.sentimentScore).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _sentimentColor(analysis.sentimentScore).withValues(alpha: 0.4)),
            ),
            child: Text(
              analysis.sentimentText,
              style: TextStyle(color: _sentimentColor(analysis.sentimentScore), fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Color _sentimentColor(int score) {
    if (score >= 60) return const Color(0xFF12A28C);
    if (score >= 40) return Colors.amber;
    return Colors.redAccent;
  }

  String _ago(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF12A28C)),
          SizedBox(height: 16),
          Text('Running AI analysis…', style: TextStyle(color: Colors.white54)),
          SizedBox(height: 6),
          Text('This takes 10–20 seconds', style: TextStyle(color: Colors.white30, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.symbol, required this.error, required this.onRetry});
  final String symbol;
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            Text('Analysis failed for $symbol', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF12A28C)),
            ),
          ],
        ),
      ),
    );
  }
}
