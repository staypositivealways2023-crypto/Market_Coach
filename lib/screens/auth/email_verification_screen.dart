/// Email Verification Gate — Phase 4
///
/// Shown after signup (and on re-launch) when the user's email is not yet
/// verified. Blocks entry to the main app until Firebase confirms verification.
///
/// Flow:
///   1. User signs up → AuthService sends verification email
///   2. This screen appears instead of RootShell
///   3. Every 4 seconds: silently reload user + check emailVerified
///   4. When verified → MarketCoachApp detects the change and routes to RootShell
///   5. "Resend" button re-sends the email (rate-limited by Firebase)
library;

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';

class EmailVerificationScreen extends ConsumerStatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  ConsumerState<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends ConsumerState<EmailVerificationScreen> {
  Timer? _pollTimer;
  bool _resendLoading = false;
  bool _resentSuccessfully = false;

  @override
  void initState() {
    super.initState();
    // Poll Firebase every 4 seconds — as soon as the user clicks the link in
    // their email, this will pick it up within 4 seconds.
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      await FirebaseAuth.instance.currentUser?.reload();
      // authStateProvider will re-emit after reload; MarketCoachApp handles routing.
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _resend() async {
    setState(() => _resendLoading = true);
    try {
      final authService = ref.read(authServiceProvider);
      await authService.resendVerificationEmail();
      if (mounted) setState(() => _resentSuccessfully = true);
      // Reset "sent" indicator after 4 seconds
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _resentSuccessfully = false);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not send email: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _resendLoading = false);
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final email = user?.email ?? 'your inbox';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_unread_outlined,
                  color: AppColors.accent,
                  size: 40,
                ),
              ),
              const SizedBox(height: 28),

              // Title
              const Text(
                'Verify your email',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Body
              Text(
                'We sent a verification link to\n$email\n\nOpen it in your email app — '
                'the app will continue automatically once verified.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),

              // Resend button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _resendLoading ? null : _resend,
                  icon: _resendLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                          ),
                        )
                      : Icon(
                          _resentSuccessfully
                              ? Icons.check_circle_outline
                              : Icons.refresh,
                          size: 18,
                        ),
                  label: Text(
                    _resentSuccessfully ? 'Email sent!' : 'Resend verification email',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _resentSuccessfully
                        ? Colors.greenAccent
                        : AppColors.accent,
                    side: BorderSide(
                      color: _resentSuccessfully
                          ? Colors.greenAccent.withValues(alpha: 0.5)
                          : AppColors.accent.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Wrong email / sign out
              TextButton(
                onPressed: _signOut,
                child: Text(
                  'Wrong email? Sign out',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.38),
                    fontSize: 13,
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Waiting indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Waiting for verification…',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.25),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
