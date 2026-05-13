/// Claude Analysis Service
///
/// All analysis is performed server-side via the Python backend.
/// The Flutter app never calls Claude or any third-party AI API directly.
library;

import 'dart:convert';
import '../models/enhanced_ai_analysis.dart';
import 'backend_service.dart';

class AnalysisException implements Exception {
  final String message;
  final int? statusCode;
  AnalysisException(this.message, {this.statusCode});
  @override
  String toString() => 'AnalysisException: $message';
}

class RateLimitException extends AnalysisException {
  RateLimitException()
    : super(
        'Daily analysis limit reached. Try again tomorrow.',
        statusCode: 429,
      );
}

class ServiceUnavailableException extends AnalysisException {
  ServiceUnavailableException()
    : super('AI analysis service is temporarily unavailable.', statusCode: 503);
}

class ClaudeAnalysisService {
  final BackendService _backendService = BackendService();

  /// Returns structured AI analysis for [symbol] via the backend.
  Future<EnhancedAIAnalysis> getStructuredAnalysis(String symbol) async {
    final data = await _backendService.getStructuredAnalysis(symbol);
    if (data == null) {
      throw AnalysisException('AI analysis unavailable. Please try again later.');
    }
    // backend_service now wraps errors as {'error': reason, 'status': code}.
    if (data.containsKey('error')) {
      final msg = data['error']?.toString() ?? 'AI analysis unavailable.';
      final status = data['status'] as int? ?? 0;
      if (status == 429) throw RateLimitException();
      if (status == 503) throw ServiceUnavailableException();
      throw AnalysisException(msg, statusCode: status);
    }
    final price = (data['current_price'] as num?)?.toDouble() ?? 0.0;
    return _parseJsonResponse(jsonEncode(data), price, symbol);
  }

  /// Parse backend JSON response into EnhancedAIAnalysis
  EnhancedAIAnalysis _parseJsonResponse(
    String rawJson,
    double currentPrice,
    String symbol,
  ) {
    try {
      var clean = rawJson.trim();
      if (clean.startsWith('```')) {
        clean = clean.replaceAll(RegExp(r'```[a-z]*\n?'), '').trim();
      }

      final json = jsonDecode(clean) as Map<String, dynamic>;

      final sentimentScore = (json['sentiment_score'] as num?)?.toInt() ?? 50;
      final rec = _parseRecommendation(json['recommendation'] as String? ?? 'HOLD');
      final summary = json['summary'] as String? ?? 'Analysis unavailable.';

      final bullish =
          (json['bullish_factors'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final bearish =
          (json['bearish_factors'] as List?)?.map((e) => e.toString()).toList() ?? [];

      var targetVal = (json['price_target'] as num?)?.toDouble();
      var lowVal = (json['price_low'] as num?)?.toDouble();
      var highVal = (json['price_high'] as num?)?.toDouble();

      // Sanitize: clamp to ±20% of current price; fix inverted low/high
      if (targetVal != null) {
        final min = currentPrice * 0.80;
        final max = currentPrice * 1.20;
        if (targetVal < min || targetVal > max) {
          final bias = (sentimentScore - 50) / 50.0;
          targetVal = double.parse(
            (currentPrice * (1 + bias * 0.07)).toStringAsFixed(2),
          );
        }
      }
      if (lowVal != null && lowVal >= currentPrice) {
        lowVal = double.parse((currentPrice * 0.96).toStringAsFixed(2));
      }
      if (highVal != null && highVal <= currentPrice) {
        highVal = double.parse((currentPrice * 1.04).toStringAsFixed(2));
      }

      final priceTarget = targetVal != null
          ? PriceTarget(
              target: targetVal,
              lowerBound: lowVal,
              upperBound: highVal,
              timeframeDays: 7,
            )
          : null;

      final riskLevel = _parseRiskLevel(json['risk_level'] as String? ?? 'MEDIUM');
      final riskExplanation =
          json['risk_explanation'] as String? ?? 'Standard market risk applies.';
      final technicalNote = json['technical_note'] as String?;

      return EnhancedAIAnalysis(
        symbol: symbol.toUpperCase(),
        timestamp: DateTime.now(),
        sentimentScore: sentimentScore.clamp(0, 100),
        recommendation: rec,
        summaryText: summary,
        currentPrice: currentPrice,
        priceTarget: priceTarget,
        bullishFactors: bullish,
        bearishFactors: bearish,
        riskLevel: riskLevel,
        riskExplanation: riskExplanation,
        technicalSummary: technicalNote,
        fullAnalysisMarkdown: rawJson,
      );
    } catch (e) {
      throw AnalysisException('Failed to parse analysis response: $e');
    }
  }

  Recommendation _parseRecommendation(String str) {
    switch (str.toUpperCase().trim()) {
      case 'STRONG_BUY':  return Recommendation.strongBuy;
      case 'BUY':         return Recommendation.buy;
      case 'SELL':        return Recommendation.sell;
      case 'STRONG_SELL': return Recommendation.strongSell;
      default:            return Recommendation.hold;
    }
  }

  RiskLevel _parseRiskLevel(String str) {
    switch (str.toUpperCase().trim()) {
      case 'LOW':       return RiskLevel.low;
      case 'HIGH':      return RiskLevel.high;
      case 'VERY_HIGH': return RiskLevel.veryHigh;
      default:          return RiskLevel.medium;
    }
  }

  /// Legacy method kept for compatibility
  Future<void> clearCache(String symbol) async {}
}
