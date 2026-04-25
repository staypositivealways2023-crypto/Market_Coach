import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../models/subscription.dart';
import '../../providers/chat_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../widgets/disclaimer_banner.dart';
import '../../widgets/paywall_bottom_sheet.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with TickerProviderStateMixin {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  late final AnimationController _dotController;
  final FocusNode _focusNode = FocusNode();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final _speech = SpeechToText();
  final _tts = FlutterTts();
  bool _speechReady = false;
  bool _isListening = false;
  bool _ttsEnabled = true;

  static const _teal = Color(0xFF12A28C);

  static const _suggestions = [
    ('Analyze AAPL', Icons.show_chart),
    ('Bitcoin outlook', Icons.currency_bitcoin),
    ('Best dividend stocks', Icons.monetization_on_outlined),
    ('Explain RSI', Icons.bar_chart),
  ];

  @override
  void initState() {
    super.initState();
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _initVoice();
  }

  Future<void> _initVoice() async {
    _speechReady = await _speech.initialize(
      onError: (_) => setState(() => _isListening = false),
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
        }
      },
    );
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    _tts.setCompletionHandler(() {});
    if (mounted) setState(() {});
  }

  Future<void> _toggleListening() async {
    if (!_speechReady) return;
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    } else {
      await _tts.stop();
      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (result) {
          _textController.text = result.recognizedWords;
          if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
            setState(() => _isListening = false);
            // Small delay so the text field visually updates before sending
            Future.delayed(const Duration(milliseconds: 150), _send);
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        listenOptions: SpeechListenOptions(cancelOnError: true),
      );
    }
  }

  Future<void> _speakResponse(String text) async {
    if (!_ttsEnabled || text.isEmpty) return;
    // Strip markdown for cleaner speech
    final clean = text
        .replaceAll(RegExp(r'\*\*?|__?|~~|`{1,3}'), '')
        .replaceAll(RegExp(r'#{1,6}\s'), '')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
        .trim();
    await _tts.speak(clean);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _dotController.dispose();
    _focusNode.dispose();
    _speech.cancel();
    _tts.stop();
    super.dispose();
  }

  void _send([String? override]) {
    final text = override ?? _textController.text;
    if (text.trim().isEmpty) return;
    _textController.clear();
    _focusNode.unfocus();
    ref.read(chatProvider.notifier).sendMessage(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final messages = chatState.messages;
    final isStreaming = chatState.isStreaming;
    final sub = ref.watch(subscriptionProvider).valueOrNull;

    ref.listen<ChatState>(chatProvider, (prev, next) {
      _scrollToBottom();
      // TTS: speak AI response when streaming finishes
      if ((prev?.isStreaming ?? false) && !next.isStreaming) {
        final last = next.messages.isNotEmpty ? next.messages.last : null;
        if (last != null && last.role == 'assistant' && last.content.isNotEmpty) {
          _speakResponse(last.content);
        }
      }
      if (next.limitReached && !(prev?.limitReached ?? false)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const PaywallBottomSheet(),
          ).then((_) => ref.read(chatProvider.notifier).clearLimitReached());
        });
      }
    });

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      endDrawer: _HistoryDrawer(scaffoldKey: _scaffoldKey),
      appBar: _buildAppBar(isStreaming, chatState),
      body: Stack(
        children: [
          // ── Programmatic dark-navy glassmorphic background ──────────────
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF010812), // near-black top
                    Color(0xFF020D1F), // deep navy
                    Color(0xFF031428), // mid dark blue
                    Color(0xFF041A30), // slightly lighter near bottom
                  ],
                  stops: [0.0, 0.35, 0.70, 1.0],
                ),
              ),
            ),
          ),
          // World-map dot grid
          Positioned.fill(
            child: CustomPaint(painter: _WorldMapDotPainter()),
          ),
          // Blue horizon glow at the bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 260,
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.0, 1.4),
                  radius: 1.0,
                  colors: [
                    Color(0x7F063B6B),
                    Color(0x4F0A4D8A),
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          // Subtle top vignette
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 180,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCC000000), Colors.transparent],
                ),
              ),
            ),
          ),
          // Main content
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: messages.isEmpty
                      ? _buildEmptyState()
                      : _buildMessageList(messages, isStreaming),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: DisclaimerBanner(),
                ),
                if (sub != null && !sub.isPro)
                  _MessageLimitBanner(sub: sub),
                _buildInputBar(isStreaming),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isStreaming, ChatState chatState) {
    final isJarvis = chatState.engine == ChatEngine.jarvis;
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              border: Border(
                bottom: BorderSide(
                  color: _teal.withValues(alpha: 0.15),
                  width: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
      titleSpacing: 0,
      leading: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Center(
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF12A28C), Color(0xFF0A6B5E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _teal.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.auto_graph, color: Colors.white, size: 20),
          ),
        ),
      ),
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'MarketCoach AI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          Text(
            'Financial Analyst',
            style: TextStyle(color: Color(0xFF12A28C), fontSize: 11),
          ),
        ],
      ),
      actions: [
        // Engine toggle: Claude ↔ Jarvis
        GestureDetector(
          onTap: isStreaming
              ? null
              : () => ref.read(chatProvider.notifier).toggleEngine(),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: isJarvis
                  ? const Color(0xFF5B3FFF).withValues(alpha: 0.18)
                  : _teal.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isJarvis
                    ? const Color(0xFF5B3FFF).withValues(alpha: 0.5)
                    : _teal.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isJarvis ? Icons.memory : Icons.auto_awesome,
                  size: 12,
                  color: isJarvis ? const Color(0xFF9B7FFF) : _teal,
                ),
                const SizedBox(width: 4),
                Text(
                  isJarvis ? 'Jarvis' : 'Claude',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isJarvis ? const Color(0xFF9B7FFF) : _teal,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        // TTS toggle
        IconButton(
          icon: Icon(
            _ttsEnabled ? Icons.volume_up_outlined : Icons.volume_off_outlined,
            color: _ttsEnabled ? Colors.white70 : Colors.white30,
            size: 20,
          ),
          tooltip: _ttsEnabled ? 'Mute voice' : 'Unmute voice',
          onPressed: () {
            setState(() => _ttsEnabled = !_ttsEnabled);
            if (!_ttsEnabled) _tts.stop();
          },
        ),
        // New chat button — only when there are messages
        if (chatState.messages.isNotEmpty && !isStreaming)
          IconButton(
            icon: const Icon(Icons.add_comment_outlined,
                color: Colors.white70, size: 20),
            tooltip: 'New chat',
            onPressed: () => ref.read(chatProvider.notifier).clearChat(),
          ),
        // History button
        IconButton(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.history, color: Colors.white70, size: 22),
              if (chatState.sessions.isNotEmpty)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: _teal,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          tooltip: 'Chat history',
          onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF12A28C), Color(0xFF0A6B5E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: _teal.withValues(alpha: 0.35),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.auto_graph, color: Colors.white, size: 42),
            ),
            const SizedBox(height: 20),
            const Text(
              'How can I help?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask me about stocks, crypto, technical\nanalysis, or market strategy.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: _suggestions
                  .map((s) => _SuggestionChip(
                        label: s.$1,
                        icon: s.$2,
                        onTap: () => _send(s.$1),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(List<ChatMessage> messages, bool isStreaming) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        final isUser = msg.role == 'user';
        final isLastAI = !isUser &&
            index == messages.length - 1 &&
            isStreaming;

        return _MessageBubble(
          message: msg,
          isUser: isUser,
          isStreaming: isLastAI,
          dotController: _dotController,
        );
      },
    );
  }

  Widget _buildInputBar(bool isStreaming) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            border: Border(
              top: BorderSide(
                color: _teal.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
          ),
          padding: EdgeInsets.only(
            left: 16,
            right: 12,
            top: 12,
            bottom: MediaQuery.of(context).padding.bottom + 12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Mic button
              _MicButton(
                isListening: _isListening,
                speechReady: _speechReady,
                onTap: _toggleListening,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2535).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isListening
                          ? Colors.redAccent.withValues(alpha: 0.6)
                          : _teal.withValues(alpha: 0.25),
                      width: _isListening ? 1.5 : 0.8,
                    ),
                  ),
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    enabled: !isStreaming,
                    maxLines: 5,
                    minLines: 1,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: _isListening
                          ? 'Listening...'
                          : isStreaming
                              ? 'AI is thinking...'
                              : 'Ask about any stock or market...',
                      hintStyle: TextStyle(
                        color: _isListening
                            ? Colors.redAccent.withValues(alpha: 0.7)
                            : Colors.white.withValues(alpha: 0.3),
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SendButton(isStreaming: isStreaming, onSend: _send),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Message Limit Banner ─────────────────────────────────────────────────────

class _MessageLimitBanner extends StatelessWidget {
  final Subscription sub;
  const _MessageLimitBanner({required this.sub});

  static const _teal = Color(0xFF12A28C);

  @override
  Widget build(BuildContext context) {
    final used = sub.aiMessagesToday;
    final limit = Subscription.freeDailyLimit;
    final remaining = (limit - used).clamp(0, limit);
    final isAtLimit = sub.isAtLimit;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isAtLimit
            ? Colors.redAccent.withValues(alpha: 0.12)
            : _teal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isAtLimit
              ? Colors.redAccent.withValues(alpha: 0.3)
              : _teal.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isAtLimit ? Icons.lock_outline : Icons.chat_bubble_outline,
            size: 14,
            color: isAtLimit ? Colors.redAccent : _teal,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isAtLimit
                  ? 'Daily limit reached — upgrade to Pro for unlimited messages'
                  : '$remaining of $limit free messages remaining today',
              style: TextStyle(
                fontSize: 11.5,
                color: isAtLimit
                    ? Colors.redAccent.withValues(alpha: 0.9)
                    : Colors.white.withValues(alpha: 0.65),
              ),
            ),
          ),
          if (isAtLimit)
            GestureDetector(
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const PaywallBottomSheet(),
              ),
              child: const Text(
                'Upgrade',
                style: TextStyle(
                  fontSize: 11.5,
                  color: _teal,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── History Drawer ───────────────────────────────────────────────────────────

class _HistoryDrawer extends ConsumerWidget {
  const _HistoryDrawer({required this.scaffoldKey});
  final GlobalKey<ScaffoldState> scaffoldKey;

  static const _teal = Color(0xFF12A28C);
  static const _bg = Color(0xFF0D131A);
  static const _border = Color(0xFF1E2D3D);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatProvider);
    final sessions = chatState.sessions;

    return Drawer(
      backgroundColor: _bg,
      width: MediaQuery.of(context).size.width * 0.82,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.history, color: _teal, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Chat History',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: Colors.white54, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Container(height: 0.5, color: _border),

            // Session list
            Expanded(
              child: sessions.isEmpty
                  ? _emptyHistory()
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: sessions.length,
                      separatorBuilder: (context, index) =>
                          Container(height: 0.5, color: _border),
                      itemBuilder: (ctx, i) =>
                          _SessionTile(session: sessions[i]),
                    ),
            ),

            // New chat button at bottom
            Container(height: 0.5, color: _border),
            Padding(
              padding: const EdgeInsets.all(16),
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  ref.read(chatProvider.notifier).clearChat();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF12A28C), Color(0xFF0A6B5E)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'New Chat',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyHistory() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 40, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 12),
          Text(
            'No past conversations',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your chats will appear here',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.2),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.session});
  final ChatSession session;

  static const _teal = Color(0xFF12A28C);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = _formatDate(session.createdAt);
    final msgCount = session.messages.length;

    return Dismissible(
      key: ValueKey(session.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.withValues(alpha: 0.15),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
      ),
      onDismissed: (direction) => ref.read(chatProvider.notifier).deleteSession(session.id),
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          ref.read(chatProvider.notifier).loadSession(session);
        },
        splashColor: _teal.withValues(alpha: 0.08),
        highlightColor: _teal.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _teal.withValues(alpha: 0.2)),
                ),
                child: const Icon(Icons.chat_bubble_outline,
                    color: _teal, size: 17),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$date · $msgCount messages',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right,
                  color: Colors.white.withValues(alpha: 0.2), size: 18),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return DateFormat('EEEE').format(dt);
    return DateFormat('MMM d').format(dt);
  }
}

