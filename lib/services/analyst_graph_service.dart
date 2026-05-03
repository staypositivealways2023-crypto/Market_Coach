// Analyst Graph Service
// Calls the LangGraph analyst pipeline on the Python backend.
// Phase 8 — Flutter Integration

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/analyst_response.dart';

class AnalystGraphService {
  static String get _base => APIConfig.backendBaseUrl;

  // ── Auth headers (same pattern as BackendService) ──────────────────────────
  static Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {'Content-Type': 'application/json'};
    try {
      final token = await user.getIdToken();
      return {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
    } catch (_) {
      return {'Content-Type': 'application/json'};
    }
  }

  // ── Main analyst call ──────────────────────────────────────────────────────

  /// POST /api/analyst/query
  ///
  /// Runs the full 5-node LangGraph pipeline:
  ///   intent → tool_router → reasoning (DeepSeek-R1 14B) →
  ///   verification (Claude Sonnet) → synthesis (Cartesia TTS)
  ///
  /// Timeout is 150 s to accommodate ~90 s DeepSeek reasoning window.
  Future<AnalystResponse> analyze({
    required String message,
    required String userId,
  }) async {
    final uri = Uri.parse('$_base/api/analyst/query');
    final headers = await _authHeaders();
    final body = jsonEncode({'message': message, 'user_id': userId});

    if (kDebugMode) {
      debugPrint('[AnalystGraphService] POST $uri');
      debugPrint('[AnalystGraphService] body: $body');
    }

    try {
      final resp = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 150));

      if (kDebugMode) {
        debugPrint('[AnalystGraphService] status=${resp.statusCode}');
        debugPrint('[AnalystGraphService] body snippet: '
            '${resp.body.substring(0, resp.body.length.clamp(0, 400))}');
      }

      if (resp.statusCode == 200) {
        return AnalystResponse.fromJson(
            jsonDecode(resp.body) as Map<String, dynamic>);
      }

      // Non-200 — surface the HTTP error as a structured error response
      return AnalystResponse(
        intent: 'general',
        error: 'Backend returned ${resp.statusCode}. '
            'Check that Phase 7 synthesis node is running.',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[AnalystGraphService] error: $e');
      // Surface timeout / connection errors as a structured error response
      final message = e.toString().contains('TimeoutException')
          ? 'Analysis timed out (>150 s). The DeepSeek reasoning model may be '
              'under load — try again in a moment.'
          : 'Could not reach the analyst backend. '
              'Check your connection and try again.';
      return AnalystResponse(intent: 'general', error: message);
    }
  }

  // ── Audio URL helpers ──────────────────────────────────────────────────────

  /// Resolves the relative audio path returned by the synthesis node into
  /// a full URL that can be passed to an audio player.
  ///
  /// Example:
  ///   input  → "/api/analyst/audio/abc-123"
  ///   output → "http://10.0.2.2:8000/api/analyst/audio/abc-123"
  String resolveAudioUrl(String relativeOrAbsoluteUrl) {
    if (relativeOrAbsoluteUrl.startsWith('http')) return relativeOrAbsoluteUrl;
    return '$_base$relativeOrAbsoluteUrl';
  }

  /// Builds the default query string for a symbol-based deep analysis.
  static String defaultQueryFor(String symbol, String intent) {
    switch (intent) {
      case 'technical':
        return 'Give me a full technical analysis of $symbol';
      case 'fundamental':
        return 'Analyse the fundamentals of $symbol';
      case 'sentiment':
        return 'What is the market sentiment on $symbol?';
      default:
        return 'Deep analysis of $symbol';
    }
  }
}
