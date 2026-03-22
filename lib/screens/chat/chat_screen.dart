import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../providers/chat_provider.dart';
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
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _dotController.dispose();
    _focusNode.dispose();
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

    ref.listen<ChatState>(chatProvider, (prev, next) {
      _scrollToBottom();
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
          // Background
          Positioned.fill(
            child: Image.asset(
              'assests/chatbackground.png',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.72)),
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
                _buildInputBar(isStreaming),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isStreaming, ChatState chatState) {
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
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2535).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _teal.withValues(alpha: 0.25),
                      width: 0.8,
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
                      hintText: isStreaming
                          ? 'MarketCoach is thinking...'
                          : 'Ask about any stock or market...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
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
