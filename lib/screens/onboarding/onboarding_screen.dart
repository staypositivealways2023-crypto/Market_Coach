import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/root_shell.dart';

/// One-time disclosure screen shown on first launch.
/// Sets [SharedPreferences] key `disclaimer_accepted_v1` and navigates to [RootShell].
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  static const _prefKey = 'disclaimer_accepted_v1';

  Future<void> _accept(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RootShell()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 48, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF06B6D4), Color(0xFF0891B2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.auto_graph, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 32),

              Text(
                'Welcome to\nMarketCoach',
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'AI-powered market insights and education — right in your pocket.',
                style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white70),
              ),

              const SizedBox(height: 40),

              // Disclaimer card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.gavel_outlined, color: Colors.amber, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Important Disclosure',
                          style: TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'MarketCoach is an educational tool. All content — including AI-generated analysis, price simulations, and market commentary — is for informational and educational purposes only.\n\n'
                      'Nothing in this app constitutes financial advice, investment recommendations, or solicitation to buy or sell any security. Always do your own research and consult a licensed financial advisor before making investment decisions.\n\n'
                      'Past performance does not guarantee future results. Investing involves risk, including loss of principal.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Accept button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _accept(context),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: const Color(0xFF06B6D4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'I Understand — Get Started',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'By continuing you acknowledge this disclosure.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
