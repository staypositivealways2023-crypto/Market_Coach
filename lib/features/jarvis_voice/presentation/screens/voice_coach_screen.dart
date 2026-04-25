/// Voice Coach Screen — premium redesign.
///
/// Layout:
///   ┌─ AppBar (back + active symbol chip) ─────────────────────────────────┐
///   │  ModeChipBar (General | Lesson | Trade Debrief)                      │
///   │                                                                       │
///   │  TranscriptList (scrollable glass-bubble chat)                       │
///   │                                                                       │
///   │  ── AI Orb + status text ──────────────────────────────────────────  │
///   │     Central animated orb changes color / pulse based on state        │
///   │     StatusText ("Tap mic to start" / "Listening…" / "Speaking…")     │
///   │                                                                       │
///   │  ── VoiceWaveform (visible when speaking) ─────────────────────────  │
///   │                                                                       │
///   │  ── Error banner ──────────────────────────────────────────────────  │
///   │                                                                       │
///   └─ BottomBar (Mute | big MicButton | End) ────────────────────────────┘
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/voice_session_bootstrap.dart';
import '../providers/voice_session_provider.dart';
import '../widgets/mic_button.dart';
import '../widgets/mode_chip_bar.dart';
import '../widgets/transcript_list.dart';
import '../widgets/voice_waveform.dart';
import '../../../../core/services/microphone_service.dart';
import '../../../../widgets/paywall_bottom_sheet.dart';

// ── Palette ────────────────────────────────────────────────────────────────────
const _kBg        = Color(0xFF060B11);
const _kBgCard    = Color(0xFF0D1420);
const _kTeal      = Color(0xFF12A28C);
const _kCyan      = Color(0xFF06B6D4);
const _kOrange    = Color(0xFFF97316);
const _kDivider   = Color(0xFF1A2535);

class VoiceCoachScreen extends ConsumerStatefulWidget {
  final VoiceMode? initialMode;
  final String? activeSymbol;
  final String? activeLessonId;

  const VoiceCoachScreen({
    super.key,
    this.initialMode,
    this.activeSymbol,
    this.activeLessonId,
  });

  @override
  ConsumerState<VoiceCoachScreen> createState() => _VoiceCoachScreenState();
}

