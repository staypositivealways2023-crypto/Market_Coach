import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
import '../providers/firebase_provider.dart';

/// Investor IQ Score — composite 0–1000
/// - Lesson completions  30% (max 300)
/// - Quiz accuracy       25% (max 250)
/// - Paper trade wins    30% (max 300)
/// - AI engagement       15% (max 150)
final iqScoreProvider = FutureProvider<IQScoreData>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const IQScoreData.zero();

  final db = ref.watch(firebaseProvider);
  final uid = user.uid;

  // ── 1. Lesson completions (guided_progress collection) ───────────────────
  final progressSnap = await db
      .collection('users')
      .doc(uid)
      .collection('guided_progress')
      .get();
  final completedLessons = progressSnap.docs
      .where((d) => d.data()['completed'] == true)
      .length
      .clamp(0, 20);
  final lessonPts = (completedLessons / 20) * 300;

  // ── 2. Quiz accuracy ─────────────────────────────────────────────────────
  final userSnap = await db.collection('users').doc(uid).get();
  final userData = userSnap.data() ?? {};
  final quizTotal = (userData['quiz_total_count'] as int?) ?? 0;
  final quizCorrect = (userData['quiz_correct_count'] as int?) ?? 0;
  final quizAccuracy = quizTotal > 0 ? quizCorrect / quizTotal : 0.0;
  final quizPts = quizAccuracy * 250;

  // ── 3. Paper trade win rate ───────────────────────────────────────────────
  final txSnap = await db
      .collection('users')
      .doc(uid)
      .collection('paper_transactions')
      .where('type', isEqualTo: 'SELL')
      .get();
  final sells = txSnap.docs;
  final winCount = sells
      .where((d) {
        final pnl = (d.data()['pnl'] as num?)?.toDouble() ??
            (d.data()['after_tax_pnl'] as num?)?.toDouble() ??
            0.0;
        return pnl > 0;
      })
      .length;
  final winRate = sells.isEmpty ? 0.0 : winCount / sells.length;
  final tradePts = winRate * 300;

  // ── 4. AI engagement (chat sessions in shared_preferences) ───────────────
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('chat_sessions_v1');
  int sessionCount = 0;
  if (raw != null) {
    try {
      final list = (raw.isNotEmpty &&
              raw.startsWith('['))
          ? (raw.length > 2 ? raw.split('},{').length : 0)
          : 0;
      sessionCount = list.clamp(0, 20);
    } catch (_) {
      sessionCount = 0;
    }
  }
  final aiPts = (sessionCount / 20) * 150;

  final total = (lessonPts + quizPts + tradePts + aiPts).round().clamp(0, 1000);

  return IQScoreData(
    total: total,
    lessonPts: lessonPts.round(),
    quizPts: quizPts.round(),
    tradePts: tradePts.round(),
    aiPts: aiPts.round(),
    completedLessons: completedLessons,
    quizAccuracy: quizAccuracy,
    winRate: winRate,
    sessionCount: sessionCount,
  );
});

class IQScoreData {
  final int total;
  final int lessonPts;
  final int quizPts;
  final int tradePts;
  final int aiPts;
  final int completedLessons;
  final double quizAccuracy;
  final double winRate;
  final int sessionCount;

  const IQScoreData({
    required this.total,
    required this.lessonPts,
    required this.quizPts,
    required this.tradePts,
    required this.aiPts,
    required this.completedLessons,
    required this.quizAccuracy,
    required this.winRate,
    required this.sessionCount,
  });

  const IQScoreData.zero()
      : total = 0,
        lessonPts = 0,
        quizPts = 0,
        tradePts = 0,
        aiPts = 0,
        completedLessons = 0,
        quizAccuracy = 0,
        winRate = 0,
        sessionCount = 0;
}
