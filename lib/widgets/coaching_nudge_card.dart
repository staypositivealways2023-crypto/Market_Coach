/// Coaching Nudge Card — Phase 2 Dean Agent
///
/// Shown below the Scenario Card when the backend's Dean Agent detects a
/// behaviour pattern (e.g. "user checks BTC 5x/week but hasn't studied
/// crypto volatility").
///
/// Design rules:
///  - Non-intrusive: subtle teal gradient, not a full alert card
///  - Dismissible: user can tap × to hide for this session
///  - Actionable: optional lesson link (future Phase 3 hook)
library;

import 'package:flutter/material.dart';

class CoachingNudgeCard extends StatefulWidget {
  /// The nudge message from the Dean Agent (≤ 120 chars).
  final String nudge;

  /// Called when the user taps the lesson link (Phase 3 — can be null for now).
  final VoidCallback? onLearnMore;

  const CoachingNudgeCard({
    super.key,
    required this.nudge,
    this.onLearnMore,
  });

  @override
  State<CoachingNudgeCard> createState() => _CoachingNudgeCardState();
}

class _CoachingNudgeCardState extends State<CoachingNudgeCard>
    with SingleTickerProviderStateMixin {
  bool _dismissed = false;
  late final AnimationController _ctrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _dismiss() {
    _ctrl.reverse().then((_) {
      if (mounted) setState(() => _dismissed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF12A28C).withValues(alpha: 0.12),
              const Color(0xFF0D6EFD).withValues(alpha: 0.06),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF12A28C).withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Coach icon ────────────────────────────────────────────
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF12A28C).withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('💡', style: TextStyle(fontSize: 16)),
              ),
            ),

            const SizedBox(width: 10),

            // ── Message + optional action ─────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Coach',
                    style: TextStyle(
                      color: const Color(0xFF12A28C),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    // Strip the leading emoji if the backend already included one
                    widget.nudge.startsWith('💡 ')
                        ? widget.nudge.substring(3)
                        : widget.nudge,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                  if (widget.onLearnMore != null) ...[
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: widget.onLearnMore,
                      child: const Text(
                        'Start lesson →',
                        style: TextStyle(
                          color: Color(0xFF12A28C),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Dismiss button ────────────────────────────────────────
            GestureDetector(
              onTap: _dismiss,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Colors.white24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