// ─── Message Bubble ──────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isUser,
    required this.isStreaming,
    required this.dotController,
  });

  final ChatMessage message;
  final bool isUser;
  final bool isStreaming;
  final AnimationController dotController;

  static const _teal = Color(0xFF12A28C);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 6,
        bottom: 6,
        left: isUser ? 48 : 0,
        right: isUser ? 0 : 48,
      ),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isUser) _aiAvatar(),
          const SizedBox(height: 4),
          isUser ? _userBubble() : _aiBubble(context),
          const SizedBox(height: 3),
          Text(
            _formatTime(message.createdAt),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiAvatar() {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF12A28C), Color(0xFF0A6B5E)],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.auto_graph, color: Colors.white, size: 15),
        ),
        const SizedBox(width: 6),
        Text(
          'MarketCoach AI',
          style: TextStyle(
            color: _teal,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _userBubble() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF12A28C), Color(0xFF0A7B6B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(4),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x3312A28C),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        message.content,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _aiBubble(BuildContext context) {
    final showDots = isStreaming && message.content.isEmpty;
    final showContent = message.content.isNotEmpty;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(4),
        topRight: Radius.circular(18),
        bottomLeft: Radius.circular(18),
        bottomRight: Radius.circular(18),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xFF0D131A).withValues(alpha: 0.88),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
            border: Border.all(
              color: _teal.withValues(alpha: 0.22),
              width: 0.8,
            ),
          ),
          child: showDots
              ? _TypingDots(controller: dotController)
              : showContent
                  ? MarkdownBody(
                      data: message.content,
                      shrinkWrap: true,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.55,
                        ),
                        strong: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                        h3: const TextStyle(
                          color: _teal,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                        listBullet: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        code: TextStyle(
                          color: _teal,
                          backgroundColor:
                              Colors.black.withValues(alpha: 0.3),
                          fontSize: 13,
                        ),
                        blockquoteDecoration: BoxDecoration(
                          color: _teal.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: const Border(
                            left: BorderSide(color: _teal, width: 3),
                          ),
                        ),
                        blockquote: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 14,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final hour = h % 12 == 0 ? 12 : h % 12;
    return '$hour:$m $period';
  }
}

