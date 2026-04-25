import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:record/record.dart';

/// Captures microphone audio as PCM16 mono 24 kHz chunks and exposes them
/// via [onChunk] for piping to the OpenAI Realtime WebSocket.
///
/// Usage:
///   await capture.start();
///   capture.onChunk.listen((bytes) => realtime.appendAudio(bytes));
///   await capture.stop();
class AudioCaptureService {
  static const _sampleRate = 24000;
  static const _channels = 1;

  // Nullable + lazy: created on first start(), nulled on dispose().
  // This prevents PlatformException when dispose() is called before start()
  // (e.g. from Riverpod autoDispose on a provider that was never used).
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _sub;
  bool _disposed = false;

  final _chunkController = StreamController<Uint8List>.broadcast();

  /// Raw PCM16 little-endian mono 24 kHz bytes, chunked as they arrive.
  Stream<Uint8List> get onChunk => _chunkController.stream;

  bool get isRecording => _sub != null;

  /// Start capturing microphone audio.
  ///
  /// Throws if microphone permission is denied or the recorder fails to start.
  Future<void> start() async {
    if (kIsWeb) {
      dev.log('[AudioCapture] Web platform — mic stream not available', name: 'AudioCapture');
      return;
    }
    if (_disposed) {
      dev.log('[AudioCapture] start() called on disposed service — aborting', name: 'AudioCapture');
      return;
    }
    if (_sub != null) {
      dev.log('[AudioCapture] already recording, skipping start()', name: 'AudioCapture');
      return;
    }

    // Lazy-create the recorder each session. This avoids reusing a recorder
    // that was previously stopped/disposed.
    _recorder ??= AudioRecorder();
    dev.log('[AudioCapture] AudioRecorder created (lazy)', name: 'AudioCapture');

    final alreadyGranted = await _recorder!.hasPermission();
    dev.log('[AudioCapture] hasPermission=$alreadyGranted', name: 'AudioCapture');

    dev.log('[AudioCapture] calling startStream (PCM16 24kHz mono)…', name: 'AudioCapture');
    final stream = await _recorder!.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: _channels,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
    dev.log('[AudioCapture] startStream succeeded — recorder is live', name: 'AudioCapture');

    var _chunkCount = 0;
    _sub = stream.listen(
      (bytes) {
        _chunkCount++;
        if (_chunkCount <= 3 || _chunkCount % 50 == 0) {
          dev.log('[AudioCapture] chunk #$_chunkCount — ${bytes.length} bytes', name: 'AudioCapture');
        }
        _chunkController.add(bytes);
      },
      onError: (e) {
        dev.log('[AudioCapture] stream error: $e', name: 'AudioCapture');
        _chunkController.addError(e);
      },
      onDone: () {
        dev.log('[AudioCapture] stream done (total chunks: $_chunkCount)', name: 'AudioCapture');
        _sub = null;
      },
    );

    dev.log('[AudioCapture] started PCM16 24kHz mono', name: 'AudioCapture');
  }

  /// Stop capturing. Safe to call even if not recording.
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _recorder?.stop();
    } catch (_) {}
    // Null out the recorder so start() creates a fresh one next session.
    try {
      await _recorder?.dispose();
    } catch (e) {
      dev.log('[AudioCapture] recorder.dispose() in stop: $e', name: 'AudioCapture');
    }
    _recorder = null;
    dev.log('[AudioCapture] stopped + recorder nulled', name: 'AudioCapture');
  }

  void dispose() {
    if (_disposed) {
      dev.log('[AudioCapture] dispose() called again — ignoring (already disposed)', name: 'AudioCapture');
      return;
    }
    _disposed = true;
    dev.log('[AudioCapture] dispose()', name: 'AudioCapture');
    stop(); // stop() already disposes and nulls _recorder
    if (!_chunkController.isClosed) _chunkController.close();
  }
}