class _VoiceCoachScreenState extends ConsumerState<VoiceCoachScreen>
    with TickerProviderStateMixin {
  final _textController = TextEditingController();
  bool _micPermission = false;
  ProviderSubscription<VoiceSessionState>? _voiceSessionSub;

  /// Fires if we're still in "Listening" state 18 seconds after connecting
  /// with no assistant response. Surfaces a clear error and ends the session
  /// so the user isn't left staring at an unresponsive orb.
  Timer? _listeningWatchdog;

  // ── Orb animation controllers ──────────────────────────────────────────────
  late AnimationController _orbPulse;
  late AnimationController _orbRing;
  late Animation<double> _pulseScale;
  late Animation<double> _ringOpacity;

  @override
  void initState() {
    super.initState();
    _requestMicPermission();
    _voiceSessionSub = ref.listenManual<VoiceSessionState>(
      voiceSessionProvider,
      (prev, next) {
        if (!mounted) return;

        // ── Paywall ────────────────────────────────────────────────────────
        if (next.isLimitReached && !(prev?.isLimitReached ?? false)) {
          ref.read(voiceSessionProvider.notifier).clearLimitReached();
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const PaywallBottomSheet(),
          );
        }

        // ── Connection watchdog ────────────────────────────────────────────
        // Start an 18-second timer the moment we enter the connected (Listening)
        // state. Cancel it the instant the assistant speaks or the session ends.
        // If it fires, the session is silently stuck — surface a clear message.
        final wasConnected = prev?.connectionState == VoiceConnectionState.connected;
        final isNowConnected = next.connectionState == VoiceConnectionState.connected;
        final assistantJustSpoke = !(prev?.isAssistantSpeaking ?? false) && next.isAssistantSpeaking;

        if (!wasConnected && isNowConnected) {
          // Just transitioned to connected — arm the watchdog.
          _listeningWatchdog?.cancel();
          _listeningWatchdog = Timer(const Duration(seconds: 18), () {
            if (!mounted) return;
            final s = ref.read(voiceSessionProvider);
            if (s.connectionState == VoiceConnectionState.connected &&
                !s.isAssistantSpeaking &&
                s.transcript.isEmpty) {
              // Still stuck in listening with zero activity — bail out.
              _showSnack('No response from voice service. Check your connection and try again.');
              ref.read(voiceSessionProvider.notifier).endSession();
            }
          });
        }

        if (assistantJustSpoke || !isNowConnected) {
          // Assistant spoke or session ended — watchdog no longer needed.
          _listeningWatchdog?.cancel();
          _listeningWatchdog = null;
        }
      },
    );

    _orbPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _orbRing = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _pulseScale = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _orbPulse, curve: Curves.easeInOut),
    );

    _ringOpacity = Tween<double>(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(parent: _orbRing, curve: Curves.easeOut),
    );
  }

  Future<void> _requestMicPermission() async {
    final granted = await MicrophoneService.requestPermission();
    if (mounted) setState(() => _micPermission = granted);
  }

  @override
  void dispose() {
    _listeningWatchdog?.cancel();
    _voiceSessionSub?.close();
    _textController.dispose();
    _orbPulse.dispose();
    _orbRing.dispose();
    super.dispose();
  }

  // ── Session control ────────────────────────────────────────────────────────

  Future<void> _toggleSession() async {
    final notifier = ref.read(voiceSessionProvider.notifier);
    final state    = ref.read(voiceSessionProvider);

    if (state.connectionState == VoiceConnectionState.connected ||
        state.connectionState == VoiceConnectionState.ending) {
      await notifier.endSession();
    } else if (state.connectionState == VoiceConnectionState.idle ||
        state.connectionState == VoiceConnectionState.error) {
      if (!_micPermission) {
        _showSnack('Microphone permission required. Please grant it in Settings.');
        return;
      }
      await notifier.startSession(
        mode: state.mode,
        activeSymbol: widget.activeSymbol,
        activeLessonId: widget.activeLessonId,
        screenContext: _buildScreenContext(),
      );
    }
  }

  String _buildScreenContext() {
    if (widget.activeSymbol != null) return 'stock_detail_${widget.activeSymbol}';
    if (widget.activeLessonId != null) return 'lesson_${widget.activeLessonId}';
    return 'voice_coach_screen';
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
        backgroundColor: const Color(0xFF1A2535),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state   = ref.watch(voiceSessionProvider);
    final micState = _resolveMicState(state);
    final canChangeMode = state.connectionState == VoiceConnectionState.idle ||
        state.connectionState == VoiceConnectionState.error;

    final orbColor = _resolveOrbColor(state);

    return Scaffold(
      backgroundColor: _kBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A1628), _kBg, Color(0xFF04070B)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Header ─────────────────────────────────────────────────────
              _Header(activeSymbol: state.activeSymbol ?? widget.activeSymbol),

              // ── Mode chip bar ───────────────────────────────────────────────
              ModeChipBar(
                selected: state.mode,
                enabled: canChangeMode,
                onSelected: (mode) =>
                    ref.read(voiceSessionProvider.notifier).setMode(mode),
              ),

              // ── Connecting progress bar ────────────────────────────────────
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: state.connectionState == VoiceConnectionState.connecting ? 2 : 0,
                child: const LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  color: _kTeal,
                ),
              ),

              // ── Transcript ─────────────────────────────────────────────────
              Expanded(
                child: state.transcript.isEmpty
                    ? _EmptyTranscriptHint(state: state)
                    : TranscriptList(items: state.transcript),
              ),

              // ── AI Orb ─────────────────────────────────────────────────────
              _AiOrb(
                color: orbColor,
                isActive: state.connectionState == VoiceConnectionState.connected,
                pulseScale: _pulseScale,
                ringOpacity: _ringOpacity,
                ringController: _orbRing,
                statusText: _statusText(state),
              ),

              const SizedBox(height: 8),

              // ── Waveform (speaking) ─────────────────────────────────────────
              AnimatedOpacity(
                opacity: state.isAssistantSpeaking ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: VoiceWaveform(active: state.isAssistantSpeaking),
                ),
              ),

              const SizedBox(height: 4),

              // ── Error banner ────────────────────────────────────────────────
              if (state.errorMessage != null)
                _ErrorBanner(message: state.errorMessage!),

              // ── Bottom controls ─────────────────────────────────────────────
              _BottomBar(
                textController: _textController,
                micState: micState,
                isConnected: state.connectionState == VoiceConnectionState.connected,
                onMicTap: _toggleSession,
                onEnd: state.connectionState == VoiceConnectionState.connected
                    ? () => ref.read(voiceSessionProvider.notifier).endSession()
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _resolveOrbColor(VoiceSessionState state) {
    switch (state.connectionState) {
      case VoiceConnectionState.connecting:
        return _kOrange;
      case VoiceConnectionState.connected:
        return state.isAssistantSpeaking ? _kCyan : _kTeal;
      default:
        return _kTeal.withOpacity(0.7);
    }
  }

  String _statusText(VoiceSessionState state) {
    switch (state.connectionState) {
      case VoiceConnectionState.connecting:
        return 'Connecting…';
      case VoiceConnectionState.connected:
        if (state.isAssistantSpeaking) return 'Speaking…';
        return 'Listening…';
      case VoiceConnectionState.ending:
        return 'Ending session…';
      case VoiceConnectionState.error:
        return 'Something went wrong';
      default:
        return 'Tap mic to start';
    }
  }

  MicState _resolveMicState(VoiceSessionState state) {
    switch (state.connectionState) {
      case VoiceConnectionState.connecting:
      case VoiceConnectionState.ending:
        return MicState.loading;
      case VoiceConnectionState.connected:
        return state.isAssistantSpeaking ? MicState.speaking : MicState.listening;
      default:
        return MicState.idle;
    }
  }
}

