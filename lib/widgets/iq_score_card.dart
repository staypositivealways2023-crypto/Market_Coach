import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/iq_score_provider.dart';
import 'glass_card.dart';

/// Animated Investor IQ score card.
/// Shows total score with count-up animation and 4 component bars.
class IQScoreCard extends ConsumerWidget {
  const IQScoreCard({super.key});

  static Color _scoreColor(int score) {
    if (score >= 800) return const Color(0xFF10B981); // green
    if (score >= 500) return const Color(0xFF06B6D4); // cyan
    if (score >= 200) return Colors.amber;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iqAsync = ref.watch(iqScoreProvider);

    return iqAsync.when(
      loading: () => GlassCard(
        padding: const EdgeInsets.all(20),
        child: const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) => GlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.psychology_outlined,
                    color: Color(0xFF06B6D4), size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Investor IQ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _scoreColor(data.total).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _scoreColor(data.total).withValues(alpha: 0.4)),
                  ),
                  child: _AnimatedScore(target: data.total),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 4 component bars
            _ComponentBar(
              label: 'Lessons',
              pts: data.lessonPts,
              maxPts: 300,
              color: const Color(0xFF8B5CF6),
            ),
            const SizedBox(height: 8),
            _ComponentBar(
              label: 'Quizzes',
              pts: data.quizPts,
              maxPts: 250,
              color: const Color(0xFF06B6D4),
            ),
            const SizedBox(height: 8),
            _ComponentBar(
              label: 'Paper Trades',
              pts: data.tradePts,
              maxPts: 300,
              color: const Color(0xFF10B981),
            ),
            const SizedBox(height: 8),
            _ComponentBar(
              label: 'AI Chats',
              pts: data.aiPts,
              maxPts: 150,
              color: Colors.amber,
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedScore extends StatefulWidget {
  final int target;
  const _AnimatedScore({required this.target});

  @override
  State<_AnimatedScore> createState() => _AnimatedScoreState();
}

class _AnimatedScoreState extends State<_AnimatedScore>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _anim = Tween<double>(begin: 0, end: widget.target.toDouble())
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
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final score = _anim.value.round();
        final color = _scoreColor(score);
        return Text(
          '$score',
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        );
      },
    );
  }

  static Color _scoreColor(int score) {
    if (score >= 800) return const Color(0xFF10B981);
    if (score >= 500) return const Color(0xFF06B6D4);
    if (score >= 200) return Colors.amber;
    return Colors.redAccent;
  }
}

class _ComponentBar extends StatelessWidget {
  final String label;
  final int pts;
  final int maxPts;
  final Color color;

  const _ComponentBar({
    required this.label,
    required this.pts,
    required this.maxPts,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = maxPts > 0 ? (pts / maxPts).clamp(0.0, 1.0) : 0.0;

    return Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
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
          width: 32,
          child: Text(
            '$pts',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
