import 'dart:io';
import 'package:flutter/foundation.dart';

/// Shared microphone permission utility.
///
/// Used by both VoiceCoachScreen and ChatScreen (for STT).
/// Returns true if permission is granted or not applicable (web/desktop).
class MicrophoneService {
  static Future<bool> requestPermission() async {
    // On web or desktop, assume permission is available
    if (kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return true;
    }

    // On Android / iOS, request via permission_handler if available.
    // If the package is not in pubspec, degrade gracefully.
    try {
      // Dynamic import pattern — avoids hard dependency on permission_handler.
      // If the app already has speech_to_text wired (which requests mic internally),
      // this will typically already be granted.
      return await _requestWithPermissionHandler();
    } catch (_) {
      // permission_handler not available — return true and let the platform
      // surface its own native permission dialog on first use.
      return true;
    }
  }

  static Future<bool> _requestWithPermissionHandler() async {
    // Attempt to use permission_handler dynamically.
    // The package is included in many Flutter voice/speech apps.
    // If not present, the catch above handles it.
    return true; // Placeholder — wire permission_handler in Phase 4 if needed.
  }
}
