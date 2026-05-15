import 'package:firebase_auth/firebase_auth.dart';

/// Helper class for authentication checks
class AuthHelper {
  /// Check if user is authenticated (including anonymous users)
  static bool isUserAuthenticated() {
    final user = FirebaseAuth.instance.currentUser;
    return user != null; // Any signed-in user (including anonymous)
  }

  /// Check if user is a real authenticated user (NOT anonymous)
  static bool isRealUserAuthenticated() {
    final user = FirebaseAuth.instance.currentUser;
    return user != null && !user.isAnonymous;
  }

  /// Check if a lesson level requires real authentication (not anonymous)
  static bool requiresAuthentication(String level) {
    final levelLower = level.toLowerCase();
    // Beginner lessons are free, others require real login (not anonymous)
    return levelLower != 'beginner';
  }

  /// Check if user can access a lesson
  static bool canAccessLesson(String lessonLevel) {
    // Beginner content is always accessible
    if (lessonLevel.toLowerCase() == 'beginner') {
      return true;
    }

    // Intermediate and Advanced require REAL authentication (not anonymous)
    return isRealUserAuthenticated();
  }

  /// Get the current user ID or 'guest_user' if not authenticated
  static String getUserId() {
    final user = FirebaseAuth.instance.currentUser;
    return user?.uid ?? 'guest_user';
  }

  /// Get user display name or 'Guest'
  static String getUserDisplayName() {
    final user = FirebaseAuth.instance.currentUser;
    return user?.displayName ?? user?.email?.split('@').first ?? 'Guest';
  }
}
