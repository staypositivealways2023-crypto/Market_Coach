/// Enhanced AI Analysis Model - Structured analysis data with sentiment scores
///
/// This model provides a clear, structured representation of AI analysis
/// instead of just markdown text.
library;

class EnhancedAIAnalysis {
  final String symbol;
  final DateTime timestamp;
  final bool isCached;

  // Overall Assessment
  final int
  sentimentScore; // 0-100 (0=very bearish, 50=neutral, 100=very bullish)
  final Recommendation recommendation;
  final String summaryText;

  // Price Analysis
  final double currentPrice;
  final PriceTarget? priceTarget;

  // Factors
  final List<String> bullishFactors;
  final List<String> bearishFactors;

  // Risk Assessment
  final RiskLevel riskLevel;
  final String riskExplanation;

  // Technical Summary
  final String? technicalSummary;

  // Original markdown (for backup/full text)
  final String fullAnalysisMarkdown;

  EnhancedAIAnalysis({
    required this.symbol,
    required this.timestamp,
    required this.sentimentScore,
    required this.recommendation,
    required this.summaryText,
    required this.currentPrice,
    this.priceTarget,
    required this.bullishFactors,
    required this.bearishFactors,
    required this.riskLevel,
    required this.riskExplanation,
    this.technicalSummary,
    required this.fullAnalysisMarkdown,
    this.isCached = false,
  });

  /// Get sentiment as text
  String get sentimentText {
    if (sentimentScore >= 75) return 'Very Bullish';
    if (sentimentScore >= 60) return 'Bullish';
    if (sentimentScore >= 40) return 'Neutral';
    if (sentimentScore >= 25) return 'Bearish';
    return 'Very Bearish';
  }

  /// Get sentiment color
  String get sentimentColorHex {
    if (sentimentScore >= 75) return '#00C853'; // Dark green
    if (sentimentScore >= 60) return '#4CAF50'; // Green
    if (sentimentScore >= 40) return '#FFC107'; // Amber
    if (sentimentScore >= 25) return '#FF5722'; // Deep orange
    return '#D32F2F'; // Red
  }

  /// Convert to JSON for caching
  Map<String, dynamic> toJson() {
    return {
      'symbol': symbol,
      'timestamp': timestamp.toIso8601String(),
      'is_cached': isCached,
      'sentiment_score': sentimentScore,
      'recommendation': recommendation.toString().split('.').last,
      'summary_text': summaryText,
      'current_price': currentPrice,
      'price_target': priceTarget?.toJson(),
      'bullish_factors': bullishFactors,
      'bearish_factors': bearishFactors,
      'risk_level': riskLevel.toString().split('.').last,
      'risk_explanation': riskExplanation,
      'technical_summary': technicalSummary,
      'full_analysis_markdown': fullAnalysisMarkdown,
    };
  }

  /// Create from JSON (for caching)
  factory EnhancedAIAnalysis.fromJson(Map<String, dynamic> json) {
    return EnhancedAIAnalysis(
      symbol: json['symbol'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isCached: json['is_cached'] as bool? ?? false,
      sentimentScore: json['sentiment_score'] as int,
      recommendation: _parseRecommendation(json['recommendation'] as String),
      summaryText: json['summary_text'] as String,
      currentPrice: (json['current_price'] as num).toDouble(),
      priceTarget: json['price_target'] != null
          ? PriceTarget.fromJson(json['price_target'] as Map<String, dynamic>)
          : null,
      bullishFactors: (json['bullish_factors'] as List).cast<String>(),
      bearishFactors: (json['bearish_factors'] as List).cast<String>(),
      riskLevel: _parseRiskLevel(json['risk_level'] as String),
      riskExplanation: json['risk_explanation'] as String,
      technicalSummary: json['technical_summary'] as String?,
      fullAnalysisMarkdown: json['full_analysis_markdown'] as String,
    );
  }

  static Recommendation _parseRecommendation(String str) {
    switch (str.toUpperCase()) {
      case 'STRONG_BUY':
        return Recommendation.strongBuy;
      case 'BUY':
        return Recommendation.buy;
      case 'HOLD':
        return Recommendation.hold;
      case 'SELL':
        return Recommendation.sell;
      case 'STRONG_SELL':
        return Recommendation.strongSell;
      default:
        return Recommendation.hold;
    }
  }

  static RiskLevel _parseRiskLevel(String str) {
    switch (str.toUpperCase()) {
      case 'LOW':
        return RiskLevel.low;
      case 'MEDIUM':
        return RiskLevel.medium;
      case 'HIGH':
        return RiskLevel.high;
      case 'VERY_HIGH':
        return RiskLevel.veryHigh;
      default:
        return RiskLevel.medium;
    }
  }

  /// Get time ago string
  String get timeAgo {
    final diff = DateTime.now().difference(timestamp);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}

/// Trading recommendation
enum Recommendation { strongBuy, buy, hold, sell, strongSell }

extension RecommendationExtension on Recommendation {
  String get displayName {
    switch (this) {
      case Recommendation.strongBuy:
        return 'Bullish signal (high confidence)';
      case Recommendation.buy:
        return 'Bullish signal';
      case Recommendation.hold:
        return 'Neutral';
      case Recommendation.sell:
        return 'Bearish signal';
      case Recommendation.strongSell:
        return 'Bearish signal (high confidence)';
    }
  }

  String get colorHex {
    switch (this) {
      case Recommendation.strongBuy:
        return '#00C853';
      case Recommendation.buy:
        return '#4CAF50';
      case Recommendation.hold:
        return '#FFC107';
      case Recommendation.sell:
        return '#FF5722';
      case Recommendation.strongSell:
        return '#D32F2F';
    }
  }
}

/// Price target with range
class PriceTarget {
  final double target;
  final double? lowerBound;
  final double? upperBound;
  final int timeframeDays;

  PriceTarget({
    required this.target,
    this.lowerBound,
    this.upperBound,
    this.timeframeDays = 7, // Default 1 week
  });

  Map<String, dynamic> toJson() {
    return {
      'target': target,
      'lower_bound': lowerBound,
      'upper_bound': upperBound,
      'timeframe_days': timeframeDays,
    };
  }

  factory PriceTarget.fromJson(Map<String, dynamic> json) {
    return PriceTarget(
      target: (json['target'] as num).toDouble(),
      lowerBound: json['lower_bound'] != null
          ? (json['lower_bound'] as num).toDouble()
          : null,
      upperBound: json['upper_bound'] != null
          ? (json['upper_bound'] as num).toDouble()
          : null,
      timeframeDays: json['timeframe_days'] as int? ?? 7,
    );
  }
}

/// Risk level assessment
enum RiskLevel { low, medium, high, veryHigh }

extension RiskLevelExtension on RiskLevel {
  String get displayName {
    switch (this) {
      case RiskLevel.low:
        return 'Low Risk';
      case RiskLevel.medium:
        return 'Medium Risk';
      case RiskLevel.high:
        return 'High Risk';
      case RiskLevel.veryHigh:
        return 'Very High Risk';
    }
  }

  String get colorHex {
    switch (this) {
      case RiskLevel.low:
        return '#4CAF50';
      case RiskLevel.medium:
        return '#FFC107';
      case RiskLevel.high:
        return '#FF5722';
      case RiskLevel.veryHigh:
        return '#D32F2F';
    }
  }
}
