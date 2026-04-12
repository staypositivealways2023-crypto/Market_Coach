import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../services/chat_service.dart';
import '../services/jarvis_service.dart';
import '../services/subscription_service.dart';
import 'subscription_provider.dart';

const _kSessionsKey = 'chat_sessions_v1';
const _kMaxSessions = 20; // keep last 20 conversations

enum ChatEngine { claude, jarvis }

class ChatState {
  final List<ChatMessage> messages;
  final bool isStreaming;
  final List<ChatSession> sessions;
  final bool limitReached;
  final ChatEngine engine;

  const ChatState({
    required this.messages,
    this.isStreaming = false,
    this.sessions = const [],
    this.limitReached = false,
    this.engine = ChatEngine.claude,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isStreaming,
    List<ChatSession>? sessions,
    bool? limitReached,
    ChatEngine? engine,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        isStreaming: isStreaming ?? this.isStreaming,
        sessions: sessions ?? this.sessions,
        limitReached: limitReached ?? this.limitReached,
        engine: engine ?? this.engine,
      );
}

class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier({this.subscriptionService})
      : super(const ChatState(messages: [])) {
    _loadSessions();
  }

  final SubscriptionService? subscriptionService;
  final _service = ChatService();
  final _jarvis = JarvisService();

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _loadSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSessionsKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => ChatSession.fromMap(e as Map<String, dynamic>))
          .toList();
      // newest first
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      state = state.copyWith(sessions: list);
    } catch (_) {}
  }

  Future<void> _saveSessions(List<ChatSession> sessions) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trimmed = sessions.take(_kMaxSessions).toList();
      await prefs.setString(
          _kSessionsKey, jsonEncode(trimmed.map((s) => s.toMap()).toList()));
    } catch (_) {}
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  void toggleEngine() {
    final next = state.engine == ChatEngine.claude
        ? ChatEngine.jarvis
        : ChatEngine.claude;
    state = state.copyWith(engine: next);
  }

  void clearLimitReached() {
    state = state.copyWith(limitReached: false);
  }

  Future<void> sendMessage(String text) async {
    if (state.isStreaming || text.trim().isEmpty) return;

    // Check subscription limit (only for authenticated users with service)
    if (subscriptionService != null) {
      try {
        // We'll get the current count via a one-shot read
        final sub = await subscriptionService!.streamSubscription().first;
        if (sub.isAtLimit) {
          state = state.copyWith(limitReached: true);
          return;
        }
        await subscriptionService!.incrementMessageCount();
      } catch (_) {
        // If subscription check fails, allow the message
      }
    }

    final userMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'user',
      content: text.trim(),
      createdAt: DateTime.now(),
    );

    final assistantMsg = ChatMessage(
      id: '${DateTime.now().millisecondsSinceEpoch + 1}',
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
    );

    final history = [...state.messages, userMsg];
    state = state.copyWith(
      messages: [...state.messages, userMsg, assistantMsg],
      isStreaming: true,
    );

    try {
      if (state.engine == ChatEngine.jarvis) {
        // Jarvis: single blocking HTTP call to local Ollama API
        final response = await _jarvis.ask(text.trim(), history);
        final msgs = state.messages;
        state = state.copyWith(
          messages: [
            ...msgs.sublist(0, msgs.length - 1),
            msgs.last.copyWith(content: response),
          ],
        );
      } else {
        // Claude: streaming response
        await for (final chunk in _service.streamMessage(history)) {
          final msgs = state.messages;
          final last = msgs.last;
          state = state.copyWith(
            messages: [
              ...msgs.sublist(0, msgs.length - 1),
              last.copyWith(content: last.content + chunk),
            ],
          );
        }
      }
    } catch (e) {
      final msgs = state.messages;
      state = state.copyWith(
        messages: [
          ...msgs.sublist(0, msgs.length - 1),
          msgs.last.copyWith(content: 'Error: $e'),
        ],
      );
    } finally {
      state = state.copyWith(isStreaming: false);
    }
  }

  /// Save current conversation to history and start fresh.
  Future<void> clearChat() async {
    if (state.isStreaming) return;
    if (state.messages.isNotEmpty) {
      await _archiveCurrent();
    }
    state = state.copyWith(messages: []);
  }

  /// Load a past session into the active view (read-only replay).
  void loadSession(ChatSession session) {
    state = state.copyWith(messages: List<ChatMessage>.from(session.messages));
  }

  /// Delete a past session permanently.
  Future<void> deleteSession(String sessionId) async {
    final updated = state.sessions.where((s) => s.id != sessionId).toList();
    state = state.copyWith(sessions: updated);
    await _saveSessions(updated);
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<void> _archiveCurrent() async {
    final session = ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: ChatSession.buildTitle(state.messages),
      messages: List<ChatMessage>.from(state.messages),
      createdAt: DateTime.now(),
    );
    final updated = [session, ...state.sessions].take(_kMaxSessions).toList();
    state = state.copyWith(sessions: updated);
    await _saveSessions(updated);
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final subService = ref.watch(subscriptionServiceProvider);
  return ChatNotifier(subscriptionService: subService);
});
