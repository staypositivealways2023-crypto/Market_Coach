import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/lesson.dart';
import '../../models/lesson_progress.dart';
import '../../providers/lesson_progress_provider.dart';
import '../../providers/bookmarks_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../lesson_detail/lesson_detail_screen.dart';
import '../../providers/guided_lesson_provider.dart';

import 'learn_constants.dart';
import 'learn_header.dart';
import 'lesson_level_tabs.dart';
import 'featured_lesson_carousel.dart';
import 'ai_coach_banner.dart';
import 'lesson_search_filter_bar.dart';
import 'lesson_list_card.dart';

// Re-export enums so other files that previously imported from here still work.
export 'learn_constants.dart'
    show ProgressFilter, LevelFilter, levelOrder, kLearnAccent;

class LearnScreen extends ConsumerStatefulWidget {
  const LearnScreen({super.key});

  @override
  ConsumerState<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends ConsumerState<LearnScreen> {
  ProgressFilter _progressFilter = ProgressFilter.all;
  LevelFilter _levelFilter = LevelFilter.beginner;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final allProgressAsync = ref.watch(allProgressProvider);
    final bookmarksAsync = ref.watch(bookmarksProvider);
    final connectivityAsync = ref.watch(connectivityProvider);
    final totalXp = ref.watch(guidedTotalXpProvider);

    return Scaffold(
      backgroundColor: kLearnBg,
      body: Column(
        children: [
          // ── Offline banner ─────────────────────────────────────────────
          connectivityAsync.maybeWhen(
            data: (isConnected) =>
                isConnected ? const SizedBox.shrink() : const _OfflineBanner(),
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: SafeArea(
              top: true,
              bottom: false,
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('lessons')
                    .orderBy('published_at', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  // ── Static top slivers (always present) ──────────────
                  final slivers = <Widget>[
                    SliverToBoxAdapter(
                      child: LearnHeader(totalXp: totalXp),
                    ),
                    SliverToBoxAdapter(
                      child: LessonLevelTabs(
                        selected: _levelFilter,
                        onChanged: (lf) =>
                            setState(() => _levelFilter = lf),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: FeaturedLessonCarousel(
                        selectedLevel: _levelFilter,
                      ),
                    ),
                    const SliverToBoxAdapter(child: AiCoachBanner()),
                    SliverToBoxAdapter(
                      child: LessonSearchFilterBar(
                        searchQuery: _searchQuery,
                        progressFilter: _progressFilter,
                        onSearchChanged: (q) =>
                            setState(() => _searchQuery = q),
                        onFilterChanged: (f) =>
                            setState(() => _progressFilter = f),
                      ),
                    ),
                    // ── Section heading ─────────────────────────────────
                    SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(20, 20, 20, 10),
                        child: Text(
                          _sectionTitle,
                          style: const TextStyle(
                            color: kLearnTextPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ),
                  ];

                  // ── Dynamic lesson content slivers ────────────────────
                  if (snapshot.hasError) {
                    slivers.add(_errorSliver(snapshot.error.toString()));
                  } else if (snapshot.connectionState ==
                      ConnectionState.waiting) {
                    slivers.add(_loadingSliver());
                  } else if (!snapshot.hasData ||
                      snapshot.data!.docs.isEmpty) {
                    slivers.add(_emptySliver(
                      'No lessons yet',
                      'Check back soon for new content!',
                      Icons.school_outlined,
                    ));
                  } else {
                    final lessons = _parseLessons(snapshot.data!.docs);
                    final filtered = allProgressAsync.maybeWhen(
                      data: (progresses) => bookmarksAsync.maybeWhen(
                        data: (bookmarks) =>
                            _filterLessons(lessons, progresses, bookmarks),
                        orElse: () =>
                            _filterLessons(lessons, progresses, []),
                      ),
                      orElse: () => _filterLessons(lessons, [], []),
                    );

                    if (filtered.isEmpty) {
                      slivers.add(_emptySliver(
                        'No matches',
                        'Try a different filter',
                        Icons.filter_list_off,
                      ));
                    } else {
                      slivers.add(
                        SliverPadding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList.builder(
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) {
                              final lesson = filtered[i];
                              final progress = allProgressAsync.valueOrNull
                                  ?.cast<LessonProgress?>()
                                  .firstWhere(
                                    (p) => p?.lessonId == lesson.id,
                                    orElse: () => null,
                                  );
                              return Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 10),
                                child: LessonListCard(
                                  lesson: lesson,
                                  progress: progress,
                                  onTap: () =>
                                      Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => LessonDetailScreen(
                                          lessonId: lesson.id),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    }
                  }

                  slivers.add(
                      const SliverToBoxAdapter(child: SizedBox(height: 32)));

                  return CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: slivers,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String get _sectionTitle => switch (_levelFilter) {
        LevelFilter.beginner => 'Beginner Lessons',
        LevelFilter.intermediate => 'Intermediate Lessons',
        LevelFilter.advanced => 'Advanced Lessons',
        LevelFilter.all => 'All Lessons',
      };

  List<Lesson> _parseLessons(List<QueryDocumentSnapshot> docs) {
    final lessons = docs
        .map((doc) =>
            Lesson.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
    lessons.sort((a, b) {
      final aL = levelOrder[a.level.toLowerCase()] ?? 999;
      final bL = levelOrder[b.level.toLowerCase()] ?? 999;
      if (aL != bL) return aL.compareTo(bL);
      if (a.publishedAt != null && b.publishedAt != null) {
        return b.publishedAt!.compareTo(a.publishedAt!);
      }
      return 0;
    });
    return lessons;
  }

  List<Lesson> _filterLessons(
    List<Lesson> lessons,
    List<LessonProgress> progresses,
    List<String> bookmarks,
  ) {
    final filtered = lessons.where((lesson) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!lesson.title.toLowerCase().contains(q) &&
            !lesson.subtitle.toLowerCase().contains(q)) {
          return false;
        }
      }
      if (_levelFilter != LevelFilter.all) {
        final match = switch (_levelFilter) {
          LevelFilter.beginner =>
            lesson.level.toLowerCase() == 'beginner',
          LevelFilter.intermediate =>
            lesson.level.toLowerCase() == 'intermediate',
          LevelFilter.advanced =>
            lesson.level.toLowerCase() == 'advanced',
          LevelFilter.all => true,
        };
        if (!match) return false;
      }
      if (_progressFilter != ProgressFilter.all) {
        final progress = progresses
            .cast<LessonProgress?>()
            .firstWhere((p) => p?.lessonId == lesson.id,
                orElse: () => null);
        final match = switch (_progressFilter) {
          ProgressFilter.bookmarked => bookmarks.contains(lesson.id),
          ProgressFilter.completed => progress?.completed == true,
          ProgressFilter.inProgress => progress?.isInProgress == true,
          ProgressFilter.notStarted =>
            progress == null || progress.isNotStarted,
          ProgressFilter.all => true,
        };
        if (!match) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      final aO = levelOrder[a.level.toLowerCase()] ?? 999;
      final bO = levelOrder[b.level.toLowerCase()] ?? 999;
      if (aO != bO) return aO.compareTo(bO);
      if (a.publishedAt != null && b.publishedAt != null) {
        return b.publishedAt!.compareTo(a.publishedAt!);
      }
      return a.title.compareTo(b.title);
    });
    return filtered;
  }

  // ── Inline state widgets ──────────────────────────────────────────────────

  Widget _errorSliver(String error) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline,
                    color: Colors.red.shade300, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Error loading lessons',
                    style: TextStyle(
                        color: Colors.red.shade300, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _loadingSliver() => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: CircularProgressIndicator(
              color: kLearnAccent,
              strokeWidth: 2,
            ),
          ),
        ),
      );

  Widget _emptySliver(String title, String subtitle, IconData icon) =>
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
            decoration: BoxDecoration(
              color: kLearnSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kLearnBorder),
            ),
            child: Column(
              children: [
                Icon(icon,
                    size: 32,
                    color: kLearnTextSecondary.withValues(alpha: 0.45)),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    color: kLearnTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                      color: kLearnTextSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
}

// ─── Offline banner ────────────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF92400E),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.cloud_off, size: 13, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Offline — showing cached lessons',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
