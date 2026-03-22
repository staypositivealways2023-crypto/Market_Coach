import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/lesson_engine.dart';
import '../models/guided_lesson.dart';
import '../models/lesson_step.dart';
import '../widgets/lesson_step_renderer.dart';
import '../../../providers/auth_provider.dart' show currentUserProvider;
import '../../../providers/guided_lesson_provider.dart' show saveGuidedLessonOpened;
import '../../../providers/iq_score_provider.dart';

/// Main screen for the guided lesson engine.
/// Owns the [LessonEngine], drives a [PageView], and shows
/// the progress bar + Continue / Back controls.
class GuidedLessonScreen extends ConsumerStatefulWidget {
  final GuidedLesson lesson;
  const GuidedLessonScreen({super.key, required this.lesson});

  @override
  ConsumerState<GuidedLessonScreen> createState() => _GuidedLessonScreenState();
}

class _GuidedLessonScreenState extends ConsumerState<GuidedLessonScreen> {
  late final LessonEngine _engine;
  late final PageController _pageController;
  @override
  void initState() {
    super.initState();
    _engine = LessonEngine(widget.lesson);
    _pageController = PageController();
    _engine.addListener(_onEngineChanged);

    // Record that the user opened this lesson
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = ref.read(currentUserProvider)?.uid;
      if (uid != null) {
        saveGuidedLessonOpened(
          uid: uid,
          lessonId: widget.lesson.id,
          level: widget.lesson.level,
        );
      }
    });
  }

  void _onEngineChanged() {
    if (!mounted) return;

    // Sync PageView to engine index
    final target = _engine.currentIndex;
    if (_pageController.hasClients &&
        (_pageController.page?.round() ?? 0) != target) {
      _pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeInOut,
      );
    }
    setState(() {});
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineChanged);
    _engine.dispose();
    _pageController.dispose();
    super.dispose();
  }

  bool get _isCompletion => _engine.currentStep is CompletionStep;

  Future<void> _onQuizAnswered(bool isCorrect) async {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'quiz_total_count': FieldValue.increment(1),
        if (isCorrect) 'quiz_correct_count': FieldValue.increment(1),
      });
      ref.invalidate(iqScoreProvider);
    } catch (_) {
      // Non-fatal — quiz tracking is best-effort
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D131A),
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(engine: _engine),
            _ProgressBar(progress: _engine.progress),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.lesson.steps.length,
                itemBuilder: (context, index) {
                  return AnimatedBuilder(
                    animation: _engine,
                    builder: (context, _) => LessonStepRenderer(
                      step: widget.lesson.steps[index],
                      engine: _engine,
                      onAnswered: _onQuizAnswered,
                    ),
                  );
                },
              ),
            ),
            if (!_isCompletion) _BottomControls(engine: _engine),
          ],
        ),
      ),
    );
  }
}

// ─── Top bar ──────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final LessonEngine engine;
  const _TopBar({required this.engine});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.close, color: Colors.white54, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              engine.lesson.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _StepCounter(engine: engine),
        ],
      ),
    );
  }
}

class _StepCounter extends StatelessWidget {
  final LessonEngine engine;
  const _StepCounter({required this.engine});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${engine.currentIndex + 1} / ${engine.lesson.steps.length}',
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── Progress bar ─────────────────────────────────────────────────────────────
class _ProgressBar extends StatelessWidget {
  final double progress;
  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: progress),
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeInOut,
          builder: (context2, value, child) => LinearProgressIndicator(
            value: value,
            minHeight: 4,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor:
                const AlwaysStoppedAnimation<Color>(Color(0xFF12A28C)),
          ),
        ),
      ),
    );
  }
}

// ─── Bottom controls ──────────────────────────────────────────────────────────
class _BottomControls extends StatelessWidget {
  final LessonEngine engine;
  const _BottomControls({required this.engine});

  @override
  Widget build(BuildContext context) {
    final canAdvance = engine.canAdvance;
    final isFirst = engine.currentIndex == 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Row(
        children: [
          if (!isFirst) ...[
            _BackButton(onTap: engine.goBack),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: ElevatedButton(
                onPressed: canAdvance ? engine.advance : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canAdvance
                      ? const Color(0xFF12A28C)
                      : Colors.white.withValues(alpha: 0.06),
                  foregroundColor: canAdvance ? Colors.white : Colors.white30,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                  disabledBackgroundColor:
                      Colors.white.withValues(alpha: 0.06),
                  disabledForegroundColor: Colors.white30,
                ),
                child: Text(
                  engine.isLastStep ? 'Finish' : 'Continue',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: const Icon(Icons.arrow_back, color: Colors.white54, size: 20),
      ),
    );
  }
}
