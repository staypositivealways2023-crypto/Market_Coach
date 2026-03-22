/// Analysis Cache Service - Cache AI analysis results to avoid redundant API calls
///
/// Saves analysis to SharedPreferences with 1-hour expiration
library;

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/enhanced_ai_analysis.dart';

class AnalysisCacheService {
  static const String _cachePrefix = 'analysis_cache_';
  static const int _cacheExpirationHours = 1; // Cache for 1 hour

  /// Save analysis to cache
  Future<void> saveAnalysis(EnhancedAIAnalysis analysis) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getCacheKey(analysis.symbol);

      final jsonData = analysis.toJson();
      final jsonString = jsonEncode(jsonData);

      await prefs.setString(key, jsonString);
      print('✅ Analysis cached for ${analysis.symbol}');
    } catch (e) {
      print('⚠️ Failed to cache analysis: $e');
      // Don't throw - caching is optional
    }
  }

  /// Get cached analysis if available and not expired
  Future<EnhancedAIAnalysis?> getCachedAnalysis(String symbol) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getCacheKey(symbol);

      final jsonString = prefs.getString(key);
      if (jsonString == null) {
        print('ℹ️ No cached analysis for $symbol');
        return null;
      }

      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      final analysis = EnhancedAIAnalysis.fromJson(jsonData);

      // Check if cache is expired
      final age = DateTime.now().difference(analysis.timestamp);
      if (age.inHours >= _cacheExpirationHours) {
        print('⏰ Cached analysis for $symbol expired (${age.inHours}h old)');
        await clearCache(symbol); // Clean up expired cache
        return null;
      }

      print('✅ Using cached analysis for $symbol (${analysis.timeAgo})');
      return analysis.copyWith(isCached: true);
    } catch (e) {
      print('⚠️ Failed to load cached analysis: $e');
      return null;
    }
  }

  /// Clear cache for a specific symbol
  Future<void> clearCache(String symbol) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getCacheKey(symbol);
      await prefs.remove(key);
      print('🗑️ Cleared cache for $symbol');
    } catch (e) {
      print('⚠️ Failed to clear cache: $e');
    }
  }

  /// Clear all cached analyses
  Future<void> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      for (final key in keys) {
        if (key.startsWith(_cachePrefix)) {
          await prefs.remove(key);
        }
      }

      print('🗑️ Cleared all analysis cache');
    } catch (e) {
      print('⚠️ Failed to clear all cache: $e');
    }
  }

  /// Get cache key for a symbol
  String _getCacheKey(String symbol) {
    return '$_cachePrefix${symbol.toUpperCase()}';
  }

  /// Check if cache exists for symbol
  Future<bool> hasCachedAnalysis(String symbol) async {
    final analysis = await getCachedAnalysis(symbol);
    return analysis != null;
  }
}

/// Extension to add copyWith method
extension EnhancedAIAnalysisExtension on EnhancedAIAnalysis {
  EnhancedAIAnalysis copyWith({
    String? symbol,
    DateTime? timestamp,
    bool? isCached,
    int? sentimentScore,
    Recommendation? recommendation,
    String? summaryText,
    double? currentPrice,
    PriceTarget? priceTarget,
    List<String>? bullishFactors,
    List<String>? bearishFactors,
    RiskLevel? riskLevel,
    String? riskExplanation,
    String? technicalSummary,
    String? fullAnalysisMarkdown,
  }) {
    return EnhancedAIAnalysis(
      symbol: symbol ?? this.symbol,
      timestamp: timestamp ?? this.timestamp,
      isCached: isCached ?? this.isCached,
      sentimentScore: sentimentScore ?? this.sentimentScore,
      recommendation: recommendation ?? this.recommendation,
      summaryText: summaryText ?? this.summaryText,
      currentPrice: currentPrice ?? this.currentPrice,
      priceTarget: priceTarget ?? this.priceTarget,
      bullishFactors: bullishFactors ?? this.bullishFactors,
      bearishFactors: bearishFactors ?? this.bearishFactors,
      riskLevel: riskLevel ?? this.riskLevel,
      riskExplanation: riskExplanation ?? this.riskExplanation,
      technicalSummary: technicalSummary ?? this.technicalSummary,
      fullAnalysisMarkdown: fullAnalysisMarkdown ?? this.fullAnalysisMarkdown,
    );
  }
}
