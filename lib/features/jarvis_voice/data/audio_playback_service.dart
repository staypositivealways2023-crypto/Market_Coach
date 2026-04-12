import 'dart:collection';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

/// Plays raw PCM16 audio chunks received from the OpenAI Realtime WebSocket.
///
/// OpenAI streams audio as base64-encoded PCM16 little-endian mono 24 kHz.
/// Flutter decodes the base64 → bytes before calling [feed].
///
/// Usage:
///   await playback.start();
///   realtimeService.onAudioDelta.listen(playback.feed);
///   await playback.stop();
class AudioPlaybackService {
  static const _sampleRate = 24000;
  static const _channels = 1;

  // Buffer of raw PCM16 byte chunks waiting to be played.
  final Queue<Uint8List> _buffer = Queue();
  bool _playing = false;
  bool _started = false;

  /// Initialise the PCM sound engine. Call once before [feed].
  Future<void> start() async {
    if (_started) return;
    try {
      await FlutterPcmSound.setup(
        sampleRate: _sampleRate,
        channelCount: _channels,
      );
      // Request more samples when buffer drops below ~100ms of audio
      // 24000 Hz * 0.1s = 2400 frames
      FlutterPcmSound.setFeedThreshold(2400);
      FlutterPcmSound.setFeedCallback(_onFeedSamples);
      _started = true;
      dev.log('[AudioPlayback] started', name: 'AudioPlayback');
    } catch (e) {
      dev.log('[AudioPlayback] setup failed: $e', name: 'AudioPlayback');
    }
  }

  /// Feed raw PCM16 bytes (little-endian Int16) to the playback buffer.
  void feed(List<int> pcm16Bytes) {
    if (!_started) return;
    _buffer.add(Uint8List.fromList(pcm16Bytes));
    if (!_playing) {
      _playing = true;
      _drainBuffer();
    }
  }

  /// Called by flutter_pcm_sound when it needs more samples.
  void _onFeedSamples(int remainingFrames) {
    _drainBuffer();
  }

  void _drainBuffer() {
    if (_buffer.isEmpty) {
      _playing = false;
      return;
    }

    // Combine all buffered chunks into one feed call for efficiency
    int totalBytes = 0;
    for (final chunk in _buffer) {
      totalBytes += chunk.length;
    }

    final combined = Uint8List(totalBytes);
    int offset = 0;
    while (_buffer.isNotEmpty) {
      final chunk = _buffer.removeFirst();
      combined.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    // Convert raw bytes (little-endian PCM16) to Int16List
    final int16 = combined.buffer.asInt16List();

    try {
      FlutterPcmSound.feed(PcmArrayInt16(bytes: int16.buffer.asByteData()));
    } catch (e) {
      dev.log('[AudioPlayback] feed error: $e', name: 'AudioPlayback');
    }
  }

  /// Flush buffer and silence output. Does not tear down the engine.
  void flush() {
    _buffer.clear();
    _playing = false;
    dev.log('[AudioPlayback] flushed', name: 'AudioPlayback');
  }

  /// Stop playback and release the audio engine.
  Future<void> stop() async {
    flush();
    try {
      await FlutterPcmSound.release();
    } catch (_) {}
    _started = false;
    dev.log('[AudioPlayback] stopped', name: 'AudioPlayback');
  }
}
