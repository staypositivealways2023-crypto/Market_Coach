import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
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
  final _userSpeechStoppedController = StreamController<void>.broadcast();
  final _amplitudeController = StreamController<double>.broadcast();
  final _assistantTurnDoneController = StreamController<void>.broadcast();

  // ignore: library_private_types_in_public_api
  Stream<_TranscriptDelta> get onTranscriptDelta => _transcriptController.stream;
  Stream<ToolCallEvent> get onToolCallReceived => _toolCallController.stream;
  Stream<bool> get onAssistantSpeaking => _speakingController.stream;
  Stream<String> get onError => _errorController.stream;
  Stream<List<int>> get onAudioDelta => _audioDeltaController.stream;
  /// Fires when the server detects the user has started speaking.
  Stream<void> get onUserSpeechStarted => _userSpeechStartedController.stream;
  /// Fires when the server detects the user has stopped speaking (VAD silence).
  Stream<void> get onUserSpeechStopped => _userSpeechStoppedController.stream;
  /// Emits normalised RMS amplitude (0.0–1.0) for each audio delta chunk.
  Stream<double> get onAudioAmplitude => _amplitudeController.stream;
  /// Fires when the assistant's current response turn is fully complete.
  Stream<void> get onAssistantTurnDone => _assistantTurnDoneController.stream;

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
      debugPrint('[Realtime] ② WS handshake OK — proxy accepted connection');
    } catch (e) {
      debugPrint('[Realtime] ② WS handshake FAILED — $e');
      _channel = null;
      rethrow; // propagate to startSession() catch block
    }

    // ⚠️  Register listener BEFORE sending session.update so we never miss
    // the session.created confirmation or any early error from OpenAI.
    _sub = _channel!.stream.listen(
      _onMessage,
      onError: (e) {
        debugPrint('[Realtime] ❌ WS stream error: $e');
        if (!_errorController.isClosed) {
          _errorController.add('WebSocket error: $e');
        }
      },
      onDone: () {
        // WS closed — surface as an error so the UI exits "Listening" state.
        debugPrint('[Realtime] ❌ WS closed by remote (onDone fired)');
        if (!_speakingController.isClosed) _speakingController.add(false);
        if (!_errorController.isClosed) _errorController.add('__ws_closed__');
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
    debugPrint('[Realtime] event: $type');

    switch (type) {
      // OpenAI Realtime handshake confirmations — log so they appear in devtools
      case 'session.created':
        debugPrint('[Realtime] ✅ session.created — OpenAI session is live');
        break;
      case 'session.updated':
        debugPrint('[Realtime] ✅ session.updated — VAD + modalities confirmed');
        break;

      // Transcript streaming
      case 'response.audio_transcript.delta':
        final delta = event['delta'] as String? ?? '';
        if (delta.isNotEmpty && !_transcriptController.isClosed) {
          _transcriptController.add(_TranscriptDelta('assistant', delta));
        }
        break;

      case 'input_audio_buffer.speech_started':
        // User started speaking — signal notifier to cancel any in-progress response
        if (!_userSpeechStartedController.isClosed) {
          _userSpeechStartedController.add(null);
        }
        break;

      case 'input_audio_buffer.speech_stopped':
        // User stopped speaking — VAD detected silence
        if (!_userSpeechStoppedController.isClosed) {
          _userSpeechStoppedController.add(null);
        }
        break;

      case 'conversation.item.input_audio_transcription.completed':
        final transcript = event['transcript'] as String? ?? '';
        if (transcript.isNotEmpty && !_transcriptController.isClosed) {
          _transcriptController.add(_TranscriptDelta('user', transcript));
        }
        break;

      // Audio output
      case 'response.audio.delta':
        final audioB64 = event['delta'] as String? ?? '';
        if (audioB64.isNotEmpty) {
          final bytes = base64Decode(audioB64);
          if (!_audioDeltaController.isClosed) _audioDeltaController.add(bytes);
          if (!_speakingController.isClosed) _speakingController.add(true);
          // Compute RMS amplitude (0.0–1.0) from PCM16 bytes
          if (!_amplitudeController.isClosed) {
            _amplitudeController.add(_computeAmplitude(bytes));
          }
        }
        break;

      case 'response.audio.done':
        if (!_speakingController.isClosed) _speakingController.add(false);
        if (!_amplitudeController.isClosed) _amplitudeController.add(0.0);
        if (!_assistantTurnDoneController.isClosed) _assistantTurnDoneController.add(null);
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
        if (name.isNotEmpty && !_toolCallController.isClosed) {
          _toolCallController.add(ToolCallEvent(callId: callId, name: name, arguments: args));
        }
        break;

      // Errors
      case 'error':
        final err = event['error'] as Map? ?? {};
        final msg = err['message'] as String? ?? 'Unknown Realtime error';
        debugPrint('[Realtime] ❌ OpenAI error message: $msg');
        if (!_errorController.isClosed) _errorController.add(msg);
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
    if (!_speakingController.isClosed) _speakingController.add(false);
  }

  /// Inject a text narration into the active session so Jarvis speaks it aloud.
  ///
  /// Used after chart vision analysis completes — passes the voice-optimised
  /// [narration] string as an assistant turn and triggers a spoken response.
  /// No-ops silently if the session is not connected.
  void injectNarration(String narration) {
    if (_channel == null || narration.trim().isEmpty) return;

    // 1. Insert the narration as an assistant conversation item
    _send({
      'type': 'conversation.item.create',
      'item': {
        'type': 'message',
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': narration.trim()},
        ],
      },
    });

    // 2. Ask OpenAI Realtime to generate a spoken response from that item
    _send({'type': 'response.create'});

    dev.log('[Realtime] injected chart narration (${narration.length} chars)',
        name: 'JarvisRealtime');
  }

  /// Append raw PCM16 audio bytes to the input buffer.
  void appendAudio(List<int> pcm16Bytes) {
    _send({
      'type': 'input_audio_buffer.append',
      'audio': base64Encode(pcm16Bytes),
    });
  }

  /// Compute normalised RMS amplitude (0.0–1.0) from raw PCM16 LE bytes.
  static double _computeAmplitude(List<int> bytes) {
    if (bytes.length < 2) return 0.0;
    final samples = Uint8List.fromList(bytes).buffer.asInt16List();
    if (samples.isEmpty) return 0.0;
    double sum = 0.0;
    for (final s in samples) {
      sum += s * s;
    }
    final rms = math.sqrt(sum / samples.length);
    // Int16 max is 32768 — normalise and clamp
    return (rms / 32768.0).clamp(0.0, 1.0);
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
    // Null out references FIRST so any in-flight callbacks see _channel == null
    // and _sub == null before we await the cancellations.  This prevents the
    // onDone / onError handlers from firing and trying to add to closed controllers.
    final sub = _sub;
    final channel = _channel;
    _sub = null;
    _channel = null;
    await sub?.cancel();
    await channel?.sink.close();
  }

  void dispose() {
    close();
    _transcriptController.close();
    _toolCallController.close();
    _speakingController.close();
    _errorController.close();
    _audioDeltaController.close();
    _userSpeechStartedController.close();
    _userSpeechStoppedController.close();
    _amplitudeController.close();
    _assistantTurnDoneController.close();
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
