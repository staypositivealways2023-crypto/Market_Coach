import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/jarvis_voice/presentation/providers/voice_session_provider.dart';
import '../screens/coach/coach_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/portfolio/portfolio_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/trade/trade_screen.dart';
import '../widgets/common/floating_bottom_nav.dart';

/// Root shell with 5-tab bottom navigation + floating voice FAB.
/// Home | Trade | Coach | Portfolio | Profile
class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// End the voice session gracefully when the app is backgrounded or killed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      try {
        final voiceState = ref.read(voiceSessionProvider);
        if (voiceState.connectionState == VoiceConnectionState.connected ||
            voiceState.connectionState == VoiceConnectionState.connecting) {
          ref.read(voiceSessionProvider.notifier).endSession();
        }
      } catch (e) {
        // Provider may not be initialised (no active session) — safe to ignore
        debugPrint('[RootShell] Error ending voice session: $e');
      }
    }
  }

  final _screens = const [
    HomeScreen(),
    TradeScreen(),
    CoachScreen(),
    PortfolioScreen(),
    ProfileScreen(),
  ];

  static const _navItems = <FloatingNavItem>[
    FloatingNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    ),
    FloatingNavItem(
      icon: Icons.candlestick_chart_outlined,
      activeIcon: Icons.candlestick_chart,
      label: 'Trade',
    ),
    FloatingNavItem(
      icon: Icons.auto_awesome_outlined,
      activeIcon: Icons.auto_awesome,
      label: 'Coach',
    ),
    FloatingNavItem(
      icon: Icons.pie_chart_outline_rounded,
      activeIcon: Icons.pie_chart_rounded,
      label: 'Portfolio',
    ),
    FloatingNavItem(
      icon: Icons.account_circle_outlined,
      activeIcon: Icons.account_circle,
      label: 'Profile',
    ),
  ];

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: const Color(0xFF080C12),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0C121A),
              Color(0xFF080C12),
              Color(0xFF05080C),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _selectedIndex,
            children: _screens,
          ),
        ),
      ),
      bottomNavigationBar: FloatingBottomNav(
        items: _navItems,
        selectedIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}
