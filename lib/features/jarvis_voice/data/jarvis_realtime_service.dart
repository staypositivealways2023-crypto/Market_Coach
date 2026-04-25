import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../config/api_config.dart';
import 'models/voice_session_bootstrap.dart';

/// OpenAI Realtime API WebSocket connection manager.
///
/// Architecture (updated — backend proxy):
///   Flutter connects to the MarketCoach backend proxy endpoint
///   (/api/voice/realtime/ws).  The backend forwards traffic to OpenAI,
///   adding the Authorization header server-side.
///
///   This approach works on ALL platforms including Flutter Web / Chrome,
///   where IOWebSocketChannel (dart:io) is unavailable and browsers cannot
///   send custom headers during the WebSocket handshake.
///
/// Audio format: PCM16 mono 24kHz (OpenAI default).
/// Tool calls flow through the backend: see JarvisRepository.invokeTool().
///
/// Usage:
///   1. Call connect(bootstrap, firebaseToken) to open the WS
///   2. Listen to onTranscriptDelta, onToolCallReceived, onAssistantSpeaking
///   3. On tool call received: call backend → send function_call_output back
///   4. Call close() when the session ends
class JarvisRealtimeService {

  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  // ── Output streams ─────────────────────────────────────────────────────────

  final _transcriptController = StreamController<_TranscriptDelta>.broadcast();
  final _toolCallController = StreamController<ToolCallEvent>.broadcast();
  final _speakingController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _audioDeltaController = StreamController<List<int>>.broadcast();
  final _userSpeechStartedController = StreamController<void>.broadcast();

  // ignore: library_private_types_in_public_api
  Stream<_TranscriptDelta> get onTranscriptDelta => _transcriptController.stream;
  Stream<ToolCallEvent> get onToolCallReceived => _toolCallController.stream;
  Stream<bool> get onAssistantSpeaking => _speakingController.stream;
  Stream<String> get onError => _errorController.stream;
  Stream<List<int>> get onAudioDelta => _audioDeltaController.stream;
  /// Fires when the server detects the user has started speaking.
  Stream<void> get onUserSpeechStarted => _userSpeechStartedController.stream;

  bool get isConnected => _channel != null;

  // ── Connection ─────────────────────────────────────────────────────────────

  /// Connect to the backend WebSocket proxy.
  ///
  /// [firebaseToken] is the current user's Firebase ID token — passed as a
  /// URL query param (browsers and all mobile platforms support this).
  /// The backend verifies the token and forwards traffic to OpenAI.
  Future<void> connect(VoiceSessionBootstrap bootstrap, String firebaseToken) async {
    if (_channel != null) {
      dev.log('[Realtime] Already connected — closing previous session', name: 'JarvisRealtime');
      await close();
    }

    // Build proxy URL — token in query param (works on web + mobile)
    final encodedToken = Uri.encodeQueryComponent(firebaseToken);
    final proxyUri = Uri.parse(
      '${APIConfig.backendWsUrl}/api/voice/realtime/ws'
      '?token=$encodedToken'
      '&model=${Uri.encodeQueryComponent(bootstrap.openaiModel)}',
    );

    dev.log('[Realtime] ② connecting to backend proxy: ${proxyUri.host}${proxyUri.path}', name: 'JarvisRealtime');

    // WebSocketChannel.connect() is platform-adaptive:
    //   Mobile/Desktop → uses dart:io WebSocket
    //   Web (Chrome)   → uses browser WebSocket
    // No custom headers needed — token travels in the URL.
    _channel = WebSocketChannel.connect(proxyUri);

    // Wait for handshake — MUST rethrow so startSession() can catch it.
    // The previous catchError() swallowed the error, hiding connection failures.
    try {
      await _channel!.ready;
      dev.log('[Realtime] ② WebSocket handshake OK', name: 'JarvisRealtime');
    } catch (e) {
      dev.log('[Realtime] ② WebSocket handshake FAILED: $e', name: 'JarvisRealtime');
      _channel = null;
      rethrow; // propagate to startSession() catch block
    }

    // ⚠️  Register listener BEFORE sending session.update so we never miss
    // the session.created confirmation or any early error from OpenAI.
    _sub = _channel!.stream.listen(
      _onMessage,
      onError: (e) {
        dev.log('[Realtime] WS error: $e', name: 'JarvisRealtime');
        _errorController.add('WebSocket error: $e');
      },
      onDone: () {
        // WS closed — surface as an error so the UI exits "Listening" state.
        dev.log('[Realtime] WS closed by remote', name: 'JarvisRealtime');
        _speakingController.add(false);
        _errorController.add('__ws_closed__'); // sentinel consumed by notifier
        _channel = null;
      },
    );

    await _authenticate();
    dev.log('[Realtime] ② session.update sent', name: 'JarvisRealtime');
  }

