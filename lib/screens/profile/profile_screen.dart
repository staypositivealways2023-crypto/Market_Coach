import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../providers/iq_score_provider.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/glass_card.dart';
import '../auth/login_screen.dart';
import '../auth/signup_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final profileAsync = ref.watch(userProfileProvider);
    final isGuest = ref.watch(isGuestProvider);
    final iqAsync = ref.watch(iqScoreProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: authState.when(
          data: (user) {
            if (user == null) return _buildSignInPrompt(context);
            return profileAsync.when(
              data: (profile) => _buildIdentityScreen(
                  context, ref, user, profile, isGuest, iqAsync),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (_, __) => _buildIdentityScreen(
                  context, ref, user, null, isGuest, iqAsync),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ),
    );
  }

  Widget _buildIdentityScreen(
    BuildContext context,
    WidgetRef ref,
    dynamic user,
    dynamic profile,
    bool isGuest,
    AsyncValue<IQScoreData> iqAsync,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        // ── Top bar: name + gear ──────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile?.displayNameOrEmail ?? (isGuest ? 'Guest' : user.email ?? ''),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (isGuest)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Guest',
                          style: TextStyle(
                              color: Colors.orange,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    )
                  else if (user.email != null)
                    Text(user.email!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white54)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.settings_outlined, color: cs.primary, size: 26),
              tooltip: 'Settings',
              onPressed: () => _showSettings(context, ref, user.uid, isGuest),
            ),
          ],
        ),

        if (isGuest) ...[
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: FilledButton.tonal(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen())),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                child: const Text('Sign In'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SignupScreen())),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                child: const Text('Sign Up'),
              ),
            ),
          ]),
        ],

        const SizedBox(height: 28),

        // ── IQ Score Ring ─────────────────────────────────────────────────
        Center(
          child: iqAsync.when(
            loading: () => const SizedBox(
                height: 180,
                width: 180,
                child: Center(child: CircularProgressIndicator())),
            error: (_, __) => const SizedBox.shrink(),
            data: (iq) => _IQRing(score: iq.total),
          ),
        ),

        const SizedBox(height: 28),

        // ── 3 stat chips ──────────────────────────────────────────────────
        iqAsync.when(
          loading: () => const SizedBox(height: 72),
          error: (_, __) => const SizedBox.shrink(),
          data: (iq) => Row(children: [
            Expanded(
                child: _StatChip(
                    label: 'Win Rate',
                    value:
                        '${(iq.winRate * 100).toStringAsFixed(0)}%',
                    color: const Color(0xFF10B981))),
            const SizedBox(width: 12),
            Expanded(
                child: _StatChip(
                    label: 'Lessons',
                    value: '${iq.completedLessons}',
                    color: const Color(0xFF8B5CF6))),
            const SizedBox(width: 12),
            Expanded(
                child: _StatChip(
                    label: 'Quiz Acc.',
                    value:
                        '${(iq.quizAccuracy * 100).toStringAsFixed(0)}%',
                    color: const Color(0xFF06B6D4))),
          ]),
        ),

        const SizedBox(height: 24),

        // ── IQ component breakdown ────────────────────────────────────────
        iqAsync.whenData((iq) => GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Score breakdown',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: Colors.white70)),
                  const SizedBox(height: 14),
                  _ScoreBar(
                      label: 'Lessons',
                      pts: iq.lessonPts,
                      maxPts: 300,
                      color: const Color(0xFF8B5CF6)),
                  const SizedBox(height: 10),
                  _ScoreBar(
                      label: 'Quizzes',
                      pts: iq.quizPts,
                      maxPts: 250,
                      color: const Color(0xFF06B6D4)),
                  const SizedBox(height: 10),
                  _ScoreBar(
                      label: 'Trades',
                      pts: iq.tradePts,
                      maxPts: 300,
                      color: const Color(0xFF10B981)),
                  const SizedBox(height: 10),
                  _ScoreBar(
                      label: 'AI Chats',
                      pts: iq.aiPts,
                      maxPts: 150,
                      color: Colors.amber),
                ],
              ),
            )).value ??
            const SizedBox.shrink(),

        const SizedBox(height: 24),

        // ── Sign out ──────────────────────────────────────────────────────
        if (!isGuest)
          OutlinedButton.icon(
            onPressed: () => _handleSignOut(context, ref),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign Out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
      ],
    );
  }

  void _showSettings(
      BuildContext context, WidgetRef ref, String uid, bool isGuest) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1824),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SettingsSheet(uid: uid, isGuest: isGuest),
    );
  }

  Widget _buildSignInPrompt(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_circle, size: 80, color: cs.primary),
            const SizedBox(height: 24),
            Text('Sign in to track your progress',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginScreen())),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 16)),
              child: const Text('Sign In'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Sign Out')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authServiceProvider).signOut();
    }
  }
}

