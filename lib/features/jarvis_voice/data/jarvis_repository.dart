import 'dart:convert';
import 'dart:developer' as dev;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../config/api_config.dart';
import 'models/voice_session_bootstrap.dart';

/// HTTP client for MarketCoach backend /api/voice/* routes.
///
/// All requests include a fresh Firebase ID token for authentication.
/// This is the thin backend layer that replaces the old localhost:7700 Jarvis path
/// for voice sessions (the old JarvisService is untouched for text mode).
class JarvisRepository {
  static String get _base => '${APIConfig.backendBaseUrl}/api/voice';
  static const _timeout = Duration(seconds: 20);

  Future<Map<String, String>> _authHeaders(User user) async {
    final token = await user.getIdToken(true);
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ── Session lifecycle ──────────────────────────────────────────────────────

  /// Bootstrap a new voice session. Returns the VoiceSessionBootstrap including
  /// the OpenAI ephemeral token Flutter needs to open the Realtime WebSocket.
  Future<VoiceSessionBootstrap> createSession(
    User user, {
    VoiceMode mode = VoiceMode.general,
    String screenContext = '',
    String? activeSymbol,
    String? activeLessonId,
  }) async {
    final headers = await _authHeaders(user);
    final body = jsonEncode({
      'mode': mode.value,
      'screen_context': screenContext,
      'active_symbol': activeSymbol,
      'active_lesson_id': activeLessonId,
    });

    dev.log('[JarvisRepo] POST /session/create mode=${mode.value}', name: 'JarvisRepository');

    final res = await http
        .post(Uri.parse('$_base/session/create'), headers: headers, body: body)
        .timeout(_timeout);

    if (res.statusCode == 200) {
      return VoiceSessionBootstrap.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      );
    }
    final detail = _extractDetail(res.body);
    if (res.statusCode == 429) throw VoiceLimitReachedException(detail);
    if (res.statusCode == 409) throw VoiceSessionConflictException(detail);
    throw Exception('session/create failed ${res.statusCode}: $detail');
  }

  /// Notify backend that the session has ended. Triggers background workers.
  Future<void> endSession(
    User user, {
    required String sessionId,
    List<Map<String, dynamic>> transcriptTurns = const [],
    double voiceSeconds = 0,
  }) async {
    final headers = await _authHeaders(user);
    final body = jsonEncode({
      'session_id': sessionId,
      'transcript_turns': transcriptTurns,
      'voice_seconds': voiceSeconds,
    });

    dev.log('[JarvisRepo] POST /session/end session=$sessionId', name: 'JarvisRepository');

    try {
      await http
          .post(Uri.parse('$_base/session/end'), headers: headers, body: body)
          .timeout(_timeout);
    } catch (e) {
      dev.log('[JarvisRepo] session/end failed (non-fatal): $e', name: 'JarvisRepository');
    }
  }

  // ── Tool invocation ────────────────────────────────────────────────────────

  /// Execute a tool on behalf of the OpenAI Realtime model.
  /// Returns the raw result dict to pass back to OpenAI as function_call_output.
  Future<Map<String, dynamic>> invokeTool(
    User user, {
    required String sessionId,
    required String toolName,
    required Map<String, dynamic> arguments,
  }) async {
    final headers = await _authHeaders(user);
    final body = jsonEncode({
      'session_id': sessionId,
      'tool_name': toolName,
      'arguments': arguments,
    });

    dev.log('[JarvisRepo] POST /tools/invoke tool=$toolName', name: 'JarvisRepository');

    final res = await http
        .post(Uri.parse('$_base/tools/invoke'), headers: headers, body: body)
        .timeout(const Duration(seconds: 15));

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['result'] as Map<String, dynamic>? ?? {};
    }
    dev.log('[JarvisRepo] tools/invoke failed ${res.statusCode}', name: 'JarvisRepository');
    return {'error': 'Tool invocation failed: ${res.statusCode}'};
  }

  // ── Events ─────────────────────────────────────────────────────────────────

  /// Batch-log behavior events.
  Future<void> logEvents(
    User user,
    List<Map<String, dynamic>> events,
  ) async {
    if (events.isEmpty) return;
    try {
      final headers = await _authHeaders(user);
      final body = jsonEncode({'events': events});
      await http
          .post(Uri.parse('$_base/events/batch'), headers: headers, body: body)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      dev.log('[JarvisRepo] events/batch failed (non-fatal): $e', name: 'JarvisRepository');
    }
  }

  // ── Memory ─────────────────────────────────────────────────────────────────

  /// Upsert a profile memory entry (used in onboarding).
  Future<void> upsertMemory(
    User user, {
    required String key,
    required String value,
    String source = 'explicit',
  }) async {
    try {
      final headers = await _authHeaders(user);
      final body = jsonEncode({'key': key, 'value': value, 'source': source});
      await http
          .post(Uri.parse('$_base/memory/upsert'), headers: headers, body: body)
          .timeout(_timeout);
    } catch (e) {
      dev.log('[JarvisRepo] memory/upsert failed (non-fatal): $e', name: 'JarvisRepository');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _extractDetail(String body) {
    try {
      final data = jsonDecode(body);
      return data['detail'] ?? data['error'] ?? body;
    } catch (_) {
      return body;
    }
  }
}

// ── Typed exceptions ─────────────────────────────────────────────────────────

/// Thrown when the backend returns 429 — user has hit their voice usage tier limit.
class VoiceLimitReachedException implements Exception {
  final String message;
  const VoiceLimitReachedException(this.message);
  @override
  String toString() => message;
}

/// Thrown when the backend returns 409 — a session is already active for this user.
class VoiceSessionConflictException implements Exception {
  final String message;
  const VoiceSessionConflictException(this.message);
  @override
  String toString() => message;
}

// Riverpod provider
final jarvisRepositoryProvider = Provider<JarvisRepository>((ref) {
  return JarvisRepository();
});
