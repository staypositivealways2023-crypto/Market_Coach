/// Floating Voice Button — sits above the bottom nav in RootShell.
///
/// Compact mic FAB that:
///   • Is hidden when the Coach tab (index 2) is active — that tab has its
///     own mic in the ChatScreen input bar, so two mics would be confusing.
///   • Returns SizedBox.shrink() for guest users (voice requires auth).
///   • Pulses with teal glow when idle.
///   • Shows orange dot when a session is connecting.
///   • Shows animated ring when connected (live session).
///   • Tap → navigates to VoiceCoachScreen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/jarvis_voice/data/models/voice_session_bootstrap.dart';
import '../features/jarvis_voice/presentation/providers/voice_session_provider.dart';
import '../features/jarvis_voice/presentation/screens/voice_coach_screen.dart';
import '../providers/auth_provider.dart';

class FloatingVoiceButton extends ConsumerStatefulWidget {
  /// Index of the currently selected bottom-nav tab.
  /// Pass the parent RootShell's _selectedIndex so the FAB knows when to hide.
  final int selectedIndex;

  const FloatingVoiceButton({super.key, required this.selectedIndex});

  @override
  ConsumerState<FloatingVoiceButton> createState() => _FloatingVoiceButtonState();
}

class _FloatingVoiceButtonState extends ConsumerState<FloatingVoiceButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _ring;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _scale = Tween<double>(begin: 0.93, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _ring = Tween<double>(begin: 0.4, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedIndex == 2) {
      return const SizedBox.shrink();
    }

    // ── Guard: hide for guest / unauthenticated users ───────────────────────
    final isGuest = ref.watch(isGuestProvider);
    if (isGuest) return const SizedBox.shrink();

    // ── Safe to watch voiceSessionProvider (user is authenticated) ──────────
    // Use try-catch so a provider error doesn't crash the whole shell.
    VoiceConnectionState connectionState = VoiceConnectionState.idle;
    bool isSpeaking = false;
    try {
      final voiceState = ref.watch(voiceSessionProvider);
      connectionState = voiceState.connectionState;
      isSpeaking = voiceState.isAssistantSpeaking;
    } catch (_) {
      // Provider not yet ready — show idle state
    }

    final isConnected  = connectionState == VoiceConnectionState.connected;
    final isConnecting = connectionState == VoiceConnectionState.connecting;

    final Color accent;
    if (isConnecting) {
      accent = Colors.orange;
    } else if (isConnected && isSpeaking) {
      accent = const Color(0xFF06B6D4);
    } else if (isConnected) {
      accent = const Color(0xFF12A28C);
    } else {
      accent = const Color(0xFF12A28C);
    }

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const VoiceCoachScreen(initialMode: VoiceMode.general),
        ),
      ),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer pulse ring (only when live)
                if (isConnected)
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: accent.withOpacity(_ring.value),
                        width: 2.5,
                      ),
                    ),
                  ),

                // FAB body
                Transform.scale(
                  scale: isConnected ? _scale.value : 1.0,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          accent.withOpacity(0.85),
                          accent.withOpacity(0.55),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withOpacity(isConnected ? 0.55 : 0.3),
                          blurRadius: isConnected ? 20 : 12,
                          spreadRadius: isConnected ? 4 : 0,
                        ),
                      ],
                      border: Border.all(
                        color: Colors.white.withOpacity(0.18),
                        width: 1.2,
                      ),
                    ),
                    child: Icon(
                      isConnecting
                          ? Icons.hourglass_top_rounded
                          : isConnected
                              ? Icons.mic_rounded
                              : Icons.mic_none_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),

                // Live indicator dot (top-right)
                if (isConnected)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isSpeaking
                            ? const Color(0xFF06B6D4)
                            : Colors.greenAccent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF0D1117),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
