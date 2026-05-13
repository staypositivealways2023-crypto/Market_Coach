/// SubscriptionGate — Phase 8
///
/// Two variants:
///
///   SubscriptionGate          — inline; wraps any widget
///   SubscriptionGateScreen    — full-screen; use as the body of a pushed
///                               screen that is Pro-only
///
/// Both variants:
///   • Admin accounts bypass the gate unconditionally.
///   • While the subscription stream is loading (null), the child is shown
///     so there is no paywall flash on startup.
///   • A PaywallBottomSheet is presented when the user taps "Upgrade".
///
/// Usage — inline:
///   SubscriptionGate(
///     feature: 'Probabilistic Engine',
///     child: ProbabilisticCard(data: data),
///   )
///
/// Usage — full screen (inside a Scaffold-returning widget's build):
///   SubscriptionGateScreen(
///     feature: 'Smart Screener',
///     description: 'Filter thousands of stocks by signal, sector & more.',
///     child: const ScreenerScreen(),
///   )

library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../providers/subscription_provider.dart';
import 'paywall_bottom_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Inline gate
// ─────────────────────────────────────────────────────────────────────────────

class SubscriptionGate extends ConsumerWidget {
  /// Content to display when the user is Pro / Admin.
  final Widget child;

  /// Short feature name shown in the locked placeholder, e.g. "Smart Screener".
  final String feature;

  /// Optional one-liner shown below the feature name.
  final String? description;

  const SubscriptionGate({
    super.key,
    required this.child,
    required this.feature,
    this.description,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(subscriptionProvider).valueOrNull;

    // Loading → show child (avoids a jarring paywall flash while Firebase warms up)
    if (sub == null || sub.isPro) return child;

    return _ProLockedInline(feature: feature, description: description);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen gate
// ─────────────────────────────────────────────────────────────────────────────

/// Wrap an entire pushed screen with this widget inside its [build].
/// The screen keeps its own AppBar; only the body is replaced with a
/// locked state for free-tier users.
class SubscriptionGateScreen extends ConsumerWidget {
  final Widget child;
  final String feature;
  final String? description;

  const SubscriptionGateScreen({
    super.key,
    required this.child,
    required this.feature,
    this.description,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(subscriptionProvider).valueOrNull;

    if (sub == null || sub.isPro) return child;

    // Free user — show a stand-alone locked screen instead of the real content.
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(
          feature,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ),
      body: Center(
        child: _ProLockedInline(feature: feature, description: description),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared locked UI
// ─────────────────────────────────────────────────────────────────────────────

class _ProLockedInline extends StatelessWidget {
  final String feature;
  final String? description;

  static const _cyan   = Color(0xFF06B6D4);
  static const _purple = Color(0xFF8B5CF6);

  const _ProLockedInline({required this.feature, this.description});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cyan.withValues(alpha: 0.25)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.card,
            _purple.withValues(alpha: 0.06),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pro badge
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_cyan, _purple],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.workspace_premium, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 16),

          // Feature name
          Text(
            feature,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),

          // "Pro feature" label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_cyan, _purple]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'PRO FEATURE',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Description
          Text(
            description ??
                'Upgrade to Pro to unlock $feature and all other premium features.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 13,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Upgrade button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const PaywallBottomSheet(),
              ),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text(
                'Upgrade to Pro',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: _cyan,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
