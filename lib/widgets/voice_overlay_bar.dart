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
  /// Pass RootShell's selectedIndex so the bar hides on the Coach tab (index 2),
  /// which already provides its own voice and chat surfaces.
  final int selectedIndex;
  const VoiceOverlayBar({super.key, required this.selectedIndex});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Hide on Coach tab — it has its own mic / chat UI
    if (selectedIndex == 2) return const SizedBox.shrink();

    final isGuest = ref.watch(isGuestProvider);
    if (isGuest) return const SizedBox.shrink();

    final voiceState = ref.watch(voiceSessionProvider);
    final isConnected  = voiceState.connectionState == VoiceConnectionState.connected;
    final isConnecting = voiceState.connectionState == VoiceConnectionState.connecting;
    final isActive     = isConnected || isConnecting;

    // Hide entirely when no session is running — no clutter when idle
    if (!isActive) return const SizedBox.shrink();

    final isSpeaking = voiceState.isAssistantSpeaking;

    final Color micColor;
    if (isConnecting) {
      micColor = Colors.orange;
    } else if (isSpeaking) {
      micColor = const Color(0xFF06B6D4);
    } else {
      micColor = const Color(0xFF12A28C);
    }

    String statusText;
    if (isConnecting) {
      statusText = 'Connecting…';
    } else {
      final transcript = voiceState.transcript;
      if (transcript.isNotEmpty) {
        final last = transcript.last;
        statusText = last.text.length > 60 ? '${last.text.substring(0, 57)}…' : last.text;
      } else {
        statusText = 'Listening…';
      }
    }

    return GestureDetector(
      onTap: () => _openVoiceScreen(context),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: micColor.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            _PulseDot(color: micColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                statusText,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isConnecting ? Icons.hourglass_top_rounded : Icons.mic_rounded,
              size: 18,
              color: micColor,
            ),
          ],
        ),
      ),
    );
  }

  void _openVoiceScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VoiceCoachScreen(initialMode: VoiceMode.general)),
    );
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
              color: widget.color.withValues(alpha: 0.5),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}
