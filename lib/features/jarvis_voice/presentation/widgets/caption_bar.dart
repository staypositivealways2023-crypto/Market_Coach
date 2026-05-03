/// CaptionBar — floating teleprompter-style caption area shown while the
/// assistant is speaking or the user is being transcribed.
///
/// Layout:
///   ┌─────────────────────────────────────────────────────────┐
///   │  [AI text streaming word-by-word in large readable font] │
///   │  ─────────────────────────────────────────────────────── │
///   │  [Ghost row: "Listening…" / user transcript preview]     │
///   └─────────────────────────────────────────────────────────┘
library;

import 'dart:ui';

import 'package:flutter/material.dart';

const _kTeal   = Color(0xFF12A28C);
const _kCyan   = Color(0xFF06B6D4);
const _kOrange = Color(0xFFF97316);

class CaptionBar extends StatelessWidget {
  /// Text currently being streamed for the active assistant turn.
  final String assistantText;

  /// True while user speech VAD is active.
  final bool isUserSpeaking;

  /// True while the assistant audio is playing.
  final bool isAssistantSpeaking;

  /// True while the session is connecting.
  final bool isConnecting;

  const CaptionBar({
    super.key,
    required this.assistantText,
    required this.isUserSpeaking,
    required this.isAssistantSpeaking,
    required this.isConnecting,
  });

  @override
  Widget build(BuildContext context) {
    final bool showAssistant = assistantText.isNotEmpty;
    final bool showGhost = isUserSpeaking || isConnecting;

    // If nothing to show, render a compact idle hint
    if (!showAssistant && !showGhost) {
      return _IdleHint();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF0D1420).withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _borderColor(isAssistantSpeaking, isUserSpeaking).withValues(alpha: 0.35),
                width: 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── AI caption ──────────────────────────────────────────────
                if (showAssistant)
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, showGhost ? 6 : 14),
                    child: _AssistantCaption(text: assistantText),
                  ),

                // ── Divider ─────────────────────────────────────────────────
                if (showAssistant && showGhost)
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: Colors.white.withValues(alpha: 0.07),
                    indent: 16,
                    endIndent: 16,
                  ),

                // ── Ghost row ────────────────────────────────────────────────
                if (showGhost)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: _GhostRow(
                      isConnecting: isConnecting,
                      isUserSpeaking: isUserSpeaking,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _borderColor(bool speaking, bool userSpeaking) {
    if (userSpeaking) return _kOrange;
    if (speaking) return _kCyan;
    return _kTeal;
  }
}

// ── Assistant caption text ────────────────────────────────────────────────────

class _AssistantCaption extends StatelessWidget {
  final String text;
  const _AssistantCaption({required this.text});

  @override
  Widget build(BuildContext context) {
    // Limit to last ~240 chars so the bar doesn't grow unbounded
    final display = text.length > 240
        ? '…${text.substring(text.length - 240)}'
        : text;

    return Text(
      display,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.55,
        letterSpacing: 0.1,
      ),
      maxLines: 5,
      overflow: TextOverflow.fade,
    );
  }
}

// ── Ghost row ─────────────────────────────────────────────────────────────────

class _GhostRow extends StatefulWidget {
  final bool isConnecting;
  final bool isUserSpeaking;
  const _GhostRow({required this.isConnecting, required this.isUserSpeaking});

  @override
  State<_GhostRow> createState() => _GhostRowState();
}

class _GhostRowState extends State<_GhostRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _blink;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _blink, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isConnecting ? _kOrange : _kTeal;
    final label = widget.isConnecting ? 'Connecting…' : 'Listening…';

    return Row(
      children: [
        FadeTransition(
          opacity: _opacity,
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.75),
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ── Idle hint (nothing active) ────────────────────────────────────────────────

class _IdleHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 0.8),
        ),
        child: const Text(
          'Tap the mic to start speaking',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white24,
            fontSize: 13,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
