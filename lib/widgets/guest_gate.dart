/// GuestGate — Phase 4
///
/// Wraps any widget that requires a signed-in (non-anonymous) user.
/// If the current user is a guest (anonymous), shows a prompt instead
/// of the protected content.
///
/// Usage:
///   GuestGate(
///     feature: 'AI analysis',
///     child: MyProtectedWidget(),
///   )
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';

class GuestGate extends ConsumerWidget {
  /// The content to show when the user is authenticated.
  final Widget child;

  /// Short feature name shown in the prompt, e.g. "AI analysis".
  final String feature;

  /// Custom message — defaults to a sensible one based on [feature].
  final String? message;

  const GuestGate({
    super.key,
    required this.child,
    required this.feature,
    this.message,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isGuest = user == null || user.isAnonymous;

    if (!isGuest) return child;

    return _GuestPrompt(feature: feature, message: message);
  }
}

/// Inline card shown instead of gated content for guest users.
class _GuestPrompt extends StatelessWidget {
  final String feature;
  final String? message;

  const _GuestPrompt({required this.feature, this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_outline_rounded,
              color: AppColors.accent,
              size: 24,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Create a free account',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message ??
                '$feature is available to registered users.\nSign up free — it takes 30 seconds.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 13,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              child: const Text(
                'Sign up free',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Convenience: a full-screen guest gate for tab-level blocking.
/// Use this as the body of a screen when the entire screen is restricted.
class GuestGateScreen extends ConsumerWidget {
  final Widget child;
  final String feature;
  final String? message;

  const GuestGateScreen({
    super.key,
    required this.child,
    required this.feature,
    this.message,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isGuest = user == null || user.isAnonymous;

    if (!isGuest) return child;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: _GuestPrompt(feature: feature, message: message),
      ),
    );
  }
}