  Future<void> _authenticate() async {
    // Confirm session modalities after connection. The backend already
    // embedded the system instructions in the ephemeral token; this just
    // ensures audio I/O and VAD settings are set correctly.
    _send({
      'type': 'session.update',
      'session': {
        'modalities': ['audio', 'text'],
        'input_audio_format': 'pcm16',
        'output_audio_format': 'pcm16',
        'turn_detection': {
          'type': 'server_vad',
          'threshold': 0.5,
          'prefix_padding_ms': 300,
          'silence_duration_ms': 600,
        },
      },
    });
  }

  // ── Message handling ───────────────────────────────────────────────────────

  void _onMessage(dynamic raw) {
    final Map<String, dynamic> event;
    try {
      event = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = event['type'] as String? ?? '';
    dev.log('[Realtime] event: $type', name: 'JarvisRealtime');

    switch (type) {
      // OpenAI Realtime handshake confirmations — log so they appear in devtools
      case 'session.created':
        dev.log('[Realtime] session.created — OpenAI session is live', name: 'JarvisRealtime');
        break;
      case 'session.updated':
        dev.log('[Realtime] session.updated — VAD + modalities confirmed', name: 'JarvisRealtime');
        break;

      // Transcript streaming
      case 'response.audio_transcript.delta':
        final delta = event['delta'] as String? ?? '';
        if (delta.isNotEmpty) {
          _transcriptController.add(_TranscriptDelta('assistant', delta));
        }
        break;

      case 'input_audio_buffer.speech_started':
        // User started speaking — signal notifier to cancel any in-progress response
        _userSpeechStartedController.add(null);
        break;

      case 'conversation.item.input_audio_transcription.completed':
        final transcript = event['transcript'] as String? ?? '';
        if (transcript.isNotEmpty) {
          _transcriptController.add(_TranscriptDelta('user', transcript));
        }
        break;

      // Audio output
      case 'response.audio.delta':
        final audioB64 = event['delta'] as String? ?? '';
        if (audioB64.isNotEmpty) {
          final bytes = base64Decode(audioB64);
          _audioDeltaController.add(bytes);
          _speakingController.add(true);
        }
        break;

      case 'response.audio.done':
        _speakingController.add(false);
        break;

      // Tool calls
      case 'response.function_call_arguments.done':
        final callId = event['call_id'] as String? ?? '';
        final name = event['name'] as String? ?? '';
        final argsRaw = event['arguments'] as String? ?? '{}';
        Map<String, dynamic> args = {};
        try {
          args = jsonDecode(argsRaw) as Map<String, dynamic>;
        } catch (_) {}
        if (name.isNotEmpty) {
          _toolCallController.add(ToolCallEvent(callId: callId, name: name, arguments: args));
        }
        break;

      // Errors
      case 'error':
        final err = event['error'] as Map? ?? {};
        final msg = err['message'] as String? ?? 'Unknown Realtime error';
        dev.log('[Realtime] error: $msg', name: 'JarvisRealtime');
        _errorController.add(msg);
        break;
    }
  }

  // ── Outbound events ────────────────────────────────────────────────────────

  /// Send a tool result back to OpenAI after the backend executed the tool.
  void sendToolResult(String callId, Map<String, dynamic> result) {
    _send({
      'type': 'conversation.item.create',
      'item': {
        'type': 'function_call_output',
        'call_id': callId,
        'output': jsonEncode(result),
      },
    });
    // Trigger the next assistant response
    _send({'type': 'response.create'});
  }

  /// Interrupt the current assistant response (user started speaking).
  void cancelResponse() {
    _send({'type': 'response.cancel'});
    _speakingController.add(false);
  }

  /// Append raw PCM16 audio bytes to the input buffer.
  void appendAudio(List<int> pcm16Bytes) {
    _send({
      'type': 'input_audio_buffer.append',
      'audio': base64Encode(pcm16Bytes),
    });
  }

  void _send(Map<String, dynamic> event) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(event));
    } catch (e) {
      dev.log('[Realtime] send error: $e', name: 'JarvisRealtime');
    }
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  Future<void> close() async {
    await _sub?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _sub = null;
  }

  void dispose() {
    close();
    _transcriptController.close();
    _toolCallController.close();
    _speakingController.close();
    _errorController.close();
    _audioDeltaController.close();
    _userSpeechStartedController.close();
  }
}

// ── Data classes ─────────────────────────────────────────────────────────────

class _TranscriptDelta {
  final String role;
  final String delta;
  _TranscriptDelta(this.role, this.delta);
}

/// Emitted when OpenAI requests a tool call.
class ToolCallEvent {
  final String callId;
  final String name;
  final Map<String, dynamic> arguments;
  const ToolCallEvent({
    required this.callId,
    required this.name,
    required this.arguments,
  });
}
