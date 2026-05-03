import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/lesson.dart';
import '../../models/lesson_screen.dart';
import '../../providers/lesson_provider.dart';
import '../../providers/lesson_progress_provider.dart';
import '../../providers/bookmarks_provider.dart';
import '../../providers/firestore_service_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/lesson_screen_widget.dart';

class LessonDetailScreen extends ConsumerStatefulWidget {
  const LessonDetailScreen({
    super.key,
    required this.lessonId,
  });

  final String lessonId;

  @override
  ConsumerState<LessonDetailScreen> createState() => _LessonDetailScreenState();
}

class _LessonDetailScreenState extends ConsumerState<LessonDetailScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  final Map<int, bool> _quizAnswers = {}; // Track quiz correctness by screen index
  final Map<int, bool> _quizMultiPassed = {}; // Track quiz_multi pass status by screen index
  DateTime? _lessonStartTime;

  @override
  void initState() {
    super.initState();
    _lessonStartTime = DateTime.now();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void recordQuizAnswer(int screenIndex, bool isCorrect) {
    setState(() {
      _quizAnswers[screenIndex] = isCorrect;
    });
  }

  Future<void> _nextPage(int totalScreens, Lesson currentLesson, List<LessonScreen> screens) async {
    // Check if current screen is quiz_multi and not passed
    final currentScreen = screens[_currentPage];
    if (currentScreen.type == 'quiz_multi' && _quizMultiPassed[_currentPage] != true) {
      // Show message that quiz must be passed
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please answer all quiz questions correctly to continue'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_currentPage < totalScreens - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // Mark as complete when leaving last screen
      await _markComplete();

      // Calculate quiz performance
      int? quizScore;
      int? correctAnswers;
      int? totalQuestions;

      if (_quizAnswers.isNotEmpty) {
        correctAnswers = _quizAnswers.values.where((correct) => correct).length;
        totalQuestions = _quizAnswers.length;
        quizScore = totalQuestions > 0
            ? ((correctAnswers / totalQuestions) * 100).round()
            : null;
      }

      // Calculate time spent
      final timeSpent = _lessonStartTime != null
          ? DateTime.now().difference(_lessonStartTime!)
          : null;


      if (mounted) {
        // Show completion dialog
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('🎉 Lesson Complete!'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Congratulations on completing "${currentLesson.title}"!'),
                if (quizScore != null && totalQuestions != null && totalQuestions > 0) ...[
                  const SizedBox(height: 16),
                  Text('Quiz Score: ${(quizScore * 100).toStringAsFixed(0)}%'),
                  Text('Correct Answers: $correctAnswers/$totalQuestions'),
                ],
                if (timeSpent != null) ...[
                  const SizedBox(height: 8),
                  Text('Time Spent: ${timeSpent.inMinutes} minutes'),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop(); // Go back to learn screen
                },
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _updateProgress(int screen, int total) async {
    try {
      final userId = ref.read(userIdProvider);
      final service = ref.read(firestoreServiceProvider);
      await service.updateLessonProgress(
        userId: userId,
        lessonId: widget.lessonId,
        currentScreen: screen,
        totalScreens: total,
        completed: screen == total - 1,
      );
    } catch (e) {
      // Silent fail - progress tracking shouldn't block UX
      debugPrint('Failed to update progress: $e');
    }
  }

  Future<void> _markComplete() async {
    try {
      final userId = ref.read(userIdProvider);
      final service = ref.read(firestoreServiceProvider);
      await service.markLessonComplete(userId, widget.lessonId);
    } catch (e) {
      debugPrint('Failed to mark complete: $e');
    }
  }

  Future<void> _toggleBookmark(bool isCurrentlyBookmarked) async {
    try {
      final userId = ref.read(userIdProvider);
      final service = ref.read(firestoreServiceProvider);
      if (isCurrentlyBookmarked) {
        await service.unbookmarkLesson(userId, widget.lessonId);
      } else {
        await service.bookmarkLesson(userId, widget.lessonId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update bookmark: $e')),
        );
      }
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lessonAsync = ref.watch(lessonProvider(widget.lessonId));
    final progressAsync = ref.watch(lessonProgressProvider(widget.lessonId));
    final bookmarksAsync = ref.watch(bookmarksProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          lessonAsync.maybeWhen(
            data: (data) => data.lesson.title,
            orElse: () => 'Lesson',
          ),
        ),
        actions: [
          // Bookmark button
          bookmarksAsync.maybeWhen(
            data: (bookmarks) {
              final isBookmarked = bookmarks.contains(widget.lessonId);
              return IconButton(
                icon: Icon(
                  isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                  color: isBookmarked ? Colors.amber : null,
                ),
                onPressed: () => _toggleBookmark(isBookmarked),
                tooltip: isBookmarked ? 'Remove bookmark' : 'Bookmark lesson',
              );
            },
            orElse: () => const SizedBox(width: 48),
          ),
          // Show checkmark if lesson completed
          progressAsync.maybeWhen(
            data: (progress) {
              if (progress?.completed == true) {
                return const Padding(
                  padding: EdgeInsets.only(right: 8.0),
                  child: Icon(Icons.check_circle, color: Colors.green),
                );
              }
              return const SizedBox.shrink();
            },
            orElse: () => const SizedBox.shrink(),
          ),
          lessonAsync.maybeWhen(
            data: (data) => Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: Text(
                  '${_currentPage + 1}/${data.screens.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: lessonAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _buildError(error.toString()),
        data: (data) => _buildContent(data.screens),
      ),
      bottomNavigationBar: lessonAsync.maybeWhen(
        data: (data) => _buildBottomBar(
          data.screens.length,
          data.lesson,
          data.screens,
        ),
        orElse: () => null,
      ),
    );
  }

  Widget _buildError(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64),
          const SizedBox(height: 16),
          Text(error),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => ref.invalidate(lessonProvider(widget.lessonId)),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(List<LessonScreen> screens) {
    // Sort screens: non-quiz first, then quiz at end
    final sortedScreens = _sortScreensWithQuizAtEnd(screens);

    return Column(
      children: [
        LinearProgressIndicator(
          value: (_currentPage + 1) / sortedScreens.length,
        ),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
              // Update progress when page changes
              _updateProgress(index, sortedScreens.length);
            },
            itemCount: sortedScreens.length,
            itemBuilder: (context, index) {
              return LessonScreenWidget(
                screen: sortedScreens[index],
                onQuizAnswered: (isCorrect) {
                  recordQuizAnswer(index, isCorrect);
                },
                onQuizPassed: () {
                  setState(() {
                    _quizMultiPassed[index] = true;
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }

  List<LessonScreen> _sortScreensWithQuizAtEnd(List<LessonScreen> screens) {
    // Separate quiz and non-quiz screens
    final nonQuizScreens = screens
        .where((screen) => screen.type != 'quiz_single')
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    final quizScreens = screens
        .where((screen) => screen.type == 'quiz_single')
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    // Return non-quiz screens first, then quiz screens
    return [...nonQuizScreens, ...quizScreens];
  }

  Widget _buildBottomBar(int screensLength, Lesson lesson, List<LessonScreen> screens) {
    final isFirstPage = _currentPage == 0;
    final isLastPage = _currentPage == screensLength - 1;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            if (!isFirstPage)
              Expanded(
                child: OutlinedButton(
                  onPressed: _previousPage,
                  child: const Text('Previous'),
                ),
              ),
            if (!isFirstPage && !isLastPage) const SizedBox(width: 16),
            Expanded(
              child: FilledButton(
                onPressed: () => _nextPage(screensLength, lesson, screens),
                child: Text(isLastPage ? 'Complete Lesson' : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
