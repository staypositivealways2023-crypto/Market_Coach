import 'dart:convert';

import 'chat_message.dart';

/// Represents a persisted conversation session.
class ChatSession {
  final String id;
  final String title; // first user message, truncated to 50 chars
  final List<ChatMessage> messages;
  final DateTime createdAt;

  const ChatSession({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toMap()).toList(),
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory ChatSession.fromMap(Map<String, dynamic> map) => ChatSession(
        id: map['id'] as String,
        title: map['title'] as String,
        messages: (map['messages'] as List<dynamic>)
            .map((m) => ChatMessage.fromMap(m as Map<String, dynamic>))
            .toList(),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      );

  String toJson() => jsonEncode(toMap());
  factory ChatSession.fromJson(String source) =>
      ChatSession.fromMap(jsonDecode(source) as Map<String, dynamic>);

  static String buildTitle(List<ChatMessage> messages) {
    final first = messages.firstWhere(
      (m) => m.role == 'user',
      orElse: () => ChatMessage(
          id: '', role: 'user', content: 'New chat', createdAt: DateTime.now()),
    );
    final t = first.content.trim().replaceAll('\n', ' ');
    return t.length > 50 ? '${t.substring(0, 47)}...' : t;
  }
}
