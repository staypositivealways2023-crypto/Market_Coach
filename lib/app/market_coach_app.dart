import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
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
          seedColor: const Color(0xFF06B6D4), // Vibrant Cyan
          primary: const Color(0xFF06B6D4), // Cyan
          secondary: const Color(0xFF8B5CF6), // Purple
          tertiary: const Color(0xFF10B981), // Green
          brightness: Brightness.dark,
          surface: const Color(0xFF080E18),
          background: const Color(0xFF03060C),
        ),
        scaffoldBackgroundColor: const Color(0xFF03060C),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF060C14).withOpacity(0.95),
          indicatorColor: const Color(0xFF06B6D4).withOpacity(0.2),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? const Color(0xFF06B6D4)
                  : Colors.white54,
              size: 24,
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              color: states.contains(WidgetState.selected)
                  ? const Color(0xFF06B6D4)
                  : Colors.white54,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF0D1824).withOpacity(0.8),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -1,
          ),
          displayMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
          headlineMedium: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          bodyLarge: TextStyle(fontSize: 16, color: Colors.white),
          bodyMedium: TextStyle(fontSize: 14, color: Colors.white70),
        ),
      ),
      home: authState.when(
        loading: () => const Scaffold(
          backgroundColor: Color(0xFF03060C),
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (_, __) => const LoginScreen(),
        data: (user) {
          if (user == null) return const LoginScreen();
          return FutureBuilder<bool>(
            future: SharedPreferences.getInstance()
                .then((p) => p.getBool('disclaimer_accepted_v1') ?? false),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Scaffold(
                  backgroundColor: Color(0xFF03060C),
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              return snap.data! ? const RootShell() : const OnboardingScreen();
            },
          );
        },
      ),
    );
  }
}
