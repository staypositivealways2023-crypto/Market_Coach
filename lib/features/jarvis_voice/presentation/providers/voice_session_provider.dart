import 'dart:async';
import 'dart:developer' as dev;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/auth_provider.dart'; // authStateProvider, currentUserProvider
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
  /// Completed transcript turns shown in the scrollable history above the caption bar.
  final List<TranscriptItem> transcript;
  final String? sessionId;
  final String? errorMessage;
  final bool isAssistantSpeaking;
  final String? activeSymbol;
  final String? activeLessonId;
  /// True when the backend rejected the session with 429 (tier limit hit).
  final bool isLimitReached;
  /// Text currently being streamed for the assistant's in-progress turn.
  /// Shown live in the caption bar. Committed to [transcript] on turn complete.
  final String currentAssistantText;
  /// True while the server VAD detects the user is actively speaking.
  final bool isUserSpeaking;
  /// In-progress user transcript (partial while speaking).
  final String currentUserText;

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
    this.currentAssistantText = '',
    this.isUserSpeaking = false,
    this.currentUserText = '',
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
    String? currentAssistantText,
    bool clearCurrentAssistant = false,
    bool? isUserSpeaking,
    String? currentUserText,
    bool clearCurrentUser = false,
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
      currentAssistantText: clearCurrentAssistant ? '' : (currentAssistantText ?? this.currentAssistantText),
      isUserSpeaking: isUserSpeaking ?? this.isUserSpeaking,
      currentUserText: clearCurrentUser ? '' : (currentUserText ?? this.currentUserText),
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

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _ts() => DateTime.now().toIso8601String();

  void _vlog(String msg, {String? sid}) {
    final tag = sid != null ? ' sid=${sid.substring(0, 8)}' : '';
    dev.log('[${_ts()}]$tag $msg', name: 'Voice');
  }

  // ── Session lifecycle ──────────────────────────────────────────────────────

  Future<void> startSession({
    VoiceMode mode = VoiceMode.general,
    String? activeSymbol,
    String? activeLessonId,
    String screenContext = '',
  }) async {
    _vlog(
      'startSession() requested '
      'mode=${mode.value} state=${state.connectionState.name} '
      'session=${state.sessionId ?? 'none'}',
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
      _vlog('① HTTP POST createSession…');
      final bootstrap = await _repo.createSession(
        _user,
        mode: mode,
        screenContext: screenContext,
        activeSymbol: activeSymbol,
        activeLessonId: activeLessonId,
      );
      createdSessionId = bootstrap.sessionId;
      _vlog('① createSession OK', sid: bootstrap.sessionId);

      if (_isDisposed) {
        await _cleanupOrphanedSession(
          createdSessionId,
          reason: 'notifier_disposed_after_create',
        );
        return;
      }

      // 2. Connect via backend proxy WebSocket (works on all platforms)
      _vlog('② getIdToken + connect WebSocket…', sid: bootstrap.sessionId);
      final firebaseToken = await _user.getIdToken() ?? '';
      await _realtime.connect(bootstrap, firebaseToken);
      _vlog('② WebSocket handshake OK', sid: bootstrap.sessionId);

      // 3. Wire ALL event streams FIRST — before audio services start.
      _wireStreams(bootstrap.sessionId);
      _vlog('③ streams wired', sid: bootstrap.sessionId);

      // 4. Start audio I/O after streams are live
      _vlog('④ AudioPlaybackService.start()…', sid: bootstrap.sessionId);
      await _playback.start();
      _vlog('④ AudioPlaybackService started — started=${_playback.isStarted}', sid: bootstrap.sessionId);
      _vlog('⑤ AudioCaptureService.start()…', sid: bootstrap.sessionId);
      await _capture.start();
      _vlog('⑤ AudioCaptureService started — mic is LIVE', sid: bootstrap.sessionId);

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
    } on VoiceSessionConflictException catch (_) {
      // ── Orphaned session recovery ──────────────────────────────────────────
      // The backend has a stale Redis lock from a previous crash (PCM released
      // before session/end was called). Force-release the lock and retry once.
      _vlog('⚠ 409 conflict — force-ending orphaned session and retrying…');
      if (_isDisposed) return;
      try {
        await _repo.forceEndSession(_user);
        _vlog('⚠ force-end OK — retrying createSession…');
        final bootstrap2 = await _repo.createSession(
          _user,
          mode: mode,
          screenContext: screenContext,
          activeSymbol: activeSymbol,
          activeLessonId: activeLessonId,
        );
        createdSessionId = bootstrap2.sessionId;
        _vlog('⚠ retry createSession OK', sid: bootstrap2.sessionId);

        if (_isDisposed) {
          await _cleanupOrphanedSession(createdSessionId, reason: 'disposed_after_retry');
          return;
        }

        final firebaseToken2 = await _user.getIdToken() ?? '';
        await _realtime.connect(bootstrap2, firebaseToken2);
        _wireStreams(bootstrap2.sessionId);
        await _playback.start();
        await _capture.start();
        _sessionTimer..reset()..start();

        if (!_isDisposed) {
          state = state.copyWith(
            connectionState: VoiceConnectionState.connected,
            sessionId: bootstrap2.sessionId,
          );
          _vlog('⚠ recovery complete — session live', sid: bootstrap2.sessionId);
        }
      } catch (retryErr) {
        _vlog('⚠ retry after force-end also failed: $retryErr');
        if (createdSessionId != null) {
          await _cleanupOrphanedSession(createdSessionId, reason: 'retry_failed');
        } else {
          await _closeLocalSessionResources();
        }
        if (!_isDisposed) {
          state = state.copyWith(
            connectionState: VoiceConnectionState.error,
            errorMessage: 'Voice session conflict — please try again.',
          );
        }
      }
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

    state = const VoiceSessionState(); // Reset to idle — clears all fields incl. caption text
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

    // User started speaking — interrupt assistant if needed, show ghost text
    _subs.add(_realtime.onUserSpeechStarted.listen((_) {
      if (_isDisposed) return;
      if (state.isAssistantSpeaking) {
        _playback.flush(); // stop playing current response immediately
        _realtime.cancelResponse();
        // Commit any in-progress assistant text as a completed turn
        _commitCurrentAssistantTurn();
      }
      state = state.copyWith(isUserSpeaking: true, clearCurrentUser: true);
    }));

    // User stopped speaking — VAD silence detected
    _subs.add(_realtime.onUserSpeechStopped.listen((_) {
      if (_isDisposed) return;
      // isUserSpeaking stays true until transcript arrives (avoids flicker)
    }));

    // Assistant turn fully complete — commit current text to history
    _subs.add(_realtime.onAssistantTurnDone.listen((_) {
      if (_isDisposed) return;
      _commitCurrentAssistantTurn();
    }));
  }

  /// Move [currentAssistantText] into the completed [transcript] list.
  void _commitCurrentAssistantTurn() {
    final text = state.currentAssistantText.trim();
    if (text.isEmpty) return;
    final updated = List<TranscriptItem>.from(state.transcript)
      ..add(TranscriptItem(role: 'assistant', text: text, createdAt: DateTime.now()));
    state = state.copyWith(transcript: updated, clearCurrentAssistant: true);
  }

  void _onTranscriptDelta(String role, String delta) {
    if (_isDisposed) return;

    if (role == 'assistant') {
      // Stream assistant text into currentAssistantText (caption bar shows this live)
      final updated = state.currentAssistantText + delta;
      state = state.copyWith(currentAssistantText: updated);
    } else {
      // User transcript arrived — turn complete, commit to history
      final userText = state.currentUserText + delta;
      final transcript = List<TranscriptItem>.from(state.transcript)
        ..add(TranscriptItem(role: 'user', text: userText, createdAt: DateTime.now()));
      _transcriptTurns.add({'role': 'user', 'text': userText, 'tool_calls': []});
      state = state.copyWith(
        transcript: transcript,
        isUserSpeaking: false,
        clearCurrentUser: true,
      );
    }
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
  // ── Auth churn guard ────────────────────────────────────────────────────────
  // Watch ONLY the UID string via .select(), not the full AsyncValue<User?>.
  // Without .select(), Firebase token refreshes emit a new User object with the
  // SAME uid — Riverpod sees the AsyncValue changed → tears down this provider
  // mid-session. .select() compares with == so identical UIDs skip the rebuild.
  final uid = ref.watch(
    authStateProvider.select((v) => v.valueOrNull?.uid),
  );
  if (uid == null) throw StateError('VoiceCoach requires authentication');

  // Re-read the User object once for the constructor — always fresh (getIdToken
  // on the User always fetches the latest token; the object itself doesn't matter).
  final user = ref.read(currentUserProvider);
  if (user == null) throw StateError('VoiceCoach requires authentication');

  // CRITICAL: use ref.watch (not ref.read) for all autoDispose sub-providers.
  // ref.read does NOT create a lasting Riverpod subscription, so autoDispose
  // sub-providers get torn down immediately after this factory returns —
  // calling FlutterPcmSound.release() and stop() while the session is still
  // starting. ref.watch keeps them alive for the lifetime of voiceSessionProvider.
  return VoiceSessionNotifier(
    ref.read(jarvisRepositoryProvider),
    ref.watch(jarvisRealtimeServiceProvider),
    ref.watch(audioCaptureServiceProvider),
    ref.watch(audioPlaybackServiceProvider),
    user,
  );
});
