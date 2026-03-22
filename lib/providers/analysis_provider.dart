/// Analysis Providers - Riverpod providers for AI-powered analysis
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/enhanced_ai_analysis.dart';
import '../services/claude_analysis_service.dart';

/// Provider for ClaudeAnalysisService (MVP: Direct Claude API)
final claudeAnalysisServiceProvider = Provider<ClaudeAnalysisService>((ref) {
  return ClaudeAnalysisService();
});

/// Provider for AI analysis of a specific symbol
///
/// Usage:
/// ```dart
/// final analysisAsync = ref.watch(aiAnalysisProvider('AAPL'));
/// ```
final aiAnalysisProvider = FutureProvider.family<EnhancedAIAnalysis, String>((
  ref,
  symbol,
) async {
  final service = ref.watch(claudeAnalysisServiceProvider);
  return await service.getStructuredAnalysis(symbol);
});

/// Provider for refreshing analysis (invalidates cache on backend)
///
/// Usage:
/// ```dart
/// await ref.read(refreshAnalysisProvider(symbol).future);
/// ref.invalidate(aiAnalysisProvider(symbol));
/// ```
final refreshAnalysisProvider = FutureProvider.family<void, String>((
  ref,
  symbol,
) async {
  final service = ref.watch(claudeAnalysisServiceProvider);
  await service.clearCache(symbol);
});
