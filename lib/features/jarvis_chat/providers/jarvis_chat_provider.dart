import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/jarvis_chat_repository.dart';
import '../data/vision_repository.dart';
import '../../jarvis_voice/data/jarvis_realtime_service.dart';
import '../../jarvis_voice/presentation/providers/voice_session_provider.dart';

// ── Message model ─────────────────────────────────────────────────────────────

enum MessageRole { user, assistant, system }

/// Distinguishes plain text messages from chart-analysis cards.
enum MessageType { text, chartAnalysis }

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final bool isError;
  final MessageType type;

  /// Non-null when [type] == [MessageType.chartAnalysis].
  final ChartAnalysis? chartAnalysis;

  /// Thumbnail bytes shown in the user bubble when an image was uploaded.
  final String? imageB64Preview; // base64, used only for display

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.isError = false,
    this.type = MessageType.text,
    this.chartAnalysis,
    this.imageB64Preview,
  });

  ChatMessage copyWith({String? content, bool? isError}) => ChatMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        timestamp: timestamp,
        isError: isError ?? this.isError,
        type: type,
        chartAnalysis: chartAnalysis,
        imageB64Preview: imageB64Preview,
      );
}

// ── State ─────────────────────────────────────────────────────────────────────

class JarvisChatState {
  final List<ChatMessage> messages;
  final bool isTyping;       // Jarvis is generating a response
  final bool isOnline;       // Jarvis service reachable
  final bool isCheckingStatus;
  final String? errorBanner; // shown at top of chat if non-null

  const JarvisChatState({
    this.messages = const [],
    this.isTyping = false,
    this.isOnline = true,
    this.isCheckingStatus = false,
    this.errorBanner,
  });

  JarvisChatState copyWith({
    List<ChatMessage>? messages,
    bool? isTyping,
    bool? isOnline,
    bool? isCheckingStatus,
    String? errorBanner,
    bool clearError = false,
  }) =>
      JarvisChatState(
        messages: messages ?? this.messages,
        isTyping: isTyping ?? this.isTyping,
        isOnline: isOnline ?? this.isOnline,
        isCheckingStatus: isCheckingStatus ?? this.isCheckingStatus,
        errorBanner: clearError ? null : (errorBanner ?? this.errorBanner),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class JarvisChatNotifier extends StateNotifier<JarvisChatState> {
  JarvisChatNotifier(this._repo, this._visionRepo, this._realtime, this._user)
      : super(const JarvisChatState()) {
    _addWelcome();
    checkStatus();
  }

  final JarvisChatRepository _repo;
  final VisionRepository _visionRepo;
  /// Nullable — only set when a voice session is active. Used to inject
  /// chart narration so Jarvis speaks the analysis aloud after image upload.
  final JarvisRealtimeService? _realtime;
  final User _user;

  int _msgCounter = 0;
  String _nextId() => 'msg_${++_msgCounter}';

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Send a user message and await Jarvis's reply.
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isTyping) return;

    // Add user bubble immediately
    final userMsg = ChatMessage(
      id: _nextId(),
      role: MessageRole.user,
      content: trimmed,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isTyping: true,
      clearError: true,
    );

    // Build history for multi-turn context (last 10 turns max)
    final history = _buildHistory();

    try {
      final reply = await _repo.chat(
        _user,
        message: trimmed,
        history: history,
      );

      final assistantMsg = ChatMessage(
        id: _nextId(),
        role: MessageRole.assistant,
        content: reply,
        timestamp: DateTime.now(),
      );
      state = state.copyWith(
        messages: [...state.messages, assistantMsg],
        isTyping: false,
      );
    } on JarvisOfflineException catch (e) {
      state = state.copyWith(
        isTyping: false,
        isOnline: false,
        errorBanner: 'Could not reach the AI backend. Check your connection.',
      );
      _addErrorBubble(e.message);
    } catch (e) {
      state = state.copyWith(
        isTyping: false,
        errorBanner: 'Something went wrong. Try again.',
      );
      _addErrorBubble('Error: $e');
    }
  }

