import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data';

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

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;

  final _chunkController = StreamController<Uint8List>.broadcast();

  /// Raw PCM16 little-endian mono 24 kHz bytes, chunked as they arrive.
  Stream<Uint8List> get onChunk => _chunkController.stream;

  bool get isRecording => _sub != null;

  /// Start capturing microphone audio.
  ///
  /// Throws if microphone permission is denied or the recorder fails to start.
  Future<void> start() async {
    if (_sub != null) return; // already recording

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw Exception('Microphone permission denied');
    }

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: _channels,
        // Auto gain control + noise suppression for cleaner voice
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );

    _sub = stream.listen(
      (bytes) => _chunkController.add(bytes),
      onError: (e) {
        dev.log('[AudioCapture] stream error: $e', name: 'AudioCapture');
        _chunkController.addError(e);
      },
      onDone: () {
        dev.log('[AudioCapture] stream done', name: 'AudioCapture');
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
      await _recorder.stop();
    } catch (_) {}
    dev.log('[AudioCapture] stopped', name: 'AudioCapture');
  }

  void dispose() {
    stop();
    _chunkController.close();
    _recorder.dispose();
  }
}
