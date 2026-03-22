import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/lesson_step.dart';
import '../../engine/lesson_engine.dart';
import '../../painters/demo_candle_painter.dart';

/// ST-3: User taps a specific candle. Shake on wrong, green + reveal on correct.
class TapOnChartWidget extends StatefulWidget {
  final TapOnChartStep step;
  final LessonEngine engine;

  const TapOnChartWidget({super.key, required this.step, required this.engine});

  @override
  State<TapOnChartWidget> createState() => _TapOnChartWidgetState();
}

class _TapOnChartWidgetState extends State<TapOnChartWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  // Track canvas size for hit testing
  final _chartKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _shakeAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 4.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 4.0, end: 0.0), weight: 1),
    ]).animate(_shakeCtrl);
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.engine.tapCandleCorrect == true) return;
    final box = _chartKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPos = box.globalToLocal(details.globalPosition);
    final size = box.size;

    const leftPad = 4.0;
    const rightPad = 8.0;
    final chartW = size.width - leftPad - rightPad;
    final n = widget.step.candles.length;
    if (n == 0) return;

    final slotW = chartW / n;
    final tappedX = localPos.dx - leftPad;
    final index = (tappedX / slotW).floor().clamp(0, n - 1);

    widget.engine.tapCandle(index);

    if (widget.engine.tapCandleCorrect == false) {
      HapticFeedback.lightImpact();
      _shakeCtrl.forward(from: 0);
    } else {
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    final step = widget.step;
    final isSolved = engine.tapCandleCorrect == true;
    final isWrong = engine.tapCandleCorrect == false;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Instruction
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF12A28C).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF12A28C).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.touch_app_rounded, color: Color(0xFF12A28C), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    step.instruction,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Chart with tap detection
          AnimatedBuilder(
            animation: _shakeAnim,
            builder: (_, child) => Transform.translate(
              offset: Offset(_shakeAnim.value, 0),
              child: child,
            ),
            child: GestureDetector(
              onTapDown: _onTapDown,
              child: Container(
                key: _chartKey,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSolved
                        ? const Color(0xFF1DE9B6).withValues(alpha: 0.5)
                        : isWrong
                            ? const Color(0xFFFF5252).withValues(alpha: 0.3)
                            : const Color(0xFF12A28C).withValues(alpha: 0.2),
                  ),
                ),
                clipBehavior: Clip.hardEdge,
                child: AnimatedBuilder(
                  animation: engine,
                  builder: (_, __) => CustomPaint(
                    size: const Size(double.infinity, 200),
                    painter: DemoCandlePainter(
                      candles: step.candles,
                      annotations: isSolved ? step.revealAnnotations : [],
                      tappedIndex: engine.tappedCandleIndex,
                      tapCorrect: engine.tapCandleCorrect,
                      revealAnnotations: isSolved,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Feedback message
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: isSolved
                ? _FeedbackBanner(
                    key: const ValueKey('success'),
                    icon: Icons.check_circle_rounded,
                    color: const Color(0xFF1DE9B6),
                    message: step.successMessage,
                  )
                : isWrong
                    ? _FeedbackBanner(
                        key: const ValueKey('wrong'),
                        icon: Icons.cancel_rounded,
                        color: const Color(0xFFFF5252),
                        message: 'Not quite — tap ${step.targetLabel}',
                      )
                    : SizedBox(
                        key: const ValueKey('hint'),
                        height: 8,
                      ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;

  const _FeedbackBanner({
    super.key,
    required this.icon,
    required this.color,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
