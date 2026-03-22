/// AI Analysis Model - AI-generated market analysis from Claude
library;

class AIAnalysis {
  final String symbol;
  final String analysisText; // Markdown-formatted analysis
  final DateTime timestamp;
  final bool isCached;
  final int? tokensUsed;

  AIAnalysis({
    required this.symbol,
    required this.analysisText,
    required this.timestamp,
    this.isCached = false,
    this.tokensUsed,
  });

  /// Create AIAnalysis from JSON response
  factory AIAnalysis.fromJson(Map<String, dynamic> json) {
    return AIAnalysis(
      symbol: json['symbol'] as String,
      analysisText: json['analysis_text'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isCached: json['is_cached'] as bool? ?? false,
      tokensUsed: json['tokens_used'] as int?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'symbol': symbol,
      'analysis_text': analysisText,
      'timestamp': timestamp.toIso8601String(),
      'is_cached': isCached,
      'tokens_used': tokensUsed,
    };
  }

  /// Get a user-friendly timestamp string (e.g., "3m ago")
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
