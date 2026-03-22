import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/firebase_provider.dart';
import '../providers/auth_provider.dart';
import 'notification_service.dart';

/// Authentication service handling all Firebase Auth operations
class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  AuthService(this._auth, this._db);

  /// Sign up with email and password
  /// Creates a new user account and Firestore profile
  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update display name
      await credential.user?.updateDisplayName(displayName);

      // Create user profile in Firestore (non-fatal — auth still succeeded)
      try {
        await _createUserProfile(credential.user!);
      } catch (_) {
        // Firestore write failed but auth account was created; ignore
      }

      // Save FCM token (non-fatal, platform-guarded inside getToken)
      _saveFcmToken(credential.user!.uid);

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Sign in with email and password
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update last login timestamp
      await _updateLastLogin(credential.user!);

      // Save FCM token (non-fatal, platform-guarded inside getToken)
      _saveFcmToken(credential.user!.uid);

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Sign in anonymously (guest mode)
  /// Auto-invoked on app first launch
  Future<UserCredential> signInAnonymously() async {
    try {
      final credential = await _auth.signInAnonymously();

      // Create user profile for anonymous user
      await _createUserProfile(credential.user!);

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Convert anonymous account to permanent email/password account
  /// Preserves user data (progress, bookmarks, watchlist)
  Future<UserCredential> linkAnonymousWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null || !user.isAnonymous) {
        throw Exception('No anonymous user to link');
      }

      // Create email credential
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );

      // Link credentials
      final linkedCredential = await user.linkWithCredential(credential);

      // Update display name
      await linkedCredential.user?.updateDisplayName(displayName);

      // Update user profile with upgrade info
      await _updateUserProfile(linkedCredential.user!, isUpgrade: true);

      return linkedCredential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Sign out current user
  /// Returns to anonymous state after sign-out (handled by main.dart)
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Create user profile document in Firestore
  Future<void> _createUserProfile(User user) async {
    // Check if profile already exists (avoid overwriting)
    final profileDoc = await _db.collection('users').doc(user.uid).get();
    if (profileDoc.exists) {
      // Just update last login
      await _updateLastLogin(user);
      return;
    }

    await _db.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'email': user.email,
      'display_name': user.displayName,
      'photo_url': user.photoURL,
      'is_anonymous': user.isAnonymous,
      'created_at': FieldValue.serverTimestamp(),
      'last_login_at': FieldValue.serverTimestamp(),
    });
  }

  /// Update user profile in Firestore
  Future<void> _updateUserProfile(User user, {bool isUpgrade = false}) async {
    final data = <String, dynamic>{
      'email': user.email,
      'display_name': user.displayName,
      'photo_url': user.photoURL,
      'is_anonymous': user.isAnonymous,
      'last_login_at': FieldValue.serverTimestamp(),
    };

    if (isUpgrade) {
      data['upgraded_at'] = FieldValue.serverTimestamp();
    }

    await _db.collection('users').doc(user.uid).set(
          data,
          SetOptions(merge: true),
        );
  }

  /// Update last login timestamp
  Future<void> _updateLastLogin(User user) async {
    await _db.collection('users').doc(user.uid).set(
      {'last_login_at': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  /// Save FCM token to Firestore for the given user (fire-and-forget).
  void _saveFcmToken(String uid) {
    NotificationService.getToken().then((token) {
      if (token == null) return;
      _db.collection('users').doc(uid).set(
        {'fcm_token': token},
        SetOptions(merge: true),
      );
    }).catchError((_) {});
  }

  /// Convert FirebaseAuthException to user-friendly error message
  Exception _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return Exception('Password must be at least 6 characters');
      case 'email-already-in-use':
        return Exception('An account already exists with this email');
      case 'invalid-email':
        return Exception('Invalid email address');
      case 'user-not-found':
        return Exception('No account found with this email');
      case 'wrong-password':
        return Exception('Incorrect password');
      case 'too-many-requests':
        return Exception('Too many attempts. Please try again later');
      case 'user-disabled':
        return Exception('This account has been disabled');
      case 'operation-not-allowed':
        return Exception('Operation not allowed. Please contact support');
      case 'invalid-credential':
        return Exception('Invalid credentials. Please try again');
      default:
        return Exception(e.message ?? 'Authentication failed');
    }
  }
}

/// Provider for AuthService
final authServiceProvider = Provider<AuthService>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  final db = ref.watch(firebaseProvider);
  return AuthService(auth, db);
});
