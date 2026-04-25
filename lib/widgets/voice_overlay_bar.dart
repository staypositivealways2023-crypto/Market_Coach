/// Voice Overlay Bar — Phase 12
///
/// A persistent, faded bar that floats above every screen in the app.
/// Shows the last transcript line + mic state.
/// Tap → navigate to VoiceCoachScreen.
/// Long-press mic → start a new voice session.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/jarvis_voice/data/models/voice_session_bootstrap.dart';
import '../features/jarvis_voice/presentation/providers/voice_session_provider.dart';
import '../features/jarvis_voice/presentation/screens/voice_coach_screen.dart';
import '../providers/auth_provider.dart';

class VoiceOverlayBar extends ConsumerWidget {
  const VoiceOverlayBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voiceState = ref.watch(voiceSessionProvider);
    final isGuest    = ref.watch(isGuestProvider);

    // Don't show for guests
    if (isGuest) return const SizedBox.shrink();

    final isConnected = voiceState.connectionState ==
        VoiceConnectionState.connected;
    final isConnecting = voiceState.connectionState ==
        VoiceConnectionState.connecting;
    final isSpeaking  = voiceState.isAssistantSpeaking;

    // Get latest transcript line (user or assistant)
    String statusText = 'Tap to talk to your AI coach';
    if (isConnecting) {
      statusText = 'Connecting…';
    } else if (isConnected) {
      final transcript = voiceState.transcript;
      if (transcript.isNotEmpty) {
        final last = transcript.last;
        statusText = last.text.length > 60
            ? '${last.text.substring(0, 57)}…'
            : last.text;
      } else {
        statusText = 'Listening…';
      }
    }

    // Mic icon color
    Color micColor;
    if (isConnecting) {
      micColor = Colors.orange;
    } else if (isConnected && isSpeaking) {
      micColor = const Color(0xFF06B6D4);
    } else if (isConnected) {
      micColor = const Color(0xFF12A28C);
    } else {
      micColor = Colors.white38;
    }

    return GestureDetector(
      onTap: () => _openVoiceScreen(context),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117).withOpacity(0.92),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isConnected
                ? const Color(0xFF12A28C).withOpacity(0.4)
                : Colors.white.withOpacity(0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Live indicator dot
            if (isConnected)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _PulseDot(color: micColor),
              ),

            // Status text
            Expanded(
              child: Text(
                statusText,
                style: TextStyle(
                  color: isConnected ? Colors.white : Colors.white54,
                  fontSize: 13,
                  fontWeight: isConnected ? FontWeight.w500 : FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const SizedBox(width: 8),

            // Mic button — long press starts session, tap opens screen
            GestureDetector(
              onLongPress: () => _startSession(context, ref),
              onTap: () => _openVoiceScreen(context),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isConnected
                      ? micColor.withOpacity(0.15)
                      : Colors.white.withOpacity(0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isConnecting
                      ? Icons.hourglass_top_rounded
                      : isConnected
                          ? Icons.mic_rounded
                          : Icons.mic_none_rounded,
                  size: 18,
                  color: micColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openVoiceScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const VoiceCoachScreen(
          initialMode: VoiceMode.general,
        ),
      ),
    );
  }

  void _startSession(BuildContext context, WidgetRef ref) {
    // Navigate to voice screen which auto-starts the session
    _openVoiceScreen(context);
  }
}

// ── Animated pulsing dot ──────────────────────────────────────────────────────

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.7, end: 1.3).animate(
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
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withOpacity(0.5),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}
