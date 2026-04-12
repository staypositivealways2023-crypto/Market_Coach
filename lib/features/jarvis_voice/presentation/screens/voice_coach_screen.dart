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

/// Voice coach screen — the primary UI for Jarvis voice sessions.
///
/// Layout:
///   ModeChipBar (General | Lesson | Trade Debrief)
///   TranscriptList (scrolling chat bubbles)
///   VoiceWaveform (visible when assistant is speaking)
///   Error banner
///   BottomBar: [fallback text input] [MicButton]
class VoiceCoachScreen extends ConsumerStatefulWidget {
  /// Optional: pre-select mode when navigating from a specific context.
  final VoiceMode? initialMode;

  /// Optional: active ticker (from stock detail screen).
  final String? activeSymbol;

  /// Optional: active lesson ID (from lesson detail screen).
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

class _VoiceCoachScreenState extends ConsumerState<VoiceCoachScreen> {
  final _textController = TextEditingController();
  bool _micPermission = false;

  @override
  void initState() {
    super.initState();
    _requestMicPermission();
  }

  Future<void> _requestMicPermission() async {
    final granted = await MicrophoneService.requestPermission();
    if (mounted) setState(() => _micPermission = granted);
  }

  @override
  void dispose() {
    _textController.dispose();
    // End session if still active when screen is disposed
    final state = ref.read(voiceSessionProvider);
    if (state.connectionState == VoiceConnectionState.connected) {
      ref.read(voiceSessionProvider.notifier).endSession();
    }
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _toggleSession() async {
    final notifier = ref.read(voiceSessionProvider.notifier);
    final state = ref.read(voiceSessionProvider);

    if (state.connectionState == VoiceConnectionState.connected) {
      await notifier.endSession();
    } else if (state.connectionState == VoiceConnectionState.idle ||
        state.connectionState == VoiceConnectionState.error) {
      if (!_micPermission) {
        _showSnack('Microphone permission required.');
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Show paywall when free-tier voice limit is hit
    ref.listen<VoiceSessionState>(voiceSessionProvider, (prev, next) {
      if (next.isLimitReached && !(prev?.isLimitReached ?? false)) {
        ref.read(voiceSessionProvider.notifier).clearLimitReached();
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const PaywallBottomSheet(),
        );
      }
    });

    final state = ref.watch(voiceSessionProvider);
    final micState = _resolveMicState(state);
    final modeChipEnabled = state.connectionState == VoiceConnectionState.idle ||
        state.connectionState == VoiceConnectionState.error;

    return Scaffold(
      backgroundColor: const Color(0xFF0D131A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D131A),
        foregroundColor: Colors.white,
        title: const Text('Voice Coach'),
        centerTitle: false,
        elevation: 0,
        actions: [
          if (state.activeSymbol != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Chip(
                label: Text(
                  state.activeSymbol!,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                backgroundColor: const Color(0xFF12A28C).withValues(alpha: 0.2),
                side: const BorderSide(color: Color(0xFF12A28C), width: 0.5),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Mode chips (locked while session is active)
            ModeChipBar(
              selected: state.mode,
              enabled: modeChipEnabled,
              onSelected: (mode) {
                ref.read(voiceSessionProvider.notifier).setMode(mode);
              },
            ),

            // Connection status indicator
            if (state.connectionState == VoiceConnectionState.connecting)
              const LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                color: Color(0xFF12A28C),
              ),

            // Transcript area
            Expanded(
              child: TranscriptList(items: state.transcript),
            ),

            // Waveform (assistant speaking)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: VoiceWaveform(
                active: state.isAssistantSpeaking,
              ),
            ),

            // Error banner
            if (state.errorMessage != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade800, width: 0.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

            // Bottom bar: fallback text input + mic button
            _BottomBar(
              textController: _textController,
              micState: micState,
              onMicTap: _toggleSession,
            ),
          ],
        ),
      ),
    );
  }

  MicState _resolveMicState(VoiceSessionState state) {
    switch (state.connectionState) {
      case VoiceConnectionState.connecting:
      case VoiceConnectionState.ending:
        return MicState.loading;
      case VoiceConnectionState.connected:
        return state.isAssistantSpeaking ? MicState.speaking : MicState.listening;
      case VoiceConnectionState.idle:
      case VoiceConnectionState.error:
        return MicState.idle;
    }
  }
}

// ── Bottom bar ─────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final TextEditingController textController;
  final MicState micState;
  final VoidCallback onMicTap;

  const _BottomBar({
    required this.textController,
    required this.micState,
    required this.onMicTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          // Fallback text input (collapsed when session is active)
          if (micState == MicState.idle)
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF111925),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white12),
                ),
                child: TextField(
                  controller: textController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Or type a question…',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            )
          else
            const Spacer(),
          MicButton(micState: micState, onTap: onMicTap),
        ],
      ),
    );
  }
}
