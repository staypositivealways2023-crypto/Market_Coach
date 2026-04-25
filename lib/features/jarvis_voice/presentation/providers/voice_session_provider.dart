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
  bool _isDisposed = false;

  // ── Session lifecycle ──────────────────────────────────────────────────────

  Future<void> startSession({
    VoiceMode mode = VoiceMode.general,
    String? activeSymbol,
    String? activeLessonId,
    String screenContext = '',
  }) async {
    dev.log(
      '[VoiceSessionNotifier] Session create requested '
      'mode=${mode.value} state=${state.connectionState.name} '
      'session=${state.sessionId ?? 'none'}',
      name: 'Voice',
    );

    if (state.connectionState == VoiceConnectionState.connecting ||
        state.connectionState == VoiceConnectionState.connected) {
      dev.log(
        '[VoiceSessionNotifier] Existing session found. '
        'Reusing session ${state.sessionId ?? '(connecting)'}',
        name: 'Voice',
      );
      return;
    }

    state = state.copyWith(
      connectionState: VoiceConnectionState.connecting,
      mode: mode,
      activeSymbol: activeSymbol,
      activeLessonId: activeLessonId,
      clearError: true,
    );

    String? createdSessionId;

    try {
      // 1. Bootstrap via backend
      dev.log('[VoiceSessionNotifier] ① createSession → HTTP POST to backend', name: 'Voice');
      final bootstrap = await _repo.createSession(
        _user,
        mode: mode,
        screenContext: screenContext,
        activeSymbol: activeSymbol,
        activeLessonId: activeLessonId,
      );
      createdSessionId = bootstrap.sessionId;
      dev.log('[VoiceSessionNotifier] ① createSession OK — sessionId=${bootstrap.sessionId}', name: 'Voice');

      if (_isDisposed) {
        await _cleanupOrphanedSession(
          createdSessionId,
          reason: 'notifier_disposed_after_create',
        );
        return;
      }

      // 2. Connect via backend proxy WebSocket (works on all platforms)
      dev.log('[VoiceSessionNotifier] ② getIdToken + connect WebSocket…', name: 'Voice');
      final firebaseToken = await _user.getIdToken() ?? '';
      await _realtime.connect(bootstrap, firebaseToken);
      dev.log('[VoiceSessionNotifier] ② WebSocket connected OK', name: 'Voice');

      // 3. Wire ALL event streams FIRST — before audio services start.
      //    Audio capture begins producing chunks immediately on start(); if
      //    _wireStreams() runs after, those first chunks are never sent to OpenAI.
      //    Similarly the WS disconnect sentinel (__ws_closed__) must be handled
      //    before we start playing/recording.
      _wireStreams(bootstrap.sessionId);
      dev.log('[VoiceSessionNotifier] ③ streams wired', name: 'Voice');

      // 4. Start audio I/O after streams are live
      dev.log('[VoiceSessionNotifier] ④ starting AudioPlaybackService…', name: 'Voice');
      await _playback.start();
      dev.log('[VoiceSessionNotifier] ④ AudioPlaybackService started', name: 'Voice');
      dev.log('[VoiceSessionNotifier] ⑤ starting AudioCaptureService…', name: 'Voice');
      await _capture.start();
      dev.log('[VoiceSessionNotifier] ⑤ AudioCaptureService started — mic is live', name: 'Voice');

      _sessionTimer
        ..reset()
        ..start();

      if (_isDisposed) {
        await _cleanupOrphanedSession(
          createdSessionId,
          reason: 'notifier_disposed_during_start',
        );
        return;
      }

      state = state.copyWith(
        connectionState: VoiceConnectionState.connected,
        sessionId: bootstrap.sessionId,
      );

      dev.log('[VoiceSessionNotifier] Session started: ${bootstrap.sessionId}', name: 'Voice');
    } on VoiceLimitReachedException catch (e) {
      dev.log('[VoiceSessionNotifier] Limit reached: $e', name: 'Voice');
      if (_isDisposed) return;
      state = state.copyWith(
        connectionState: VoiceConnectionState.idle,
        isLimitReached: true,
        errorMessage: e.message,
      );
    } on VoiceSessionConflictException catch (e) {
      dev.log('[VoiceSessionNotifier] Existing session found on backend: $e', name: 'Voice');
      if (_isDisposed) return;
      state = state.copyWith(
        connectionState: VoiceConnectionState.error,
        errorMessage: 'Another session is already active. Please wait a moment and try again.',
      );
    } catch (e) {
      dev.log('[VoiceSessionNotifier] Start failed: $e', name: 'Voice');
      if (createdSessionId != null) {
        await _cleanupOrphanedSession(
          createdSessionId,
          reason: 'start_failed',
        );
      } else {
        await _closeLocalSessionResources();
      }
      if (_isDisposed) return;
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

    if (sessionId != null) {
      dev.log('[VoiceSessionNotifier] Closing session $sessionId', name: 'Voice');
    }

    await _closeLocalSessionResources();

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
    dev.log(
      '[VoiceSessionNotifier] Session closed ${sessionId ?? '(local only)'}',
      name: 'Voice',
    );
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
      if (_isDisposed) return;
      state = state.copyWith(isAssistantSpeaking: speaking);
    }));

    // Errors + WS disconnect sentinel
    _subs.add(_realtime.onError.listen((msg) {
      if (_isDisposed) return;
      if (msg == '__ws_closed__') {
        // OpenAI closed the WebSocket — end the session so UI exits Listening state.
        dev.log('[VoiceSessionNotifier] WS closed by remote — ending session', name: 'Voice');
        endSession();
      } else {
        state = state.copyWith(errorMessage: msg);
      }
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
    if (_isDisposed) return;
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
    if (_isDisposed) return;
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
    if (!_isDisposed && symbol != null) {
      state = state.copyWith(activeSymbol: symbol);
    }

    // Return result to OpenAI Realtime
    _realtime.sendToolResult(event.callId, result);
  }

  Future<void> _closeLocalSessionResources() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    await _capture.stop();
    await _playback.stop();
    await _realtime.close();
    _sessionTimer.stop();
  }

  Future<void> _cleanupOrphanedSession(
    String sessionId, {
    required String reason,
  }) async {
    dev.log(
      '[VoiceSessionNotifier] Existing session found. '
      'Closing/replacing orphaned session $sessionId reason=$reason',
      name: 'Voice',
    );
    await _closeLocalSessionResources();
    await _repo.endSession(
      _user,
      sessionId: sessionId,
      transcriptTurns: List.from(_transcriptTurns),
      voiceSeconds: _sessionTimer.elapsed.inSeconds.toDouble(),
    );
    _transcriptTurns.clear();
    _sessionTimer.reset();
    dev.log('[VoiceSessionNotifier] Session replaced $sessionId', name: 'Voice');
  }

  @override
  void dispose() {
    _isDisposed = true;
    final sessionId = state.sessionId;
    final shouldReleaseBackendSession =
        sessionId != null &&
        (state.connectionState == VoiceConnectionState.connected ||
            state.connectionState == VoiceConnectionState.connecting ||
            state.connectionState == VoiceConnectionState.ending);

    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    _sessionTimer.stop();
    if (shouldReleaseBackendSession) {
      dev.log(
        '[VoiceSessionNotifier] Provider disposed with active session. '
        'Closing session $sessionId',
        name: 'Voice',
      );
      unawaited(
        _repo.endSession(
          _user,
          sessionId: sessionId,
          transcriptTurns: List.from(_transcriptTurns),
          voiceSeconds: _sessionTimer.elapsed.inSeconds.toDouble(),
        ),
      );
    }
    // stop() not dispose() — audioCaptureServiceProvider.ref.onDispose owns
    // the single true dispose. Calling dispose() here too causes double
    // _recorder.dispose() → PlatformException.
    unawaited(_capture.stop());
    unawaited(_playback.stop());
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
