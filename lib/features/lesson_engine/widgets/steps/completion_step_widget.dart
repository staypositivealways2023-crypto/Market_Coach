import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/lesson_step.dart';
import '../../engine/lesson_engine.dart';
import '../../../../models/stock_summary.dart';
import '../../../../features/chart/screens/asset_chart_screen.dart';
import '../../../../providers/auth_provider.dart' show currentUserProvider;
import '../../../../providers/guided_lesson_provider.dart';

class CompletionStepWidget extends ConsumerStatefulWidget {
  final CompletionStep step;
  final LessonEngine engine;

  const CompletionStepWidget({
    super.key,
    required this.step,
    required this.engine,
  });

  @override
  ConsumerState<CompletionStepWidget> createState() =>
      _CompletionStepWidgetState();
}

class _CompletionStepWidgetState extends ConsumerState<CompletionStepWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Saves completion to Firestore (idempotent — only fires once per widget lifecycle).
  void _saveCompletion() {
    if (_saved) return;
    _saved = true;
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid != null) {
      saveGuidedLessonCompletion(uid: uid, lesson: widget.engine.lesson);
    }
  }

  void _openChart(BuildContext context) {
    _saveCompletion();

    final stock = StockSummary(
      ticker: widget.step.ctaTicker,
      name: widget.step.ctaTickerName,
      price: 0,
      changePercent: 0,
      isCrypto: widget.step.ctaIsCrypto,
    );
    // Close the lesson first, then navigate to the chart from the root navigator
    // so the chart sits naturally in the existing nav stack.
    final rootNav = Navigator.of(context, rootNavigator: true);
    rootNav.pop(); // dismiss lesson fullscreen dialog
    rootNav.push(MaterialPageRoute(
      builder: (_) => AssetChartScreen(
        stock: stock,
        initialShowRSI: widget.step.ctaShowRSI,
        initialShowMACD: widget.step.ctaShowMACD,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: FadeTransition(
        opacity: _fade,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // XP Badge
            ScaleTransition(
              scale: _scale,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(colors: [
                    Color(0xFF1DE9B6),
                    Color(0xFF12A28C),
                  ]),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF12A28C).withValues(alpha: 0.4),
                      blurRadius: 28,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '+${widget.step.xpEarned}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Text(
                        'XP',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            // Title
            Text(
              widget.step.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 14),
            // Message
            Text(
              widget.step.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xB3FFFFFF),
                fontSize: 15,
                height: 1.65,
              ),
            ),
            const SizedBox(height: 40),
            // CTA button → opens chart AND marks complete
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _openChart(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF12A28C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.candlestick_chart_outlined, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      widget.step.ctaLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Dismiss / back to lessons — also marks complete
            TextButton(
              onPressed: () {
                _saveCompletion();
                Navigator.of(context).pop();
              },
              child: const Text(
                'Back to Lessons',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
