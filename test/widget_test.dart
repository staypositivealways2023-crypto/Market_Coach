import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_coach/app/market_coach_app.dart';
import 'package:market_coach/providers/auth_provider.dart';

void main() {
  testWidgets('App renders login screen when signed out', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Simulate signed-out state — no Firebase required.
          authStateProvider.overrideWith(
            (ref) => Stream<User?>.value(null),
          ),
        ],
        child: const MarketCoachApp(),
      ),
    );

    // Allow async providers to settle.
    await tester.pumpAndSettle();

    // App should show the login screen (has a Sign In button).
    expect(find.text('Sign In'), findsWidgets);
  });
}
