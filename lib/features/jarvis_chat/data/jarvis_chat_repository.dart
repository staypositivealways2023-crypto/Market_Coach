import 'dart:convert';
import 'dart:developer' as dev;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../config/api_config.dart';

/// HTTP client for /api/jarvis/* routes on the MarketCoach backend.
///
/// The backend proxies all calls to the local Jarvis service (Ollama).
/// If Jarvis is offline the backend returns 503 and this repo throws
/// [JarvisOfflineException] so the UI can show an offline banner.
class JarvisChatRepository {
  static String get _base => '${APIConfig.backendBaseUrl}/api/jarvis';
  static const _timeout = Duration(seconds: 30);

  Future<Map<String, String>> _authHeaders(User user) async {
    final token = await user.getIdToken(true);
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ── Status ─────────────────────────────────────────────────────────────────

  /// Returns true if the local Jarvis service is reachable.
  Future<bool> isOnline(User user) async {
    try {
      final headers = await _authHeaders(user);
      final res = await http
          .get(Uri.parse('$_base/status'), headers: headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['online'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── Chat ───────────────────────────────────────────────────────────────────

  /// Send [message] to Jarvis and return the assistant's reply.
  ///
  /// [history] is a list of previous turns:
  ///   [{"role": "user", "content": "..."}, {"role": "assistant", "content": "..."}]
  ///
  /// Throws [JarvisOfflineException] if Jarvis is unreachable (503).
  /// Throws [JarvisChatException] for other errors.
  Future<String> chat(
    User user, {
    required String message,
    List<Map<String, dynamic>> history = const [],
  }) async {
    final headers = await _authHeaders(user);
    final body = jsonEncode({'message': message, 'history': history});

    dev.log(
      '[JarvisChatRepo] POST /chat msg="${message.substring(0, message.length.clamp(0, 60))}"',
      name: 'JarvisChatRepository',
    );

    final res = await http
        .post(Uri.parse('$_base/chat'), headers: headers, body: body)
        .timeout(_timeout);

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['reply'] as String?) ?? '';
    }

    final detail = _extractDetail(res.body);
    if (res.statusCode == 503) throw JarvisOfflineException(detail);
    throw JarvisChatException('Chat failed (${res.statusCode}): $detail');
  }

  // ── Finance quick-access ───────────────────────────────────────────────────

  /// Fetch a combined quote + indicators snapshot from Jarvis.
  Future<Map<String, dynamic>> snapshot(User user, String ticker) async {
    final headers = await _authHeaders(user);
    final res = await http
        .get(Uri.parse('$_base/snapshot/${ticker.toUpperCase()}'), headers: headers)
        .timeout(const Duration(seconds: 10));

    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    final detail = _extractDetail(res.body);
    if (res.statusCode == 503) throw JarvisOfflineException(detail);
    throw JarvisChatException('Snapshot failed (${res.statusCode}): $detail');
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

// ── Exceptions ────────────────────────────────────────────────────────────────

/// Thrown when the backend cannot reach the local Jarvis service.
class JarvisOfflineException implements Exception {
  final String message;
  const JarvisOfflineException([this.message = 'Jarvis is offline']);
  @override
  String toString() => message;
}

/// Thrown for unexpected backend errors during chat.
class JarvisChatException implements Exception {
  final String message;
  const JarvisChatException(this.message);
  @override
  String toString() => message;
}

// ── Provider ──────────────────────────────────────────────────────────────────

final jarvisChatRepositoryProvider = Provider<JarvisChatRepository>((ref) {
  return JarvisChatRepository();
});
