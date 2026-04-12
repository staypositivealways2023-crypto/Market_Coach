import 'package:flutter/foundation.dart';

/// Dart mirror of the Python VoiceSessionBootstrap response model.
/// Returned by POST /api/voice/session/create.
@immutable
class VoiceSessionBootstrap {
  final String sessionId;
  final String openaiEphemeralToken;
  final String openaiModel;
  final String openaiVoice;
  final String instructions;
  final List<Map<String, dynamic>> tools;
  final String mode;
  final String userLevel;
  final DateTime expiresAt;

  const VoiceSessionBootstrap({
    required this.sessionId,
    required this.openaiEphemeralToken,
    required this.openaiModel,
    required this.openaiVoice,
    required this.instructions,
    required this.tools,
    required this.mode,
    required this.userLevel,
    required this.expiresAt,
  });

  factory VoiceSessionBootstrap.fromJson(Map<String, dynamic> json) {
    return VoiceSessionBootstrap(
      sessionId: json['session_id'] as String,
      openaiEphemeralToken: json['openai_ephemeral_token'] as String,
      openaiModel: json['openai_model'] as String,
      openaiVoice: json['openai_voice'] as String,
      instructions: json['instructions'] as String,
      tools: (json['tools'] as List<dynamic>)
          .map((t) => Map<String, dynamic>.from(t as Map))
          .toList(),
      mode: json['mode'] as String,
      userLevel: json['user_level'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}

/// A single transcript turn (user or assistant).
@immutable
class TranscriptItem {
  final String role;       // "user" | "assistant"
  final String text;
  final bool isToolCall;
  final DateTime createdAt;

  const TranscriptItem({
    required this.role,
    required this.text,
    this.isToolCall = false,
    required this.createdAt,
  });

  bool get isUser => role == 'user';
}

/// Voice session modes matching the backend VoiceMode enum.
enum VoiceMode {
  general('general'),
  lesson('lesson'),
  tradeDebrief('trade_debrief');

  final String value;
  const VoiceMode(this.value);

  String get displayLabel {
    switch (this) {
      case VoiceMode.general:
        return 'General';
      case VoiceMode.lesson:
        return 'Lesson';
      case VoiceMode.tradeDebrief:
        return 'Trade Debrief';
    }
  }
}
