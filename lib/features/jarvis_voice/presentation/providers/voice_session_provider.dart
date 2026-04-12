import 'dart:async';
import 'dart:developer' as dev;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/auth_provider.dart';
import '../../data/audio_capture_service.dart';
import '../../data/audio_playback_service.dart';
import '../../data/jarvis_realtime_service.dart';
import '../../data/jarvis_repository.dart';
import '../../data/models/voice_session_bootstrap.dart';

// ── State ─────────────────────────────────────────────────────────────────────

enum VoiceConnectionState { idle, connecting, connected, ending, error }

class VoiceSessionState {
  final VoiceConnectionState connectionState;
  final VoiceMode mode;
  final List<TranscriptItem> transcript;
  final String? sessionId;
  final String? errorMessage;
  final bool isAssistantSpeaking;
  final String? activeSymbol;
  final String? activeLessonId;
  /// True when the backend rejected the session with 429 (tier limit hit).
  final bool isLimitReached;

  const VoiceSessionState({
    this.connectionState = VoiceConnectionState.idle,
    this.mode = VoiceMode.general,
    this.transcript = const [],
    this.sessionId,
    this.errorMessage,
    this.isAssistantSpeaking = false,
    this.activeSymbol,
    this.activeLessonId,
    this.isLimitReached = false,
  });