// ─── Typing Dots ─────────────────────────────────────────────────────────────

class _TypingDots extends StatelessWidget {
  const _TypingDots({required this.controller});
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, anim) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final offset = (controller.value - i * 0.25).clamp(0.0, 1.0);
            final opacity = (offset < 0.5 ? offset * 2 : (1 - offset) * 2).clamp(0.3, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Opacity(
                opacity: opacity,
                child: const CircleAvatar(
                  radius: 4,
                  backgroundColor: Color(0xFF12A28C),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ─── Send Button ─────────────────────────────────────────────────────────────

class _SendButton extends StatelessWidget {
  const _SendButton({required this.isStreaming, required this.onSend});
  final bool isStreaming;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isStreaming ? null : onSend,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: isStreaming
              ? const LinearGradient(colors: [Color(0xFF1E293B), Color(0xFF1E293B)])
              : const LinearGradient(
                  colors: [Color(0xFF12A28C), Color(0xFF0A7B6B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: isStreaming
              ? []
              : [
                  BoxShadow(
                    color: const Color(0xFF12A28C).withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Icon(
          Icons.arrow_upward_rounded,
          color: isStreaming
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

// ─── Mic Button ──────────────────────────────────────────────────────────────

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.isListening,
    required this.speechReady,
    required this.onTap,
  });

  final bool isListening;
  final bool speechReady;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: speechReady ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isListening
              ? Colors.redAccent.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isListening
                ? Colors.redAccent.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.12),
            width: isListening ? 1.5 : 1,
          ),
        ),
        child: Icon(
          isListening ? Icons.mic : Icons.mic_none_outlined,
          color: isListening
              ? Colors.redAccent
              : speechReady
                  ? Colors.white70
                  : Colors.white24,
          size: 20,
        ),
      ),
    );
  }
}

// ─── Suggestion Chip ─────────────────────────────────────────────────────────

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF12A28C).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFF12A28C).withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF12A28C), size: 15),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Paints a world-map-style dot grid — dark dots representing continental
/// landmasses, dimly visible against the deep-navy background.
class _WorldMapDotPainter extends CustomPainter {
  // Very rough continent dot map expressed as (xFraction, yFraction) pairs
  // scaled into the widget's actual size at paint time.
  static const List<(double, double)> _landDots = [
    // North America
    (0.08,0.18),(0.10,0.22),(0.12,0.25),(0.14,0.20),(0.16,0.28),(0.18,0.30),
    (0.20,0.25),(0.22,0.32),(0.19,0.38),(0.17,0.42),(0.21,0.44),(0.24,0.40),
    (0.13,0.30),(0.11,0.35),(0.15,0.36),(0.26,0.35),(0.28,0.30),(0.25,0.27),
    (0.10,0.28),(0.12,0.32),(0.08,0.24),(0.06,0.20),(0.07,0.28),
    // South America
    (0.24,0.52),(0.26,0.56),(0.28,0.60),(0.27,0.65),(0.25,0.68),(0.23,0.72),
    (0.22,0.60),(0.24,0.64),(0.26,0.70),(0.28,0.55),(0.30,0.58),(0.29,0.63),
    (0.21,0.55),(0.20,0.62),(0.22,0.68),
    // Europe
    (0.44,0.18),(0.46,0.16),(0.48,0.20),(0.50,0.18),(0.52,0.22),(0.46,0.24),
    (0.48,0.26),(0.50,0.24),(0.42,0.22),(0.44,0.26),(0.54,0.20),(0.56,0.18),
    (0.52,0.16),(0.50,0.14),(0.45,0.14),(0.47,0.12),(0.49,0.10),
    // Africa
    (0.46,0.32),(0.48,0.36),(0.50,0.40),(0.52,0.44),(0.50,0.48),(0.48,0.52),
    (0.46,0.56),(0.48,0.60),(0.50,0.55),(0.52,0.50),(0.54,0.46),(0.52,0.40),
    (0.44,0.38),(0.44,0.44),(0.46,0.48),(0.54,0.38),(0.56,0.42),
    // Asia
    (0.56,0.14),(0.60,0.16),(0.64,0.18),(0.68,0.20),(0.72,0.22),(0.76,0.24),
    (0.70,0.28),(0.66,0.26),(0.62,0.24),(0.58,0.22),(0.56,0.26),(0.60,0.30),
    (0.64,0.32),(0.68,0.28),(0.72,0.30),(0.76,0.26),(0.80,0.22),(0.82,0.20),
    (0.74,0.18),(0.78,0.16),(0.84,0.18),(0.86,0.22),(0.80,0.28),(0.78,0.32),
    (0.74,0.34),(0.70,0.36),(0.66,0.34),(0.62,0.36),(0.58,0.30),(0.56,0.32),
    (0.84,0.24),(0.86,0.28),(0.88,0.26),(0.82,0.26),(0.80,0.30),
    // Australia / Oceania
    (0.76,0.56),(0.78,0.58),(0.80,0.60),(0.82,0.58),(0.84,0.56),(0.80,0.54),
    (0.78,0.62),(0.80,0.64),(0.82,0.62),(0.86,0.54),(0.84,0.60),
    // Japan / SE Asia
    (0.82,0.30),(0.84,0.32),(0.74,0.40),(0.72,0.44),(0.70,0.42),(0.76,0.44),
    (0.78,0.46),(0.74,0.48),(0.72,0.50),(0.70,0.48),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A3456).withOpacity(0.55)
      ..style = PaintingStyle.fill;