// ── Header ─────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String? activeSymbol;
  const _Header({this.activeSymbol});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 20, color: Colors.white70),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Voice Coach',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
                const Text(
                  'Powered by Jarvis',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          if (activeSymbol != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _kTeal.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kTeal.withOpacity(0.4), width: 0.8),
              ),
              child: Text(
                activeSymbol!,
                style: const TextStyle(
                    color: _kTeal, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}

// ── AI Orb ─────────────────────────────────────────────────────────────────────

class _AiOrb extends StatelessWidget {
  final Color color;
  final bool isActive;
  final Animation<double> pulseScale;
  final Animation<double> ringOpacity;
  final AnimationController ringController;
  final String statusText;

  const _AiOrb({
    required this.color,
    required this.isActive,
    required this.pulseScale,
    required this.ringOpacity,
    required this.ringController,
    required this.statusText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: AnimatedBuilder(
              animation: ringController,
              builder: (context, _) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer ring (sweeps when active)
                    if (isActive)
                      Transform.rotate(
                        angle: ringController.value * 2 * math.pi,
                        child: CustomPaint(
                          size: const Size(120, 120),
                          painter: _ArcPainter(
                            color: color,
                            opacity: 0.35,
                          ),
                        ),
                      ),

                    // Pulse ring
                    if (isActive)
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color.withOpacity(ringOpacity.value * 0.5),
                            width: 1.5,
                          ),
                        ),
                      ),

                    // Core orb
                    ScaleTransition(
                      scale: isActive ? pulseScale : const AlwaysStoppedAnimation(1.0),
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              color.withOpacity(0.9),
                              color.withOpacity(0.4),
                              color.withOpacity(0.0),
                            ],
                            stops: const [0.0, 0.55, 1.0],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: color.withOpacity(isActive ? 0.5 : 0.2),
                              blurRadius: isActive ? 32 : 16,
                              spreadRadius: isActive ? 8 : 0,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.auto_awesome,
                            color: Colors.white.withOpacity(0.9),
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Text(
              statusText,
              key: ValueKey(statusText),
              style: TextStyle(
                color: isActive ? Colors.white70 : Colors.white38,
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final Color color;
  final double opacity;
  const _ArcPainter({required this.color, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: size.width / 2 - 2,
    );
    canvas.drawArc(rect, 0, math.pi * 1.2, false, paint);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => false;
}

// ── Empty transcript hint ──────────────────────────────────────────────────────

class _EmptyTranscriptHint extends StatelessWidget {
  final VoiceSessionState state;
  const _EmptyTranscriptHint({required this.state});

  @override
  Widget build(BuildContext context) {
    final isIdle = state.connectionState == VoiceConnectionState.idle;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isIdle ? Icons.tips_and_updates_outlined : Icons.mic_rounded,
              size: 32,
              color: Colors.white24,
            ),
            const SizedBox(height: 12),
            Text(
              isIdle
                  ? 'Ask me anything about markets, your portfolio, or how to trade.'
                  : 'Session active — start speaking…',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white30,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error banner ────────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withOpacity(0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade800.withOpacity(0.5), width: 0.8),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12, height: 1.4),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom bar ─────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final TextEditingController textController;
  final MicState micState;
  final bool isConnected;
  final VoidCallback onMicTap;
  final VoidCallback? onEnd;

  const _BottomBar({
    required this.textController,
    required this.micState,
    required this.isConnected,
    required this.onMicTap,
    this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: _kDivider, width: 0.8),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── Text input (only when idle) ────────────────────────────────
          if (!isConnected)
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: _kBgCard,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white10, width: 0.8),
                ),
                child: TextField(
                  controller: textController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Or type a question…',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                  ),
                ),
              ),
            ),

          // ── End session button (when connected) ───────────────────────
          if (isConnected && onEnd != null) ...[
            _ControlButton(
              icon: Icons.call_end_rounded,
              label: 'End',
              color: Colors.redAccent,
              onTap: onEnd!,
            ),
            const SizedBox(width: 20),
          ],

          // ── Mic button ─────────────────────────────────────────────────
          MicButton(micState: micState, onTap: onMicTap),
        ],
      ),
    );
  }
}

// ── Small labelled control button ─────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.3), width: 0.8),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: color.withOpacity(0.8), fontSize: 10),
          ),
        ],
      ),
    );
  }
}
