import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/auth_provider.dart';
import '../../../theme/app_tokens.dart';
import '../../jarvis_voice/data/models/voice_session_bootstrap.dart';
import '../../jarvis_voice/presentation/providers/voice_session_provider.dart';
import '../providers/jarvis_chat_provider.dart';
import 'widgets/chat_bubble.dart';

// ── Mode enum ─────────────────────────────────────────────────────────────────

enum _InputMode { text, voice }

// ── Screen ────────────────────────────────────────────────────────────────────

/// Combined text + voice chat screen for the Coach > Ask tab.
///
/// • Text mode  – multi-turn conversation with Jarvis (Claude API fallback)
/// • Voice mode – real-time voice session via OpenAI Realtime
///               with the reference bottom bar: [Stop] [Avatar+Waveform] [Chat]
class JarvisChatScreen extends ConsumerStatefulWidget {
  final bool showAppBar;

  const JarvisChatScreen({
    super.key,
    this.showAppBar = true,
  });

  @override
  ConsumerState<JarvisChatScreen> createState() => _JarvisChatScreenState();
}

class _JarvisChatScreenState extends ConsumerState<JarvisChatScreen>
    with TickerProviderStateMixin {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();

  _InputMode _mode = _InputMode.text;

  // Waveform animation — runs continuously, animates when voice is active.
  late final AnimationController _waveCtrl;

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Text chat ──────────────────────────────────────────────────────────────

  void _send() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    ref.read(jarvisChatProvider.notifier).sendMessage(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendSuggestion(String text) {
    _inputCtrl.text = text;
    _send();
  }

  // ── Voice ──────────────────────────────────────────────────────────────────

  Future<void> _startVoice() async {
    // ── DIAGNOSTIC LOG 1: confirm mic button tapped ──────────────────────────
    debugPrint('[MicTap] _startVoice() called');

    final isGuest = ref.read(isGuestProvider);
    // ── DIAGNOSTIC LOG 2: auth gate ─────────────────────────────────────────
    debugPrint('[MicTap] isGuest=$isGuest  → voice ${isGuest ? "BLOCKED (anonymous/signed-out)" : "allowed"}');

    if (isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to use voice coaching')),
      );
      return;
    }
    setState(() => _mode = _InputMode.voice);
    try {
      debugPrint('[MicTap] calling voiceSessionProvider.startSession…');
      await ref.read(voiceSessionProvider.notifier).startSession(
        mode: VoiceMode.general,
        screenContext: 'Coach Ask tab',
      );
      debugPrint('[MicTap] startSession() returned OK');
    } catch (e) {
      debugPrint('[MicTap] startSession() threw: $e');
      if (mounted) {
        setState(() => _mode = _InputMode.text);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Voice unavailable: $e')),
        );
      }
    }
  }

  Future<void> _stopVoice() async {
    try {
      await ref.read(voiceSessionProvider.notifier).endSession();
    } catch (_) {}
    if (mounted) setState(() => _mode = _InputMode.text);
  }

  void _switchToChat() {
    // Keep the voice session running but show the text input bar.
    setState(() => _mode = _InputMode.text);
  }

  // ── Safe voice state ───────────────────────────────────────────────────────

  VoiceSessionState? _voiceState() {
    try {
      return ref.watch(voiceSessionProvider);
    } catch (_) {
      return null;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(jarvisChatProvider);
    final isGuest = ref.watch(isGuestProvider);
    final voiceState = _voiceState();

    ref.listen<JarvisChatState>(jarvisChatProvider, (_, __) => _scrollToBottom());

    final isVoiceConnecting = voiceState?.connectionState == VoiceConnectionState.connecting;
    final isVoiceConnected = voiceState?.connectionState == VoiceConnectionState.connected;
    final isVoiceSpeaking = voiceState?.isAssistantSpeaking ?? false;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: widget.showAppBar ? _buildAppBar(chatState) : null,
      body: Column(
        children: [
          // ── Offline / error banner (text mode only) ─────────────────────
          if (_mode == _InputMode.text &&
              (!chatState.isOnline || chatState.errorBanner != null))
            _OfflineBanner(
              message: chatState.errorBanner ?? 'Jarvis is offline',
              onRetry: () =>
                  ref.read(jarvisChatProvider.notifier).checkStatus(),
            ),

          // ── Voice status banner ──────────────────────────────────────────
          if (_mode == _InputMode.voice && isVoiceConnecting)
            _VoiceStatusBanner(label: 'Connecting to voice…'),

          if (_mode == _InputMode.voice &&
              voiceState?.connectionState == VoiceConnectionState.error)
            _VoiceStatusBanner(
              label: voiceState?.errorMessage ?? 'Voice error',
              isError: true,
            ),

          // ── Message / Transcript list ────────────────────────────────────
          Expanded(
            child: _mode == _InputMode.text
                ? _buildTextMessages(chatState)
                : _buildVoiceTranscript(voiceState),
          ),

          // ── Bottom bar ───────────────────────────────────────────────────
          if (_mode == _InputMode.text)
            _TextInputBar(
              controller: _inputCtrl,
              focusNode: _focusNode,
              isTyping: chatState.isTyping,
              isOnline: chatState.isOnline,
              onSend: _send,
              onMicTap: isGuest ? null : _startVoice,
            )
          else
            _buildVoiceBar(
              isConnecting: isVoiceConnecting,
              isConnected: isVoiceConnected,
              isSpeaking: isVoiceSpeaking,
            ),
        ],
      ),
    );
  }

  // ── Message list (text mode) ───────────────────────────────────────────────

  Widget _buildTextMessages(JarvisChatState state) {
    if (state.messages.isEmpty) {
      return _EmptyState(onChipTap: _sendSuggestion);
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      itemCount: state.messages.length + (state.isTyping ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == state.messages.length) return const TypingIndicator();
        return ChatBubble(message: state.messages[i]);
      },
    );
  }

  // ── Voice transcript (voice mode) ──────────────────────────────────────────

  Widget _buildVoiceTranscript(VoiceSessionState? voiceState) {
    final items = voiceState?.transcript ?? [];

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PulsingOrb(),
            const SizedBox(height: 24),
            Text(
              voiceState?.connectionState == VoiceConnectionState.connecting
                  ? 'Connecting…'
                  : 'Listening…',
              style: AppText.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Start speaking to your AI coach',
              style: AppText.micro.copyWith(color: AppColors.textFaint),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        final isUser = item.role == 'user';
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            decoration: BoxDecoration(
              color: isUser
                  ? AppColors.accent.withOpacity(0.15)
                  : AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isUser
                    ? AppColors.accent.withOpacity(0.3)
                    : AppColors.border,
              ),
            ),
            child: item.isToolCall
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.text,
                        style:
                            AppText.micro.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  )
                : Text(
                    item.text,
                    style: AppText.body.copyWith(
                      color: isUser
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
          ),
        );
      },
    );
  }

  // ── Voice bottom bar ───────────────────────────────────────────────────────

  Widget _buildVoiceBar({
    required bool isConnecting,
    required bool isConnected,
    required bool isSpeaking,
  }) {
    // Use explicit padding.bottom instead of SafeArea — with 3 nested Scaffolds
    // SafeArea can lose the nav bar inset set by extendBody:true on RootShell.
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
        child: Container(
          height: 84,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF080E1A),
                Color(0xFF0C1830),
                Color(0xFF080E1A),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(42),
            border: Border.all(
              color: isSpeaking
                  ? const Color(0xFF06B6D4).withOpacity(0.6)
                  : const Color(0xFF1A2E4A),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF06B6D4)
                    .withOpacity(isConnected ? 0.25 : 0.08),
                blurRadius: 24,
                spreadRadius: isConnected ? 3 : 1,
              ),
            ],
          ),
          child: Row(
            children: [
              // ── Stop ──────────────────────────────────────────────────
              _VoiceActionButton(
                label: 'Stop',
                icon: Icons.stop_rounded,
                color: const Color(0xFFEF4444),
                onTap: _stopVoice,
              ),

              // ── Avatar + Waveform ─────────────────────────────────────
              Expanded(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _waveCtrl,
                    builder: (_, __) => _AvatarWaveform(
                      animValue: _waveCtrl.value,
                      isActive: isConnected,
                      isSpeaking: isSpeaking,
                    ),
                  ),
                ),
              ),

              // ── Chat ──────────────────────────────────────────────────
              _VoiceActionButton(
                label: 'Chat',
                icon: Icons.chat_bubble_outline_rounded,
                color: const Color(0xFF06B6D4),
                onTap: _switchToChat,
              ),
            ],
          ),
        ),
    );
  }

  // ── AppBar ──────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(JarvisChatState state) {
    return AppBar(
      backgroundColor: AppColors.bgElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        color: AppColors.textSecondary,
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.accent, AppColors.accentBright],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Jarvis', style: AppText.bodyStrong),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: state.isCheckingStatus
                          ? AppColors.caution
                          : state.isOnline
                              ? AppColors.bullish
                              : AppColors.bearish,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    state.isCheckingStatus
                        ? 'checking…'
                        : state.isOnline
                            ? 'online'
                            : 'offline',
                    style: AppText.micro.copyWith(
                      color: state.isOnline
                          ? AppColors.bullish
                          : AppColors.bearish,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (state.isCheckingStatus)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
          )
        else
          IconButton(
            icon: const Icon(Icons.wifi_find_rounded, size: 20),
            color: AppColors.textMuted,
            tooltip: 'Check Jarvis status',
            onPressed: () =>
                ref.read(jarvisChatProvider.notifier).checkStatus(),
          ),
        IconButton(
          icon: const Icon(Icons.delete_sweep_outlined, size: 20),
          color: AppColors.textMuted,
          tooltip: 'Clear chat',
          onPressed: state.messages.length <= 1
              ? null
              : () => _confirmClear(context),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.border),
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        title: Text('Clear chat?', style: AppText.h3),
        content: Text(
          'This will remove all messages.',
          style: AppText.body.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: AppText.bodyStrong.copyWith(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(jarvisChatProvider.notifier).clearHistory();
            },
            child: Text('Clear',
                style:
                    AppText.bodyStrong.copyWith(color: AppColors.bearish)),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _TextInputBar extends StatelessWidget {
  const _TextInputBar({
    required this.controller,
    required this.focusNode,
    required this.isTyping,
    required this.isOnline,
    required this.onSend,
    this.onMicTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isTyping;
  final bool isOnline;
  final VoidCallback onSend;
  final VoidCallback? onMicTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        border:
            const Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.sm,
        top: AppSpacing.md,
        // viewInsets.bottom = keyboard height (0 when hidden)
        // padding.bottom    = FloatingBottomNav height (via extendBody:true on RootShell)
        // When keyboard is up, padding.bottom shrinks to 0 automatically, so no double-count.
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Mic button — authenticated users only
          if (onMicTap != null) ...[
            GestureDetector(
              onTap: onMicTap,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.card,
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  Icons.mic_none_rounded,
                  size: 20,
                  color: AppColors.accent,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                maxLines: null,
                textInputAction: TextInputAction.newline,
                keyboardType: TextInputType.multiline,
                style: AppText.body.copyWith(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Ask Jarvis anything…',
                  hintStyle:
                      AppText.body.copyWith(color: AppColors.textFaint),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _SendButton(
            isTyping: isTyping,
            isOnline: isOnline,
            onPressed: onSend,
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.isTyping,
    required this.isOnline,
    required this.onPressed,
  });

  final bool isTyping;
  final bool isOnline;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isTyping ? null : onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: isTyping
              ? null
              : const LinearGradient(
                  colors: [AppColors.accent, AppColors.accentBright],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: isTyping ? AppColors.card : null,
          boxShadow: isTyping
              ? null
              : [
                  BoxShadow(
                    color: AppColors.accent.withOpacity(0.4),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
        ),
        child: isTyping
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accent,
                ),
              )
            : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      color: AppColors.bearish.withOpacity(0.12),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 14, color: AppColors.bearish),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppText.micro.copyWith(color: AppColors.bearish),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Retry',
              style:
                  AppText.micro.copyWith(color: AppColors.accentBright),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceStatusBanner extends StatelessWidget {
  const _VoiceStatusBanner({required this.label, this.isError = false});

  final String label;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      color: (isError ? AppColors.bearish : AppColors.accent).withOpacity(0.12),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.mic_rounded,
            size: 14,
            color: isError ? AppColors.bearish : AppColors.accent,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: AppText.micro.copyWith(
                color: isError ? AppColors.bearish : AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onChipTap});

  final void Function(String) onChipTap;

  static const _suggestions = [
    "What's the RSI on AAPL?",
    "Give me a rundown of NVDA",
    "Explain MACD in simple terms",
    "What is a support level?",
    "Is BTC overbought?",
    "What's the 52-week high of TSLA?",
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.accent, AppColors.accentBright],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.auto_awesome, size: 28, color: Colors.white),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Ask me anything', style: AppText.h3),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Market data, stock analysis, or general finance questions.',
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.center,
              children: _suggestions
                  .map((s) => _SuggestionChip(label: s, onTap: onChipTap))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(label),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          style: AppText.micro.copyWith(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

// ── Voice bottom bar sub-widgets ──────────────────────────────────────────────

class _VoiceActionButton extends StatelessWidget {
  const _VoiceActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: SizedBox(
        width: 80,
        height: 84,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.12),
                border: Border.all(color: color.withOpacity(0.35)),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Animated robot avatar with waveform bars (matches reference design).
class _AvatarWaveform extends StatelessWidget {
  const _AvatarWaveform({
    required this.animValue,
    required this.isActive,
    required this.isSpeaking,
  });

  final double animValue;
  final bool isActive;
  final bool isSpeaking;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Waveform bars
          CustomPaint(
            size: const Size(180, 52),
            painter: _WaveformPainter(
              animValue: animValue,
              isActive: isActive,
              isSpeaking: isSpeaking,
            ),
          ),
          // Robot avatar orb
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: isSpeaking
                    ? [const Color(0xFF0E7490), const Color(0xFF06B6D4)]
                    : isActive
                        ? [const Color(0xFF6B21A8), const Color(0xFF06B6D4)]
                        : [
                            const Color(0xFF1E3A5F),
                            const Color(0xFF1E3A5F)
                          ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: (isActive || isSpeaking)
                  ? [
                      BoxShadow(
                        color: const Color(0xFF06B6D4)
                            .withOpacity(isSpeaking ? 0.6 : 0.3),
                        blurRadius: isSpeaking ? 16 : 8,
                        spreadRadius: isSpeaking ? 3 : 1,
                      ),
                    ]
                  : null,
            ),
            child: const Icon(
              Icons.smart_toy_outlined,
              size: 20,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.animValue,
    required this.isActive,
    required this.isSpeaking,
  });

  final double animValue;
  final bool isActive;
  final bool isSpeaking;

  @override
  void paint(Canvas canvas, Size size) {
    final activeColor = isSpeaking
        ? const Color(0xFF06B6D4)
        : isActive
            ? const Color(0xFF0891B2)
            : const Color(0xFF1E3A5F);

    final paint = Paint()
      ..color = activeColor
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    const avatarWidth = 44.0;
    const barCount = 7; // bars on each side
    const barSpacing = 7.0;
    const minHeightFraction = 0.15;
    const maxHeightFraction = 0.80;

    final leftEdge = (size.width - avatarWidth) / 2 - barCount * barSpacing;
    final rightEdge = (size.width + avatarWidth) / 2;

    for (int i = 0; i < barCount; i++) {
      final phase = (animValue * 2 * pi) + (i * 0.9);
      final heightFraction = (isActive || isSpeaking)
          ? minHeightFraction +
              ((sin(phase) + 1) / 2) *
                  (maxHeightFraction - minHeightFraction)
          : minHeightFraction;

      final barH = size.height * heightFraction;
      final top = (size.height - barH) / 2;

      final xLeft = leftEdge + i * barSpacing;
      final xRight = rightEdge + (barCount - 1 - i) * barSpacing;

      canvas.drawLine(Offset(xLeft, top), Offset(xLeft, top + barH), paint);
      canvas.drawLine(
          Offset(xRight, top), Offset(xRight, top + barH), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.animValue != animValue ||
      old.isActive != isActive ||
      old.isSpeaking != isSpeaking;
}

/// Gently pulsing orb shown in the center of the voice transcript when idle.
class _PulsingOrb extends StatefulWidget {
  const _PulsingOrb();

  @override
  State<_PulsingOrb> createState() => _PulsingOrbState();
}

class _PulsingOrbState extends State<_PulsingOrb>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.85, end: 1.05).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF6B21A8), Color(0xFF06B6D4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF06B6D4).withOpacity(0.4),
              blurRadius: 20,
              spreadRadius: 4,
            ),
          ],
        ),
        child: const Icon(Icons.smart_toy_outlined, size: 32, color: Colors.white),
      ),
    );
  }
}
