// Analyst Graph Service
// Calls the LangGraph analyst pipeline on the Python backend.
// Phase 8 — Flutter Integration

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import '../models/analyst_response.dart';
import '../utils/backend_http.dart';

class AnalystGraphService {
  static const _path = '/api/analyst/query';

  // ── Auth headers ───────────────────────────────────────────────────────────
  static Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {'Content-Type': 'application/json'};
    try {
      final token = await user.getIdToken();
      return {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};
    } catch (_) {
      return {'Content-Type': 'application/json'};
    }
  }

  // ── Main analyst call ──────────────────────────────────────────────────────

  /// POST /api/analyst/query — full 5-node LangGraph pipeline.
  /// Timeout: 150 s (DeepSeek-R1 14B reasoning can take ~90 s).
  Future<AnalystResponse> analyze({
    required String message,
    required String userId,
  }) async {
    final headers = await _authHeaders();
    final body = jsonEncode({'message': message, 'user_id': userId});
    if (kDebugMode) debugPrint('[AnalystGraphService] POST $_path');

    final resp = await BackendHttp.post(
      _path,
      headers: headers,
      body: body,
      timeout: const Duration(seconds: 150),
    );

    if (resp == null) {
      return AnalystResponse(
        intent: 'general',
        error: 'Could not reach the analyst backend. Check your connection.',
      );
    }

    if (kDebugMode) {
      debugPrint('[AnalystGraphService] status=${resp.statusCode}');
      debugPrint('[AnalystGraphService] snippet: '
          '${resp.body.substring(0, resp.body.length.clamp(0, 400))}');
    }

    if (resp.statusCode == 200) {
      return AnalystResponse.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    }

    return AnalystResponse(
      intent: 'general',
      error: 'Backend returned ${resp.statusCode}.',
    );
  }

  // ── Audio URL helpers ──────────────────────────────────────────────────────

  String resolveAudioUrl(String relativeOrAbsoluteUrl) {
    if (relativeOrAbsoluteUrl.startsWith('http')) return relativeOrAbsoluteUrl;
    return '${APIConfig.backendBaseUrl}$relativeOrAbsoluteUrl';
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
