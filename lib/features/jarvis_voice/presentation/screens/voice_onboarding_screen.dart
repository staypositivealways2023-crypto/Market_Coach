import 'dart:developer' as dev;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../providers/auth_provider.dart';
import '../../data/jarvis_repository.dart';

/// Key stored in SharedPreferences once onboarding is complete.
const _kOnboardingDoneKey = 'voice_onboarding_done';

/// Returns true if voice onboarding has already been completed on this device.
Future<bool> isVoiceOnboardingDone() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kOnboardingDoneKey) ?? false;
}

Future<void> _markOnboardingDone() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kOnboardingDoneKey, true);
}

// ── Data model ─────────────────────────────────────────────────────────────────

class _OnboardingStep {
  final String memoryKey;
  final String question;
  final List<_Option> options;
  const _OnboardingStep({
    required this.memoryKey,
    required this.question,
    required this.options,
  });
}

class _Option {
  final String label;
  final String value;
  const _Option(this.label, this.value);
}

const _steps = [
  _OnboardingStep(
    memoryKey: 'experience_level',
    question: 'How would you describe your investing experience?',
    options: [
      _Option('Just getting started', 'beginner'),
      _Option('Some experience', 'intermediate'),
      _Option('Experienced trader/investor', 'advanced'),
    ],
  ),
  _OnboardingStep(
    memoryKey: 'primary_market',
    question: 'What markets do you focus on?',
    options: [
      _Option('Stocks & ETFs', 'stocks'),
      _Option('Crypto', 'crypto'),
      _Option('Both', 'mixed'),
    ],
  ),
  _OnboardingStep(
    memoryKey: 'goal',
    question: 'What is your main goal?',
    options: [
      _Option('Learn to invest', 'learn to invest'),
      _Option('Improve my trading', 'improve trading'),
      _Option('Analyse the market', 'market analysis'),
      _Option('Track my portfolio', 'portfolio tracking'),
    ],
  ),
  _OnboardingStep(
    memoryKey: 'risk_tolerance',
    question: 'How do you feel about risk?',
    options: [
      _Option('Play it safe', 'conservative'),
      _Option('Balanced', 'moderate'),
      _Option('High risk, high reward', 'aggressive'),
    ],
  ),
];

// ── Screen ─────────────────────────────────────────────────────────────────────

/// Shown on first voice tab visit. Collects 4 profile facts and seeds
/// voice_profile_memory via /api/voice/memory/upsert.
///
/// Calls [onComplete] when all steps are done.
class VoiceOnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;

  const VoiceOnboardingScreen({super.key, required this.onComplete});

  @override
  ConsumerState<VoiceOnboardingScreen> createState() => _VoiceOnboardingScreenState();
}

class _VoiceOnboardingScreenState extends ConsumerState<VoiceOnboardingScreen> {
  int _currentStep = 0;
  bool _saving = false;
  final Map<String, String> _answers = {};

  Future<void> _selectOption(_Option option) async {
    final step = _steps[_currentStep];
    _answers[step.memoryKey] = option.value;

    if (_currentStep < _steps.length - 1) {
      setState(() => _currentStep++);
      return;
    }

    // Last step — save all answers
    setState(() => _saving = true);
    final user = ref.read(currentUserProvider);
    if (user != null) {
      await _saveAnswers(user);
    }
    await _markOnboardingDone();
    widget.onComplete();
  }

  Future<void> _saveAnswers(User user) async {
    final repo = ref.read(jarvisRepositoryProvider);
    for (final entry in _answers.entries) {
      try {
        await repo.upsertMemory(user, key: entry.key, value: entry.value, source: 'onboarding');
      } catch (e) {
        dev.log('[VoiceOnboarding] upsert failed for ${entry.key}: $e', name: 'VoiceOnboarding');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_currentStep];

    return Scaffold(
      backgroundColor: const Color(0xFF0D131A),
      body: SafeArea(
        child: _saving
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF12A28C)),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40),

                    // Progress dots
                    Row(
                      children: List.generate(_steps.length, (i) {
                        final active = i == _currentStep;
                        final done = i < _currentStep;
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          width: active ? 20 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: done || active
                                ? const Color(0xFF12A28C)
                                : Colors.white12,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 40),

                    // Header
                    const Text(
                      'Set up your\nVoice Coach',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This helps Jarvis personalise your coaching from day one.',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),

                    const SizedBox(height: 40),

                    // Question
                    Text(
                      step.question,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Options
                    ...step.options.map((opt) => _OptionCard(
                          label: opt.label,
                          onTap: () => _selectOption(opt),
                        )),

                    const Spacer(),

                    // Step counter
                    Center(
                      child: Text(
                        '${_currentStep + 1} of ${_steps.length}',
                        style: const TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }
}

// ── Option card ────────────────────────────────────────────────────────────────

class _OptionCard extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _OptionCard({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF111925),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
          ],
        ),
      ),
    );
  }
}
