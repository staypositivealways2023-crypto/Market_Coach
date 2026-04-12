import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'voice_coach_screen.dart';
import 'voice_onboarding_screen.dart';

/// Shown in the Voice tab. Checks whether onboarding has been completed:
///   - No  → shows [VoiceOnboardingScreen]
///   - Yes → shows [VoiceCoachScreen]
class VoiceEntry extends ConsumerStatefulWidget {
  const VoiceEntry({super.key});

  @override
  ConsumerState<VoiceEntry> createState() => _VoiceEntryState();
}

class _VoiceEntryState extends ConsumerState<VoiceEntry> {
  bool? _onboardingDone; // null = loading

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final done = await isVoiceOnboardingDone();
    if (mounted) setState(() => _onboardingDone = done);
  }

  @override
  Widget build(BuildContext context) {
    if (_onboardingDone == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D131A),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF12A28C)),
        ),
      );
    }

    if (!_onboardingDone!) {
      return VoiceOnboardingScreen(
        onComplete: () => setState(() => _onboardingDone = true),
      );
    }

    return const VoiceCoachScreen();
  }
}
