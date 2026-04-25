import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// Shared microphone permission utility.
///
/// Used by both VoiceCoachScreen and ChatScreen (for STT).
/// Returns true if permission is granted or not applicable (web/desktop).
///
/// Note: dart:io is intentionally NOT imported here — it does not compile
/// on Flutter Web. Platform detection uses [defaultTargetPlatform] instead.
///
/// IMPORTANT: On Android/iOS the actual OS permission dialog is triggered
/// inside AudioCaptureService.start() → record.startStream(). This method
/// serves as an early check so the UI can reflect state, but returning true
/// here does NOT mean the user has accepted — the dialog appears on first
/// startStream() call.
class MicrophoneService {
  static Future<bool> requestPermission() async {
    // Web and non-mobile platforms: assume permission is handled by browser/OS
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux) {
      dev.log('[MicPermission] non-mobile platform — permission assumed granted', name: 'MicPermission');
      return true;
    }

    // Android / iOS: request permission explicitly before starting the session.
    // hasPermission() on the record package triggers the OS permission dialog
    // on first call if not yet decided, then returns the granted state.
    try {
      final recorder = AudioRecorder();
      final granted = await recorder.hasPermission();
      dev.log('[MicPermission] hasPermission=$granted (platform: $defaultTargetPlatform)', name: 'MicPermission');
      await recorder.dispose();
      return granted; // ← return actual result; UI blocks on false
    } catch (e) {
      dev.log('[MicPermission] hasPermission check failed: $e — proceeding anyway', name: 'MicPermission');
      // On error let the session attempt and AudioCaptureService will surface it.
      return true;
    }
  }
}
