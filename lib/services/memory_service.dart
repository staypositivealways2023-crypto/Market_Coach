/// MemoryService — talks to GET /api/voice/memory/timeline and
/// DELETE /api/voice/memory/chroma/{doc_id}.
///
/// Phase 4 — Deep Memory System.
library;

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/memory_entry.dart';

class MemoryService {
  static String get _base => APIConfig.backendBaseUrl;

  // ── Auth headers (matches BackendService / AnalystGraphService pattern) ─────
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

  /// Fetch the full ChromaDB memory timeline for the current user.
  ///
  /// [category] — optional filter (e.g. 'trade_history').
  /// [limit]    — max entries (default 100).
  ///
  /// Returns an empty list on any error so the UI degrades gracefully.
  Future<List<MemoryTimelineEntry>> getTimeline({
    String? category,
    int limit = 100,
  }) async {
    try {
      final queryParams = <String, String>{'limit': limit.toString()};
      if (category != null) queryParams['category'] = category;

      final uri = Uri.parse('$_base/api/voice/memory/timeline')
          .replace(queryParameters: queryParams);

      final resp = await http
          .get(uri, headers: await _authHeaders())
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        return MemoryTimelineResponse.fromJson(body).entries;
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Delete a single ChromaDB memory entry by its document ID.
  ///
  /// Returns true on success, false on any error.
  Future<bool> deleteEntry(String docId) async {
    try {
      final uri =
          Uri.parse('$_base/api/voice/memory/chroma/${Uri.encodeComponent(docId)}');
      final resp = await http
          .delete(uri, headers: await _authHeaders())
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        return body['deleted'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
