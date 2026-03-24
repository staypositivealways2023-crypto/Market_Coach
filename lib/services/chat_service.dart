import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/chat_message.dart';

class ChatService {
  /// Streams text deltas from the backend /api/chat endpoint.
  /// Yields one string per text chunk.
  Stream<String> streamMessage(List<ChatMessage> history) async* {
    final url = '${APIConfig.backendBaseUrl}/api/chat';
    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(url));
      request.headers['content-type'] = 'application/json';

      final messages = history
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();

      request.body = jsonEncode({
        'messages': messages,
        'user_level': 'beginner',
      });

      final response = await client.send(request);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        yield 'Error ${response.statusCode}: ${_extractErrorMessage(body)}';
        return;
      }

      final buffer = StringBuffer();
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer.write(chunk);
        String data = buffer.toString();
        final lines = data.split('\n');

        // Keep incomplete last line in buffer
        buffer.clear();
        if (!data.endsWith('\n')) {
          buffer.write(lines.removeLast());
        } else {
          lines.removeLast();
        }

        for (final line in lines) {
          if (!line.startsWith('data: ')) continue;
          final jsonStr = line.substring(6).trim();
          if (jsonStr == '[DONE]') return;
          try {
            final event = jsonDecode(jsonStr) as Map<String, dynamic>;
            if (event.containsKey('error')) {
              yield 'Service error — please try again.';
              return;
            }
            if (event.containsKey('text')) {
              yield event['text'] as String;
            }
          } catch (_) {
            // Skip malformed SSE lines
          }
        }
      }
    } on SocketException {
      // Socket closed after [DONE] — normal SSE teardown, not an error
    } catch (e) {
      yield 'Connection error — please try again.';
    } finally {
      client.close();
    }
  }

  String _extractErrorMessage(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['detail'] as String? ?? json['error'] as String? ?? body;
    } catch (_) {
      return body;
    }
  }
}