// ── IQ Ring ───────────────────────────────────────────────────────────────────

class _IQRing extends StatefulWidget {
  final int score;
  const _IQRing({required this.score});

  @override
  State<_IQRing> createState() => _IQRingState();
}

class _IQRingState extends State<_IQRing> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _progress;
  late Animation<int> _counter;

  static Color _color(int s) {
    if (s >= 800) return const Color(0xFF10B981);
    if (s >= 500) return const Color(0xFF06B6D4);
    if (s >= 200) return Colors.amber;
    return Colors.redAccent;
  }

  static String _rank(int s) {
    if (s >= 800) return 'Expert';
    if (s >= 500) return 'Proficient';
    if (s >= 200) return 'Learning';
    return 'Beginner';
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _progress = Tween<double>(begin: 0, end: widget.score / 1000)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _counter = IntTween(begin: 0, end: widget.score)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(widget.score);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final score = _counter.value;
        return SizedBox(
          width: 180,
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Track ring
              SizedBox(
                width: 180,
                height: 180,
                child: CustomPaint(
                  painter: _RingPainter(
                    progress: _progress.value,
                    color: _color(score),
                    trackColor: Colors.white.withOpacity(0.07),
                    strokeWidth: 14,
                  ),
                ),
              ),
              // Center content
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$score',
                    style: TextStyle(
                      color: color,
                      fontSize: 52,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -2,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Investor IQ',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _rank(score),
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  const _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

// ── Stat chips ────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ── Score bar ─────────────────────────────────────────────────────────────────

class _ScoreBar extends StatelessWidget {
  final String label;
  final int pts;
  final int maxPts;
  final Color color;
  const _ScoreBar(
      {required this.label,
      required this.pts,
      required this.maxPts,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final ratio = maxPts > 0 ? (pts / maxPts).clamp(0.0, 1.0) : 0.0;
    return Row(children: [
      SizedBox(
        width: 72,
        child: Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 28,
        child: Text('$pts',
            textAlign: TextAlign.right,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

// ── Settings bottom sheet ─────────────────────────────────────────────────────

class _SettingsSheet extends ConsumerStatefulWidget {
  final String uid;
  final bool isGuest;
  const _SettingsSheet({required this.uid, required this.isGuest});

  @override
  ConsumerState<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends ConsumerState<_SettingsSheet> {
  bool? _notificationsEnabled;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .get();
      final val = snap.data()?['notifications_enabled'] as bool?;
      if (mounted) setState(() => _notificationsEnabled = val ?? false);
    } catch (_) {
      if (mounted) setState(() => _notificationsEnabled = false);
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() => _notificationsEnabled = value);
    try {
      final Map<String, dynamic> updates = {'notifications_enabled': value};
      if (value) {
        await NotificationService.requestPermission();
        final token = await NotificationService.getToken();
        if (token != null) updates['fcm_token'] = token;
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .update(updates);
    } catch (_) {
      if (mounted) setState(() => _notificationsEnabled = !value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Settings',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          if (!widget.isGuest)
            SwitchListTile(
              secondary: Icon(Icons.notifications_outlined,
                  color: theme.colorScheme.primary),
              title: const Text('Daily Market Brief',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              subtitle: const Text('7am watchlist summary',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              value: _notificationsEnabled ?? false,
              onChanged: _notificationsEnabled == null
                  ? null
                  : _toggleNotifications,
              activeColor: theme.colorScheme.primary,
            ),
          ListTile(
            leading:
                Icon(Icons.link, color: theme.colorScheme.primary),
            title: const Text('Linked broker',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: const Text('Not connected',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () {},
          ),
          ListTile(
            leading: Icon(Icons.lock_outline,
                color: theme.colorScheme.primary),
            title: const Text('Privacy & security',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: const Text('2FA, devices, data controls',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () {},
          ),
          ListTile(
            leading:
                Icon(Icons.chat_bubble_outline, color: theme.colorScheme.primary),
            title: const Text('Contact support',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
