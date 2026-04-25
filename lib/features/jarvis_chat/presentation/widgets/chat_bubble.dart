import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme/app_tokens.dart';
import '../../providers/jarvis_chat_provider.dart';

/// A single chat message bubble.
///
/// User messages: right-aligned, teal accent background.
/// Jarvis messages: left-aligned, dark card background.
/// Error messages: left-aligned, red-tinted background.
class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.message});

  final ChatMessage message;

  bool get _isUser => message.role == MessageRole.user;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: _isUser ? 48 : 0,
        right: _isUser ? 0 : 48,
        bottom: AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment:
            _isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!_isUser) _avatar(),
          const SizedBox(width: AppSpacing.sm),
          Flexible(child: _bubble(context)),
          if (_isUser) const SizedBox(width: AppSpacing.sm),
        ],
      ),
    );
  }

  Widget _avatar() {
    return Container(
      width: 28,
      height: 28,
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
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
    );
  }

  Widget _bubble(BuildContext context) {
    final Color bg = _isUser
        ? AppColors.accent.withOpacity(0.18)
        : message.isError
            ? AppColors.bearish.withOpacity(0.12)
            : AppColors.card;

    final Color border = _isUser
        ? AppColors.accent.withOpacity(0.35)
        : message.isError
            ? AppColors.bearish.withOpacity(0.25)
            : AppColors.border;

    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: message.content));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied to clipboard'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppRadius.card),
            topRight: const Radius.circular(AppRadius.card),
            bottomLeft: Radius.circular(_isUser ? AppRadius.card : 4),
            bottomRight: Radius.circular(_isUser ? 4 : AppRadius.card),
          ),
          border: Border.all(color: border, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _parseContent(message.content),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _formatTime(message.timestamp),
              style: AppText.micro.copyWith(color: AppColors.textFaint),
            ),
          ],
        ),
      ),
    );
  }

  /// Render markdown-lite: *italic*, **bold**, `code`, and line breaks.
  Widget _parseContent(String text) {
    return Text(
      text,
      style: AppText.body.copyWith(
        color: message.isError ? AppColors.bearish : AppColors.textSecondary,
        height: 1.5,
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Animated typing indicator shown while Jarvis is generating a response.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm, right: 48),
      child: Row(
        children: [
          // Same avatar as Jarvis bubbles
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.accent, AppColors.accentBright],
              ),
            ),
            child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.card),
                topRight: Radius.circular(AppRadius.card),
                bottomRight: Radius.circular(AppRadius.card),
                bottomLeft: Radius.circular(4),
              ),
              border: Border.all(color: AppColors.border, width: 0.8),
            ),
            child: AnimatedBuilder(
              animation: _anim,
              builder: (_, __) => Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final delay = i * 0.33;
                  final t = (_anim.value - delay).clamp(0.0, 1.0);
                  final opacity = (0.3 + 0.7 * (t < 0.5 ? t * 2 : (1 - t) * 2))
                      .clamp(0.0, 1.0);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Opacity(
                      opacity: opacity,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
