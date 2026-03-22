import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_profile.dart';
import 'firebase_provider.dart';

/// Base Firebase Auth instance provider
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

/// Auth state stream - emits User? on authentication state changes
final authStateProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return auth.authStateChanges();
});

/// Current user provider - derived from authStateProvider
final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.maybeWhen(data: (user) => user, orElse: () => null);
});

/// User ID provider - REPLACES all 'guest_user' constants
/// Returns the current user's UID or 'guest_user' as fallback
final userIdProvider = Provider<String>((ref) {
  final user = ref.watch(currentUserProvider);
  return user?.uid ?? 'guest_user';
});

/// Is authenticated provider (not anonymous)
final isAuthenticatedProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider);
  return user != null && !user.isAnonymous;
});

/// Is guest provider (anonymous or null)
final isGuestProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider);
  return user == null || user.isAnonymous;
});

/// User profile stream provider
/// Returns the Firestore user profile document for the current user
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(null);

  final db = ref.watch(firebaseProvider);
  return db.collection('users').doc(user.uid).snapshots().map((snapshot) {
    if (!snapshot.exists || snapshot.data() == null) return null;
    return UserProfile.fromMap(snapshot.data()!, snapshot.id);
  });
});