  VoiceSessionState copyWith({
    VoiceConnectionState? connectionState,
    VoiceMode? mode,
    List<TranscriptItem>? transcript,
    String? sessionId,
    String? errorMessage,
    bool clearError = false,
    bool? isAssistantSpeaking,
    String? activeSymbol,
    String? activeLessonId,
    bool? isLimitReached,
  }) {
    return VoiceSessionState(
      connectionState: connectionState ?? this.connectionState,
      mode: mode ?? this.mode,
      transcript: transcript ?? this.transcript,
      sessionId: sessionId ?? this.sessionId,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isAssistantSpeaking: isAssistantSpeaking ?? this.isAssistantSpeaking,
      activeSymbol: activeSymbol ?? this.activeSymbol,
      activeLessonId: activeLessonId ?? this.activeLessonId,
      isLimitReached: isLimitReached ?? this.isLimitReached,
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class VoiceSessionNotifier extends StateNotifier<VoiceSessionState> {
  VoiceSessionNotifier(this._repo, this._realtime, this._capture, this._playback, this._user)
      : super(const VoiceSessionState());

  final JarvisRepository _repo;
  final JarvisRealtimeService _realtime;
  final AudioCaptureService _capture;
  final AudioPlaybackService _playback;
  final User _user;

  final List<Map<String, dynamic>> _transcriptTurns = [];
  final Stopwatch _sessionTimer = Stopwatch();
  final List<StreamSubscription> _subs = [];

  // ── Session lifecycle ──────────────────────────────────────────────────────

  Future<void> startSession({
    VoiceMode mode = VoiceMode.general,
    String? activeSymbol,
    String? activeLessonId,
    String screenContext = '',
  }) async {
    if (state.connectionState == VoiceConnectionState.connecting ||
        state.connectionState == VoiceConnectionState.connected) {
      return;
    }

    state = state.copyWith(
      connectionState: VoiceConnectionState.connecting,
      mode: mode,
      activeSymbol: activeSymbol,
      activeLessonId: activeLessonId,
      clearError: true,
    );

    try {
      // 1. Bootstrap via backend
      final bootstrap = await _repo.createSession(
        _user,
        mode: mode,
        screenContext: screenContext,
        activeSymbol: activeSymbol,
        activeLessonId: activeLessonId,
      );

      // 2. Connect WebSocket to OpenAI Realtime
      await _realtime.connect(bootstrap);

      // 3. Start audio I/O
      await _playback.start();
      await _capture.start();

      // 4. Wire realtime event streams (including audio piping)
      _wireStreams(bootstrap.sessionId);

      _sessionTimer
        ..reset()
        ..start();

      state = state.copyWith(
        connectionState: VoiceConnectionState.connected,
        sessionId: bootstrap.sessionId,
      );

      dev.log('[VoiceSessionNotifier] Session started: ${bootstrap.sessionId}', name: 'Voice');
    } on VoiceLimitReachedException catch (e) {
      dev.log('[VoiceSessionNotifier] Limit reached: $e', name: 'Voice');
      state = state.copyWith(
        connectionState: VoiceConnectionState.idle,
        isLimitReached: true,
        errorMessage: e.message,
      );
    } on VoiceSessionConflictException catch (e) {
      dev.log('[VoiceSessionNotifier] Session conflict: $e', name: 'Voice');
      state = state.copyWith(
        connectionState: VoiceConnectionState.error,
        errorMessage: 'Another session is already active. Please wait a moment and try again.',
      );
    } catch (e) {
      dev.log('[VoiceSessionNotifier] Start failed: $e', name: 'Voice');
      state = state.copyWith(
        connectionState: VoiceConnectionState.error,
        errorMessage: 'Failed to start voice session: $e',
      );
    }
  }

  Future<void> endSession() async {
    if (state.connectionState == VoiceConnectionState.idle ||
        state.connectionState == VoiceConnectionState.ending) {
      return;
    }

    state = state.copyWith(connectionState: VoiceConnectionState.ending);
    _sessionTimer.stop();

    final sessionId = state.sessionId;

    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    await _capture.stop();
    await _playback.stop();
    await _realtime.close();

    if (sessionId != null) {
      await _repo.endSession(
        _user,
        sessionId: sessionId,
        transcriptTurns: List.from(_transcriptTurns),
        voiceSeconds: _sessionTimer.elapsed.inSeconds.toDouble(),
      );
    }

    state = const VoiceSessionState(); // Reset to idle
    _transcriptTurns.clear();
    dev.log('[VoiceSessionNotifier] Session ended', name: 'Voice');
  }

  void setMode(VoiceMode mode) {
    state = state.copyWith(mode: mode);
  }

  void clearLimitReached() {
    state = state.copyWith(isLimitReached: false, clearError: true);
  }

  // ── Internal stream wiring ─────────────────────────────────────────────────

  void _wireStreams(String sessionId) {
    // Mic capture → OpenAI input buffer
    _subs.add(_capture.onChunk.listen((bytes) {
      _realtime.appendAudio(bytes);
    }));

    // OpenAI audio output → speaker
    _subs.add(_realtime.onAudioDelta.listen((bytes) {
      _playback.feed(bytes);
    }));

    // Transcript deltas — append to current last item of matching role
    _subs.add(_realtime.onTranscriptDelta.listen((delta) {
      _onTranscriptDelta(delta.role, delta.delta);
    }));

    // Tool calls — dispatch to backend then return result to OpenAI
    _subs.add(_realtime.onToolCallReceived.listen((event) {
      _onToolCallReceived(sessionId, event);
    }));

    // Speaking state
    _subs.add(_realtime.onAssistantSpeaking.listen((speaking) {
      state = state.copyWith(isAssistantSpeaking: speaking);
    }));

    // Errors
    _subs.add(_realtime.onError.listen((msg) {
      state = state.copyWith(errorMessage: msg);
    }));

    // Interruption — user started speaking while assistant was talking
    _subs.add(_realtime.onUserSpeechStarted.listen((_) {
      if (state.isAssistantSpeaking) {
        _playback.flush(); // stop playing current response immediately
        _realtime.cancelResponse();
      }
    }));
  }

  void _onTranscriptDelta(String role, String delta) {
    final transcript = List<TranscriptItem>.from(state.transcript);

    // Append to existing item if same role, else start a new item
    if (transcript.isNotEmpty && transcript.last.role == role && !transcript.last.isToolCall) {
      final last = transcript.removeLast();
      transcript.add(
        TranscriptItem(
          role: role,
          text: last.text + delta,
          createdAt: last.createdAt,
        ),
      );
    } else {
      transcript.add(
        TranscriptItem(
          role: role,
          text: delta,
          createdAt: DateTime.now(),
        ),
      );
      // Track turn for post-session summary
      if (transcript.last.text.trim().isNotEmpty) {
        _transcriptTurns.add({'role': role, 'text': delta, 'tool_calls': []});
      }
    }

    state = state.copyWith(transcript: transcript);
  }

  Future<void> _onToolCallReceived(String sessionId, ToolCallEvent event) async {
    dev.log('[VoiceSessionNotifier] Tool call: ${event.name}', name: 'Voice');

    // Add a tool badge to the transcript
    final transcript = List<TranscriptItem>.from(state.transcript)
      ..add(TranscriptItem(
        role: 'assistant',
        text: '🔧 Calling ${event.name}…',
        isToolCall: true,
        createdAt: DateTime.now(),
      ));
    state = state.copyWith(transcript: transcript);

    // Execute tool via backend
    final result = await _repo.invokeTool(
      _user,
      sessionId: sessionId,
      toolName: event.name,
      arguments: event.arguments,
    );

    // Update active symbol from result if present
    final symbol = result['symbol'] as String?;
    if (symbol != null) {
      state = state.copyWith(activeSymbol: symbol);
    }

    // Return result to OpenAI Realtime
    _realtime.sendToolResult(event.callId, result);
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _capture.dispose();
    _playback.stop();
    _realtime.dispose();
    super.dispose();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final jarvisRealtimeServiceProvider = Provider.autoDispose<JarvisRealtimeService>((ref) {
  final svc = JarvisRealtimeService();
  ref.onDispose(svc.dispose);
  return svc;
});

final audioCaptureServiceProvider = Provider.autoDispose<AudioCaptureService>((ref) {
  final svc = AudioCaptureService();
  ref.onDispose(svc.dispose);
  return svc;
});

final audioPlaybackServiceProvider = Provider.autoDispose<AudioPlaybackService>((ref) {
  final svc = AudioPlaybackService();
  ref.onDispose(() => svc.stop());
  return svc;
});

final voiceSessionProvider =
    StateNotifierProvider.autoDispose<VoiceSessionNotifier, VoiceSessionState>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) throw StateError('VoiceCoach requires authentication');
  return VoiceSessionNotifier(
    ref.read(jarvisRepositoryProvider),
    ref.read(jarvisRealtimeServiceProvider),
    ref.read(audioCaptureServiceProvider),
    ref.read(audioPlaybackServiceProvider),
    user,
  );
});
