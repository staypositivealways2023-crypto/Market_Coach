/// Enhanced Analysis Providers - Riverpod providers for enhanced AI analysis with caching
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/enhanced_ai_analysis.dart';
import '../services/enhanced_analysis_service.dart';

/// Provider for EnhancedAnalysisService
final enhancedAnalysisServiceProvider = Provider<EnhancedAnalysisService>((
  ref,
) {
  return EnhancedAnalysisService();
});

/// Provider for enhanced AI analysis of a specific symbol
///
/// Automatically uses cached data if available (< 1 hour old)
///
/// Usage:
/// ```dart
/// final analysisAsync = ref.watch(enhancedAnalysisProvider('AAPL'));
/// ```
final enhancedAnalysisProvider =
    FutureProvider.family<EnhancedAIAnalysis, String>((ref, symbol) async {
      final service = ref.watch(enhancedAnalysisServiceProvider);
      return await service.getAnalysis(symbol, forceRefresh: false);
    });

/// Provider for forcing fresh analysis (bypasses cache)
///
/// Usage:
/// ```dart
/// await ref.read(refreshEnhancedAnalysisProvider(symbol).future);
/// ref.invalidate(enhancedAnalysisProvider(symbol));
/// ```
final refreshEnhancedAnalysisProvider =
    FutureProvider.family<EnhancedAIAnalysis, String>((ref, symbol) async {
      final service = ref.watch(enhancedAnalysisServiceProvider);
      return await service.getAnalysis(symbol, forceRefresh: true);
    });
