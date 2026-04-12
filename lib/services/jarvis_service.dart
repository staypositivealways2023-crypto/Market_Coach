import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;

import '../models/chat_message.dart';

/// HTTP client for the local Jarvis API (port 7700).
///
/// When testing on a physical Android/iOS device, change [baseUrl] to your
/// PC's local IP address — e.g. 'http://192.168.1.100:7700'.
/// On a desktop build or Android emulator, 'http://localhost:7700' works.
class JarvisService {
  // Android emulator → http://10.0.2.2:7700  (current setting)
  // Physical Android/iOS device on same WiFi → PC's LAN IP e.g. http://192.168.1.203:7700
  // Windows desktop  → http://localhost:7700
  static const String baseUrl = 'http://10.0.2.2:7700';

  /// Returns true if the Jarvis API server is reachable.
  Future<bool> isAvailable() async {
    try {
      final url = '$baseUrl/health';
      dev.log('[Jarvis] GET $url', name: 'JarvisService');
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 3));
      dev.log('[Jarvis] /health → ${res.statusCode}', name: 'JarvisService');
      return res.statusCode == 200;
    } catch (e) {
      dev.log('[Jarvis] /health error: $e', name: 'JarvisService');
      return false;
    }
  }

  /// Sends [message] through Jarvis's full intent pipeline (/ask).
  /// Passes [history] so Jarvis has conversational context.
  /// Returns Jarvis's plain-text response.
  Future<String> ask(String message, List<ChatMessage> history) async {
    final historyJson = history
        .where((m) => m.content.isNotEmpty)
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    final url = '$baseUrl/ask';
    final body = jsonEncode({
      'message': message,
      'history': historyJson,
      'experience_level': 'intermediate',
    });

    dev.log('[Jarvis] POST $url', name: 'JarvisService');
    dev.log('[Jarvis] body: $body', name: 'JarvisService');

    try {
      final res = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 45));

      dev.log('[Jarvis] status: ${res.statusCode}', name: 'JarvisService');
      dev.log('[Jarvis] response: ${res.body}', name: 'JarvisService');

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return (data['response'] as String?)?.trim() ?? 'No response from Jarvis.';
      }
      throw Exception('Jarvis returned ${res.statusCode}. Body: ${res.body}');
    } on Exception catch (e) {
      dev.log('[Jarvis] exception: $e', name: 'JarvisService');
      if (e.toString().contains('Connection refused') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup')) {
        throw Exception(
          'Jarvis is offline.\n\nStart it with:\n  cd C:\\Users\\sandi\\jarvis\n  python api/run.py',
        );
      }
      rethrow;
    }
  }
}
