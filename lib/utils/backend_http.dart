/// Shared HTTP helpers for all backend service calls.
///
/// In debug mode, automatically retries against Railway production when the
/// local backend (10.0.2.2:8000) is unreachable — i.e. when running on a
/// physical device without a local server running.
library;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class BackendHttp {
  static List<String> _bases() {
    final local = APIConfig.backendBaseUrl;
    final prod  = APIConfig.productionBackendUrl;
    return (kDebugMode && local != prod) ? [local, prod] : [local];
  }

  static Future<http.Response?> get(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    for (final base in _bases()) {
      try {
        final resp = await http
            .get(Uri.parse('$base$path'), headers: headers)
            .timeout(timeout);
        if (resp.statusCode < 500) return resp;
      } catch (_) {}
    }
    return null;
  }

  static Future<http.Response?> post(
    String path, {
    required Map<String, String> headers,
    required String body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    for (final base in _bases()) {
      try {
        final resp = await http
            .post(Uri.parse('$base$path'), headers: headers, body: body)
            .timeout(timeout);
        if (resp.statusCode < 500) return resp;
      } catch (_) {}
    }
    return null;
  }
}
