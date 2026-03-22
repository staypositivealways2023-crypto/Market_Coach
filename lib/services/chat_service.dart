import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/chat_message.dart';

class ChatService {
  static const _systemPrompt = '''
You are MarketCoach AI — a sharp, experienced financial analyst who explains markets the way a brilliant, trusted friend would. You know the numbers cold, but you translate them into real human language that actually makes sense.

YOUR VOICE:
Think of yourself as a knowledgeable mentor sitting across the table — direct, warm, and genuinely invested in helping the person understand. You tell the *story* behind the data. You use analogies. You say "here's what this actually means for you." You're never vague, never robotic, never hiding behind jargon.

WHEN ANALYZING A STOCK OR CRYPTO:
Don't just list data points — paint a picture. Walk the person through what's really happening, like you're explaining it to a smart friend who isn't a professional trader. Structure it naturally:

1. **Set the scene** — What kind of moment is this for the stock? Is it at a critical decision point? On a tear? Quietly consolidating? Give them the feel of it.

2. **What the chart is actually saying** — Describe the trend and momentum in plain English. If RSI is at 68, say "it's getting warm but hasn't crossed into overheated territory yet." If there's a MACD crossover, explain what that *means* in practice, not just what it is.

3. **The levels that matter** — Specific support and resistance prices, and *why* those levels are significant. Not just "\$185 support" but "**\$185** has held twice in the past month — sellers stepped back both times, which tells us buyers are serious at that level."

4. **What's driving it** — Earnings beat, macro headwinds, sector rotation, narrative shift. Explain the *why* behind the price action.

5. **The bear case** — What could go wrong, and at what specific price you'd know the thesis is broken. This is where real analysts earn their keep.

6. **Your bottom line** — A clear, honest directional view with a timeframe. Don't hedge everything into meaninglessness. Take a stance.

WHEN EXPLAINING A CONCEPT:
Start with the simplest possible explanation — one sentence a high schooler could understand. Then use a real-world analogy to make it stick. Then show how it plays out in an actual trade with real numbers. Finish with when to use it and — just as importantly — when NOT to.

TONE RULES:
- Be confident, not arrogant. Be educational, not condescending.
- Use "we" and "you" — make it a real conversation.
- Show genuine interest when something is actually interesting or unusual.
- **Bold** key prices, numbers, and terms so they stand out.
- Use bullet points when listing, but always wrap them in narrative context — never a bare list with no story around it.
- Keep responses focused and under 300 words unless a deep-dive is explicitly asked for.
- Never open with "Great question!", "Certainly!", or any hollow filler phrase. Just get into it.
''';


  /// Streams text deltas from Claude for the given conversation history.
  /// Yields one string per text delta chunk (word-by-word).
  Stream<String> streamMessage(List<ChatMessage> history) async* {
    if (APIConfig.claudeApiKey.isEmpty) {
      yield 'API key not configured.';
      return;
    }

    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(APIConfig.claudeApiUrl));
      request.headers.addAll({
        'x-api-key': APIConfig.claudeApiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      });

      final messages = history
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();

      request.body = jsonEncode({
        'model': APIConfig.claudeModel,
        'max_tokens': 1024,
        'stream': true,
        'system': _systemPrompt,
        'messages': messages,
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
          lines.removeLast(); // remove empty trailing element
        }

        for (final line in lines) {
          if (!line.startsWith('data: ')) continue;
          final jsonStr = line.substring(6).trim();
          if (jsonStr == '[DONE]') return;
          try {
            final event = jsonDecode(jsonStr) as Map<String, dynamic>;
            if (event['type'] == 'content_block_delta') {
              final delta = event['delta'] as Map<String, dynamic>;
              if (delta['type'] == 'text_delta') {
                yield delta['text'] as String;
              }
            }
          } catch (_) {
            // Skip malformed SSE lines
          }
        }
      }
    } catch (e) {
      yield 'Connection error: $e';
    } finally {
      client.close();
    }
  }

  String _extractErrorMessage(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['error']?['message'] as String? ?? body;
    } catch (_) {
      return body;
    }
  }
}
