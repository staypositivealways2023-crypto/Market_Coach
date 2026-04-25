import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/onboarding_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../theme/app_tokens.dart';
import 'root_shell.dart';

class MarketCoachApp extends ConsumerWidget {
  const MarketCoachApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return MaterialApp(
      title: 'MarketCoach',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          primary: AppColors.accent,
          secondary: AppColors.accentBright,
          tertiary: AppColors.bullish,
          brightness: Brightness.dark,
          surface: AppColors.card,
          background: AppColors.bg,
        ),
        scaffoldBackgroundColor: AppColors.bg,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: AppColors.textPrimary),
        ),
        cardTheme: CardThemeData(
          color: AppColors.card,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 0.6),
        textTheme: const TextTheme(
          displayLarge: AppText.display,
          displayMedium: AppText.h1,
          headlineMedium: AppText.h2,
          titleLarge: AppText.h3,
          titleMedium: AppText.bodyStrong,
          bodyLarge: AppText.bodyStrong,
          bodyMedium: AppText.body,
          labelLarge: AppText.caption,
          labelSmall: AppText.micro,
        ),
      ),
      home: authState.when(
        loading: () => const Scaffold(
          backgroundColor: AppColors.bg,
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stackTrace) {
          // Log error for debugging
          debugPrint('Auth error: $error');
          debugPrint('Stack trace: $stackTrace');
          return Scaffold(
            backgroundColor: AppColors.bg,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: AppColors.bearish, size: 64),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Authentication Error',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      // Retry by navigating to login
                      Navigator.of(_buildContext).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        },
        data: (user) {
          // No user — show login screen
          if (user == null) return const LoginScreen();

          // Signed in (any user: email, anonymous) — check onboarding
          final onboardingState = ref.watch(onboardingCompleteProvider);

          return onboardingState.when(
            loading: () => const Scaffold(
              backgroundColor: AppColors.bg,
              body: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stackTrace) {
              debugPrint('Onboarding error: $error');
              // If onboarding check fails, show the main app (fail open)
              return const RootShell();
            },
            data: (isComplete) {
              return isComplete ? const RootShell() : const OnboardingScreen();
            },
          );
        },
      ),
    );
  }

  // Helper to get context from MaterialApp navigator
  static BuildContext get _buildContext => navigatorKey.currentContext!;
  static final navigatorKey = GlobalKey<NavigatorState>();
}
