import 'package:flutter_test/flutter_test.dart';
import 'package:market_coach/utils/auth_helper.dart';

void main() {
  group('AuthHelper Tests', () {
    test('requiresAuthentication returns false for beginner', () {
      expect(AuthHelper.requiresAuthentication('Beginner'), false);
      expect(AuthHelper.requiresAuthentication('beginner'), false);
      expect(AuthHelper.requiresAuthentication('BEGINNER'), false);
    });

    test('requiresAuthentication returns true for intermediate', () {
      expect(AuthHelper.requiresAuthentication('Intermediate'), true);
      expect(AuthHelper.requiresAuthentication('intermediate'), true);
      expect(AuthHelper.requiresAuthentication('INTERMEDIATE'), true);
    });

    test('requiresAuthentication returns true for advanced', () {
      expect(AuthHelper.requiresAuthentication('Advanced'), true);
      expect(AuthHelper.requiresAuthentication('advanced'), true);
      expect(AuthHelper.requiresAuthentication('ADVANCED'), true);
    });

    test('canAccessLesson returns true for beginner regardless of auth', () {
      expect(AuthHelper.canAccessLesson('Beginner'), true);
      expect(AuthHelper.canAccessLesson('beginner'), true);
    });

    // Note: getUserId() and getUserDisplayName() are simple wrappers around
    // FirebaseAuth.instance.currentUser and require platform channels to test.
    // These will be tested in integration tests with proper Firebase Auth mocking.
  });
}
