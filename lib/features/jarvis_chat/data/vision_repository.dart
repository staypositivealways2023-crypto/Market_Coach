import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../../config/api_config.dart';

/// Data model returned by POST /api/analyst/vision.
class ChartAnalysis {
  final String symbol;
  final String timeframe;
  final String trend; // 'Bullish' | 'Bearish' | 'Neutral'
  final double trendConfidence;
  final List<String> patterns;
  final List<String> supportLevels;
  final List<String> resistanceLevels;
  final String volumeAnalysis;
  final List<String> indicatorReadings;
  final List<String> keySignals;
  final ScenarioCard scenario;
  final String summary;
  final String narration; // voice-ready
  final double confidence;
  final int tokensUsed;

  const ChartAnalysis({
    required this.symbol,
    required this.timeframe,
    required this.trend,
    required this.trendConfidence,
    required this.patterns,
    required this.supportLevels,
    required this.resistanceLevels,
    required this.volumeAnalysis,
    required this.indicatorReadings,
    required this.keySignals,
    required this.scenario,
    required this.summary,
    required this.narration,
    required this.confidence,
    required this.tokensUsed,
  });

  factory ChartAnalysis.fromJson(Map<String, dynamic> j) => ChartAnalysis(
        symbol: j['symbol'] as String? ?? 'Unknown',
        timeframe: j['timeframe'] as String? ?? 'Unknown',
        trend: j['trend'] as String? ?? 'Neutral',
        trendConfidence: (j['trend_confidence'] as num?)?.toDouble() ?? 0.5,
        patterns: _strings(j['patterns']),
        supportLevels: _strings(j['support_levels']),
        resistanceLevels: _strings(j['resistance_levels']),
        volumeAnalysis: j['volume_analysis'] as String? ?? '',
        indicatorReadings: _strings(j['indicator_readings']),
        keySignals: _strings(j['key_signals']),
        scenario: ScenarioCard.fromJson(
            j['scenario'] as Map<String, dynamic>? ?? {}),
        summary: j['summary'] as String? ?? '',
        narration: j['narration'] as String? ?? '',
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0.5,
        tokensUsed: j['tokens_used'] as int? ?? 0,
      );

  static List<String> _strings(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    return [];
  }
}

class ScenarioCard {
  final String bull;
  final String base;
  final String bear;

  const ScenarioCard({
    required this.bull,
    required this.base,
    required this.bear,
  });

  factory ScenarioCard.fromJson(Map<String, dynamic> j) => ScenarioCard(
        bull: j['bull'] as String? ?? '',
        base: j['base'] as String? ?? '',
        bear: j['bear'] as String? ?? '',
      );
}

/// HTTP client for /api/analyst/vision.
class VisionRepository {
  static String get _base => '${APIConfig.backendBaseUrl}/api/analyst';
  static const _timeout = Duration(seconds: 60); // vision is slow (~10-15s)

  Future<Map<String, String>> _authHeaders(User user) async {
    final token = await user.getIdToken(true);
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Picks an image from the gallery, compresses it, and returns the
  /// [XFile] + base64 string ready for the API.
  ///
  /// Returns null if the user cancelled the picker.
  Future<({XFile file, String b64, String mediaType})?> pickImage() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75, // compress to ~300-600 KB
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (xfile == null) return null;

    final Uint8List bytes = await xfile.readAsBytes();
    final String b64 = base64Encode(bytes);
    final String mediaType =
        xfile.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';

    dev.log(
      '[VisionRepo] picked ${xfile.name} — ${(bytes.length / 1024).toStringAsFixed(0)} KB',
      name: 'VisionRepository',
    );

    return (file: xfile, b64: b64, mediaType: mediaType);
  }

  /// Send the chart image to the backend and return structured analysis.
  Future<ChartAnalysis> analyseChart(
    User user, {
    required String imageB64,
    required String mediaType,
    String? symbol,
    String? question,
  }) async {
    final headers = await _authHeaders(user);
    final body = jsonEncode({
      'image_b64': imageB64,
      'media_type': mediaType,
      ?'symbol': symbol,
      ?'question': question,
    });

    dev.log('[VisionRepo] POST /vision — size=${imageB64.length} symbol=$symbol',
        name: 'VisionRepository');

    final res = await http
        .post(Uri.parse('$_base/vision'), headers: headers, body: body)
        .timeout(_timeout);

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return ChartAnalysis.fromJson(data);
    }

    final detail = _detail(res.body);
    if (res.statusCode == 422) throw VisionException('Image error: $detail');
    if (res.statusCode == 503) throw VisionException('Vision service offline: $detail');
    throw VisionException('Analysis failed (${res.statusCode}): $detail');
  }

  String _detail(String body) {
    try {
      final d = jsonDecode(body);
      return d['detail'] ?? d['error'] ?? body;
    } catch (_) {
      return body;
    }
  }
}

class VisionException implements Exception {
  final String message;
  const VisionException(this.message);
  @override
  String toString() => message;
}

final visionRepositoryProvider = Provider<VisionRepository>((_) => VisionRepository());
