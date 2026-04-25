import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Onboarding disclaimer acceptance state provider.
/// Caches the result to avoid redundant SharedPreferences lookups.
final onboardingCompleteProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('disclaimer_accepted_v1') ?? false;
});

/// Mark onboarding as complete (called after user accepts disclaimer).
final onboardingNotifierProvider =
    StateNotifierProvider<OnboardingNotifier, bool>((ref) {
  return OnboardingNotifier(ref);
});

class OnboardingNotifier extends StateNotifier<bool> {
  OnboardingNotifier(this.ref) : super(false);
  final Ref ref;

  Future<void> markComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('disclaimer_accepted_v1', true);
    state = true;
    // Invalidate the FutureProvider to refresh it
    ref.invalidate(onboardingCompleteProvider);
  }
}