  /// Pick a chart image from the gallery and run vision analysis.
  ///
  /// Workflow:
  ///   1. Open the image picker (user selects chart screenshot)
  ///   2. Add a user bubble showing the image thumbnail
  ///   3. Show typing indicator while backend processes
  ///   4. Replace typing indicator with a rich ChartAnalysis card bubble
  Future<void> analyseChartImage({String? symbol, String? question}) async {
    if (state.isTyping) return;

    // 1. Pick image
    final picked = await _visionRepo.pickImage();
    if (picked == null) return; // user cancelled

    // 2. User bubble with thumbnail preview (first 40 KB of b64 is enough for display)
    final previewB64 = picked.b64.length > 54000
        ? picked.b64.substring(0, 54000) // ~40 KB decoded
        : picked.b64;

    final userMsg = ChatMessage(
      id: _nextId(),
      role: MessageRole.user,
      content: question?.isNotEmpty == true
          ? '📊 Chart uploaded: "$question"'
          : '📊 Chart uploaded — please analyse this.',
      timestamp: DateTime.now(),
      imageB64Preview: previewB64,
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isTyping: true,
      clearError: true,
    );

    // 3. Run vision analysis
    try {
      final analysis = await _visionRepo.analyseChart(
        _user,
        imageB64: picked.b64,
        mediaType: picked.mediaType,
        symbol: symbol,
        question: question,
      );

      // 4. Analysis card bubble
      final analysisMsg = ChatMessage(
        id: _nextId(),
        role: MessageRole.assistant,
        content: analysis.summary,
        timestamp: DateTime.now(),
        type: MessageType.chartAnalysis,
        chartAnalysis: analysis,
      );

      state = state.copyWith(
        messages: [...state.messages, analysisMsg],
        isTyping: false,
      );

      // Narrate via Jarvis if a voice session is currently active
      if (analysis.narration.isNotEmpty) {
        _realtime?.injectNarration(analysis.narration);
      }
    } on VisionException catch (e) {
      state = state.copyWith(isTyping: false);
      _addErrorBubble('Chart analysis failed: ${e.message}');
    } catch (e) {
      state = state.copyWith(isTyping: false);
      _addErrorBubble('Unexpected error during chart analysis: $e');
    }
  }

  /// Ping Jarvis to update the online status indicator.
  Future<void> checkStatus() async {
    state = state.copyWith(isCheckingStatus: true);
    final online = await _repo.isOnline(_user);
    state = state.copyWith(
      isOnline: online,
      isCheckingStatus: false,
      errorBanner: online ? null : 'AI backend may be slow — messages will still be sent',
      clearError: online,
    );
  }

  /// Clear all messages (keep the welcome message).
  void clearHistory() {
    state = const JarvisChatState();
    _addWelcome();
    checkStatus();
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  void _addWelcome() {
    state = state.copyWith(
      messages: [
        ChatMessage(
          id: _nextId(),
          role: MessageRole.assistant,
          content:
              "Hey! I'm Jarvis, your AI financial coach.\n\n"
              "I can help you with market data, stock analysis, and general finance questions — "
              "or just have a conversation.\n\n"
              "Try asking: *What's the RSI on AAPL?* or *Explain what MACD tells me.*",
          timestamp: DateTime.now(),
        ),
      ],
    );
  }

  void _addErrorBubble(String text) {
    final errMsg = ChatMessage(
      id: _nextId(),
      role: MessageRole.assistant,
      content: text,
      timestamp: DateTime.now(),
      isError: true,
    );
    state = state.copyWith(messages: [...state.messages, errMsg]);
  }

  /// Convert recent messages to [{role, content}] for the backend history param.
  List<Map<String, dynamic>> _buildHistory() {
    final recent = state.messages
        .where((m) => m.role != MessageRole.system && !m.isError)
        .toList();
    // Keep last 10 turns (5 exchanges) to stay within Ollama context
    final sliced = recent.length > 10 ? recent.sublist(recent.length - 10) : recent;
    return sliced.map((m) => {
      'role': m.role == MessageRole.user ? 'user' : 'assistant',
      'content': m.content,
    }).toList();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final jarvisChatProvider =
    StateNotifierProvider<JarvisChatNotifier, JarvisChatState>((ref) {
  final repo = ref.watch(jarvisChatRepositoryProvider);
  final visionRepo = ref.watch(visionRepositoryProvider);
  // Watch the realtime service so narration is injected when a voice session
  // is active. The autoDispose provider stays alive while this notifier lives.
  final realtime = ref.watch(jarvisRealtimeServiceProvider);
  final user = FirebaseAuth.instance.currentUser ??
      (throw Exception('JarvisChatProvider: no authenticated user'));
  return JarvisChatNotifier(repo, visionRepo, realtime, user);
});