    const dotRadius = 1.6;
    const spacing = 18.0;

    // Draw subtle full grid first (very dim ocean dots)
    final gridPaint = Paint()
      ..color = const Color(0xFF0B1E33).withOpacity(0.35)
      ..style = PaintingStyle.fill;

    for (double x = spacing / 2; x < size.width; x += spacing) {
      for (double y = spacing / 2; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, gridPaint);
      }
    }

    // Draw land dots (brighter)
    for (final (fx, fy) in _landDots) {
      final cx = fx * size.width;
      final cy = fy * size.height;
      // Paint a small cluster of dots around each landmark
      for (var dx = -spacing; dx <= spacing; dx += spacing) {
        for (var dy = -spacing * 0.5; dy <= spacing * 0.5; dy += spacing * 0.5) {
          final ox = cx + dx + (dx * 0.1);
          final oy = cy + dy;
          if (ox >= 0 && ox <= size.width && oy >= 0 && oy <= size.height) {
            canvas.drawCircle(Offset(ox, oy), dotRadius, paint);
          }
        }
      }
    }

    // Cyan horizon shimmer line
    final shimmerPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF06B6D4).withOpacity(0.18),
          const Color(0xFF0891B2).withOpacity(0.30),
          const Color(0xFF06B6D4).withOpacity(0.18),
          Colors.transparent,
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(Rect.fromLTWH(0, size.height * 0.72, size.width, 2));
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.72, size.width, 1.5),
      shimmerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
