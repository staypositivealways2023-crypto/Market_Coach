/// Enhanced Analysis Service - Caching wrapper around ClaudeAnalysisService
library;

import 'claude_analysis_service.dart';
import 'analysis_cache_service.dart';
import '../models/enhanced_ai_analysis.dart';

class EnhancedAnalysisService {
  final ClaudeAnalysisService _claudeService = ClaudeAnalysisService();
  final AnalysisCacheService _cacheService = AnalysisCacheService();

  Future<EnhancedAIAnalysis> getAnalysis(
    String symbol, {
    bool forceRefresh = false,
  }) async {
    // Check cache first (skip if force refresh)
    if (!forceRefresh) {
      final cached = await _cacheService.getCachedAnalysis(symbol);
      if (cached != null) return cached;
    }

    // Fetch fresh analysis from Claude (includes stock data internally)
    final analysis = await _claudeService.getStructuredAnalysis(symbol);

    // Save to cache
    await _cacheService.saveAnalysis(analysis);

    return analysis;
  }

  Future<void> clearCache(String symbol) async {
    await _cacheService.clearCache(symbol);
  }
}
