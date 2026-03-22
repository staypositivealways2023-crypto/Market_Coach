/// Claude Analysis Service - Direct Claude API integration, returns JSON
///
/// Asks Claude to return structured JSON directly. No parsing guesswork.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/enhanced_ai_analysis.dart';
import 'backend_service.dart';
import 'stock_data_service.dart';

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
  final StockDataService _stockDataService = StockDataService();
  final BackendService _backendService = BackendService();

  /// Fetch stock data + call Claude + return structured EnhancedAIAnalysis.
  /// Falls back to backend-proxied analysis if no direct API key is configured.
  Future<EnhancedAIAnalysis> getStructuredAnalysis(String symbol) async {
    if (!APIConfig.isConfigured) {
      return _getAnalysisFromBackend(symbol);
    }

    // 1. Fetch stock data
    final stockData = await _stockDataService.fetchStockData(symbol);

    // 2. Build prompt asking for JSON
    final prompt = _buildJsonPrompt(stockData);

    // 3. Call Claude
    final rawJson = await _callClaudeAPI(prompt);

    // 4. Parse JSON directly
    return _parseJsonResponse(rawJson, stockData.currentPrice, symbol);
  }

  /// Backend-proxied analysis — used when no direct Claude key is configured
  Future<EnhancedAIAnalysis> _getAnalysisFromBackend(String symbol) async {
    final data = await _backendService.getStructuredAnalysis(symbol);
    if (data == null) {
      throw AnalysisException(
        'AI analysis unavailable. Start the backend or configure a Claude API key.',
      );
    }
    final price = (data['current_price'] as num?)?.toDouble() ?? 0.0;
    return _parseJsonResponse(jsonEncode(data), price, symbol);
  }

  /// Build prompt that asks Claude to respond with strict JSON
  String _buildJsonPrompt(StockData data) {
    final buffer = StringBuffer();

    buffer.writeln(
      'You are a financial analyst. Analyze ${data.symbol} and respond ONLY with a JSON object - no explanation, no markdown, no code fences, just raw JSON.',
    );
    buffer.writeln();
    buffer.writeln('MARKET DATA:');
    buffer.writeln('Symbol: ${data.symbol}');
    buffer.writeln('Current Price: \$${data.currentPrice.toStringAsFixed(2)}');

    if (data.changePercent != null) {
      buffer.writeln(
        'Today Change: ${data.changePercent!.toStringAsFixed(2)}%',
      );
    }
    if (data.dayHigh != null && data.dayLow != null) {
      buffer.writeln(
        'Day Range: \$${data.dayLow!.toStringAsFixed(2)} - \$${data.dayHigh!.toStringAsFixed(2)}',
      );
    }
    if (data.fiftyTwoWeekHigh != null && data.fiftyTwoWeekLow != null) {
      buffer.writeln(
        '52-Week Range: \$${data.fiftyTwoWeekLow!.toStringAsFixed(2)} - \$${data.fiftyTwoWeekHigh!.toStringAsFixed(2)}',
      );
      final pos = data.fiftyTwoWeekPosition;
      if (pos != null)
        buffer.writeln('52-Week Position: ${pos.toStringAsFixed(0)}%');
    }
    if (data.volume != null) {
      buffer.writeln('Volume: ${data.volume}');
    }
    if (data.peRatio != null) {
      buffer.writeln('P/E Ratio: ${data.peRatio!.toStringAsFixed(1)}');
    }
    if (data.priceHistory.isNotEmpty) {
      final firstPrice = data.priceHistory.first.price;
      final lastPrice = data.priceHistory.last.price;
      final monthChange = (lastPrice - firstPrice) / firstPrice * 100;
      buffer.writeln('30-Day Price Change: ${monthChange.toStringAsFixed(2)}%');
    }

    if (data.news.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('RECENT NEWS:');
      for (final n in data.news.take(5)) {
        buffer.writeln(
          '- ${n.title}${n.source != null ? ' (${n.source})' : ''}',
        );
      }
    }

    buffer.writeln();
    final price = data.currentPrice;
    final maxUp = (price * 1.15).toStringAsFixed(2);
    final maxDown = (price * 0.85).toStringAsFixed(2);

    buffer.writeln(
      'CRITICAL PRICE CONSTRAINT: Current price is exactly \$${price.toStringAsFixed(2)}.',
    );
    buffer.writeln(
      'All price fields MUST be realistic dollar values anchored to this price:',
    );
    buffer.writeln(
      '  price_target: between \$$maxDown and \$$maxUp (within ±15% of current)',
    );
    buffer.writeln(
      '  price_low: must be BELOW \$${price.toStringAsFixed(2)} (downside scenario)',
    );
    buffer.writeln(
      '  price_high: must be ABOVE \$${price.toStringAsFixed(2)} (upside scenario)',
    );
    buffer.writeln(
      'Do NOT use round placeholder numbers like 100, 200, 1000 — use precise values near \$${price.toStringAsFixed(2)}.',
    );
    buffer.writeln();
    buffer.writeln(
      'Respond with EXACTLY this JSON structure and nothing else:',
    );
    buffer.writeln('''
{
  "sentiment_score": <integer 0-100, where 0=extremely bearish, 50=neutral, 100=extremely bullish>,
  "recommendation": <one of: "STRONG_BUY", "BUY", "HOLD", "SELL", "STRONG_SELL">,
  "summary": "<2-3 sentence plain-English summary of the current situation for ${data.symbol}>",
  "bullish_factors": ["<specific factor with data>", "<specific factor with data>", "<specific factor with data>"],
  "bearish_factors": ["<specific factor with data>", "<specific factor with data>", "<specific factor with data>"],
  "price_target": <7-day target, a precise number near \$${price.toStringAsFixed(2)}, within ±15%>,
  "price_low": <pessimistic 7-day price below \$${price.toStringAsFixed(2)}, within 15% downside>,
  "price_high": <optimistic 7-day price above \$${price.toStringAsFixed(2)}, within 15% upside>,
  "risk_level": <one of: "LOW", "MEDIUM", "HIGH", "VERY_HIGH">,
  "risk_explanation": "<1-2 sentences explaining the main risk>",
  "technical_note": "<1 sentence on the key technical signal right now>"
}''');

    return buffer.toString();
  }

  /// Parse Claude's JSON response into EnhancedAIAnalysis
  EnhancedAIAnalysis _parseJsonResponse(
    String rawJson,
    double currentPrice,
    String symbol,
  ) {
    try {
      // Strip any accidental markdown fences if Claude adds them
      var clean = rawJson.trim();
      if (clean.startsWith('```')) {
        clean = clean.replaceAll(RegExp(r'```[a-z]*\n?'), '').trim();
      }

      final json = jsonDecode(clean) as Map<String, dynamic>;

      // sentiment_score
      final sentimentScore = (json['sentiment_score'] as num?)?.toInt() ?? 50;

      // recommendation
      final rec = _parseRecommendation(
        json['recommendation'] as String? ?? 'HOLD',
      );

      // summary
      final summary = json['summary'] as String? ?? 'Analysis unavailable.';

      // factors
      final bullish =
          (json['bullish_factors'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      final bearish =
          (json['bearish_factors'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      // price target — validate all values are anchored to current price
      var targetVal = (json['price_target'] as num?)?.toDouble();
      var lowVal = (json['price_low'] as num?)?.toDouble();
      var highVal = (json['price_high'] as num?)?.toDouble();

      // Sanitize: clamp to ±20% of current price; fix inverted low/high
      if (targetVal != null) {
        final min = currentPrice * 0.80;
        final max = currentPrice * 1.20;
        if (targetVal < min || targetVal > max) {
          // Hallucinated — derive from sentiment
          final bias = (sentimentScore - 50) / 50.0; // -1..+1
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

      // risk
      final riskLevel = _parseRiskLevel(
        json['risk_level'] as String? ?? 'MEDIUM',
      );
      final riskExplanation =
          json['risk_explanation'] as String? ??
          'Standard market risk applies.';

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
      throw AnalysisException(
        'Failed to parse Claude response: $e\n\nRaw: $rawJson',
      );
    }
  }

  Recommendation _parseRecommendation(String str) {
    switch (str.toUpperCase().trim()) {
      case 'STRONG_BUY':
        return Recommendation.STRONG_BUY;
      case 'BUY':
        return Recommendation.BUY;
      case 'SELL':
        return Recommendation.SELL;
      case 'STRONG_SELL':
        return Recommendation.STRONG_SELL;
      default:
        return Recommendation.HOLD;
    }
  }

  RiskLevel _parseRiskLevel(String str) {
    switch (str.toUpperCase().trim()) {
      case 'LOW':
        return RiskLevel.LOW;
      case 'HIGH':
        return RiskLevel.HIGH;
      case 'VERY_HIGH':
        return RiskLevel.VERY_HIGH;
      default:
        return RiskLevel.MEDIUM;
    }
  }

  /// Call Claude API and return raw response text
  Future<String> _callClaudeAPI(String prompt) async {
    final uri = Uri.parse(APIConfig.claudeApiUrl);

    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': APIConfig.claudeApiKey,
              'anthropic-version': '2023-06-01',
            },
            body: jsonEncode({
              'model': APIConfig.claudeModel,
              'max_tokens': 1024,
              'messages': [
                {'role': 'user', 'content': prompt},
              ],
            }),
          )
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () =>
                throw AnalysisException('Request timed out after 45s.'),
          );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final content = json['content'] as List;
        return (content[0] as Map<String, dynamic>)['text'] as String;
      }

      switch (response.statusCode) {
        case 401:
          throw AnalysisException('Invalid API key.', statusCode: 401);
        case 429:
          throw RateLimitException();
        case 500:
        case 529:
          throw ServiceUnavailableException();
        default:
          final msg = _parseErrorMessage(response.body);
          throw AnalysisException(
            'Claude API error (${response.statusCode}): $msg',
            statusCode: response.statusCode,
          );
      }
    } on http.ClientException catch (e) {
      throw AnalysisException('Network error: ${e.message}');
    } on FormatException catch (e) {
      throw AnalysisException('Bad response format: ${e.message}');
    } on AnalysisException {
      rethrow;
    } catch (e) {
      throw AnalysisException('Unexpected error: $e');
    }
  }

  String _parseErrorMessage(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final error = json['error'] as Map<String, dynamic>?;
      return error?['message'] as String? ?? 'Unknown error';
    } catch (_) {
      return 'Unknown error';
    }
  }

  /// Legacy method kept for compatibility
  Future<void> clearCache(String symbol) async {}
}
