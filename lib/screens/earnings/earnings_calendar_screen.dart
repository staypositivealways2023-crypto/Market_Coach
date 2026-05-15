import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/firestore_constants.dart';
import '../../models/stock_summary.dart';
import '../../services/backend_service.dart';
import '../../widgets/glass_card.dart';
import '../../features/chart/screens/asset_chart_screen.dart';

// ── Theme constants ───────────────────────────────────────────────────────────
const _bg = Color(0xFF0D131A);
const _cardBg = Color(0xFF111925);
const _accent = Color(0xFF12A28C);
const _textDim = Color(0xFF8A9BB5);

Widget _spacedGlassCard({
  required EdgeInsetsGeometry margin,
  EdgeInsetsGeometry? padding,
  required Widget child,
}) {
  return Padding(
    padding: margin,
    child: GlassCard(padding: padding, child: child),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// EARNINGS CALENDAR SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class EarningsCalendarScreen extends StatefulWidget {
  const EarningsCalendarScreen({super.key});

  @override
  State<EarningsCalendarScreen> createState() => _EarningsCalendarScreenState();
}

class _EarningsCalendarScreenState extends State<EarningsCalendarScreen> {
  final _backend = BackendService();

  int _daysAhead = 30;
  List<Map<String, dynamic>> _groups = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _backend.getEarningsCalendar(daysAhead: _daysAhead);
      if (data != null && mounted) {
        setState(() {
          _groups = (data['groups'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>();
          _loading = false;
        });
      } else if (mounted) {
        setState(() {
          _loading = false;
          _error = 'No earnings data available.';
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = 'Failed to load calendar.';
        });
    }
  }

  // ── Date formatting ────────────────────────────────────────────────────────
  String _fmtDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final wd = days[d.weekday - 1];
      return '$wd ${months[d.month - 1]} ${d.day}';
    } catch (_) {
      return iso;
    }
  }

  bool _isToday(String iso) {
    final today = DateTime.now();
    try {
      final d = DateTime.parse(iso);
      return d.year == today.year &&
          d.month == today.month &&
          d.day == today.day;
    } catch (_) {
      return false;
    }
  }

  bool _isTomorrow(String iso) {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    try {
      final d = DateTime.parse(iso);
      return d.year == tomorrow.year &&
          d.month == tomorrow.month &&
          d.day == tomorrow.day;
    } catch (_) {
      return false;
    }
  }

  String _dayLabel(String iso) {
    if (_isToday(iso)) return '  TODAY';
    if (_isTomorrow(iso)) return '  TOMORROW';
    return '';
  }

  // ── Navigate to detail + prediction ───────────────────────────────────────
  void _openPrediction(Map<String, dynamic> event) {
    final sym = event['symbol'] as String? ?? '';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _EarningsPredictionScreen(symbol: sym, event: event),
      ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _daysFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [7, 14, 30, 60].map((d) {
          final active = _daysAhead == d;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() => _daysAhead = d);
                _load();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: active ? _accent.withOpacity(0.18) : _cardBg,
                  border: Border.all(color: active ? _accent : Colors.white12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$d days',
                  style: TextStyle(
                    color: active ? _accent : _textDim,
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _dateHeader(String dateIso) {
    final label = _fmtDate(dateIso);
    final dayLabel = _dayLabel(dateIso);
    final isToday = _isToday(dateIso);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: isToday ? _accent : Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          if (dayLabel.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                dayLabel.trim(),
                style: const TextStyle(
                  color: _accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const Spacer(),
          const Icon(
            Icons.chevron_right_rounded,
            color: Colors.white24,
            size: 16,
          ),
        ],
      ),
    );
  }

  Widget _eventTile(Map<String, dynamic> event) {
    final sym = event['symbol'] as String? ?? '';
    final epsEst = event['eps_estimate'] as num?;
    final revEst = event['revenue_estimate'] as num?;

    String _fmtRev(num? v) {
      if (v == null) return '-';
      if (v >= 1e9) return '\$${(v / 1e9).toStringAsFixed(1)}B';
      if (v >= 1e6) return '\$${(v / 1e6).toStringAsFixed(1)}M';
      return '\$${v.toStringAsFixed(0)}';
    }

    return GestureDetector(
      onTap: () => _openPrediction(event),
      child: _spacedGlassCard(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Symbol avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _accent.withOpacity(0.3)),
              ),
              child: Center(
                child: Text(
                  sym.length > 4 ? sym.substring(0, 4) : sym,
                  style: const TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Symbol + estimates
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sym,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        'EPS est: ${epsEst != null ? epsEst.toStringAsFixed(2) : "-"}',
                        style: const TextStyle(color: _textDim, fontSize: 11),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Rev est: ${_fmtRev(revEst)}',
                        style: const TextStyle(color: _textDim, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // AI prediction chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _accent.withOpacity(0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 12, color: _accent),
                  SizedBox(width: 4),
                  Text(
                    'AI View',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Earnings Calendar',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        children: [
          _daysFilter(),
          const Divider(color: Colors.white10, height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _accent))
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_off_rounded,
                            size: 40,
                            color: _textDim.withOpacity(0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _textDim,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : _groups.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.event_busy_rounded,
                          size: 48,
                          color: _textDim.withOpacity(0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No earnings returned for the next $_daysAhead days.',
                          style: const TextStyle(color: _textDim, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 28),
                          child: Text(
                            'This screen uses the backend earnings calendar provider. An empty result can mean there are no dates in this tracked universe, or the provider did not return calendar data.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF5A6880),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 120),
                    itemCount: _groups.length,
                    itemBuilder: (ctx, gi) {
                      final group = _groups[gi];
                      final dateIso = group['date'] as String? ?? '';
                      final events = (group['events'] as List<dynamic>? ?? [])
                          .cast<Map<String, dynamic>>();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _dateHeader(dateIso),
                          ...events.map(_eventTile),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AI PRE-EARNINGS PREDICTION SCREEN  (pushed from calendar tile tap)
// ─────────────────────────────────────────────────────────────────────────────
class _EarningsPredictionScreen extends StatefulWidget {
  final String symbol;
  final Map<String, dynamic> event;

  const _EarningsPredictionScreen({required this.symbol, required this.event});

  @override
  State<_EarningsPredictionScreen> createState() =>
      _EarningsPredictionScreenState();
}

class _EarningsPredictionScreenState extends State<_EarningsPredictionScreen> {
  final _backend = BackendService();

  Map<String, dynamic>? _prediction;
  Map<String, dynamic>? _postAnalysis;
  bool _loadingPre = false;
  bool _loadingPost = false;
  bool _savingAlert = false;
  String? _preError;

  @override
  void initState() {
    super.initState();
    _loadPrediction();
    _loadPostAnalysis();
  }

  Future<void> _loadPrediction() async {
    setState(() {
      _loadingPre = true;
      _preError = null;
    });
    try {
      final data = await _backend.getPreEarningsPrediction(widget.symbol);
      if (mounted)
        setState(() {
          _prediction = data;
          _loadingPre = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _loadingPre = false;
          _preError = 'Failed to load prediction.';
        });
    }
  }

  Future<void> _loadPostAnalysis() async {
    setState(() {
      _loadingPost = true;
    });
    try {
      final data = await _backend.getPostEarningsAnalysis(widget.symbol);
      if (mounted)
        setState(() {
          _postAnalysis = data;
          _loadingPost = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _loadingPost = false;
        });
    }
  }

  Color _verdictColor(String? v) {
    switch (v) {
      case 'BULLISH':
        return const Color(0xFF26C96F);
      case 'BEARISH':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFFFFB547);
    }
  }

  IconData _verdictIcon(String? v) {
    switch (v) {
      case 'BULLISH':
        return Icons.trending_up_rounded;
      case 'BEARISH':
        return Icons.trending_down_rounded;
      default:
        return Icons.trending_flat_rounded;
    }
  }

  void _openChart() {
    final isCrypto = false; // calendar only has stocks
    final stock = StockSummary(
      ticker: widget.symbol,
      name: widget.symbol,
      price: 0.0,
      changePercent: 0.0,
      isCrypto: isCrypto,
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AssetChartScreen(stock: stock)),
    );
  }

  Future<void> _saveEarningsAlert() async {
    if (_savingAlert) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      _showSnack('Sign in to save earnings alerts.');
      return;
    }

    final earningsDate =
        (widget.event['earnings_date'] as String?) ??
        (_prediction?['earnings_date'] as String?) ??
        '';
    if (earningsDate.isEmpty) {
      _showSnack('Earnings date is not available yet.');
      return;
    }

    setState(() => _savingAlert = true);
    try {
      await FirebaseFirestore.instance
          .collection(FirestoreConstants.users)
          .doc(user.uid)
          .collection(FirestoreConstants.alerts)
          .add({
            'symbol': widget.symbol.toUpperCase(),
            'earnings_date': earningsDate,
            'type': 'earnings',
            'created_at': FieldValue.serverTimestamp(),
            'enabled': true,
          });
      if (mounted) _showSnack('Earnings alert saved.');
    } catch (_) {
      if (mounted) _showSnack('Could not save earnings alert.');
    } finally {
      if (mounted) setState(() => _savingAlert = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
    child: Text(
      title,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 12,
        letterSpacing: 1.1,
      ),
    ),
  );

  Widget _predictionCard() {
    if (_loadingPre) {
      return _spacedGlassCard(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(24),
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
            ),
            SizedBox(width: 12),
            Text(
              'Generating AI prediction...',
              style: TextStyle(color: _textDim, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_prediction == null) {
      return _spacedGlassCard(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(16),
        child: Text(
          _preError ?? 'Prediction unavailable.',
          style: const TextStyle(color: _textDim, fontSize: 13),
        ),
      );
    }

    final verdict = _prediction!['verdict'] as String? ?? 'NEUTRAL';
    final rationale = _prediction!['rationale'] as String? ?? '';
    final epsEst = _prediction!['eps_estimate'] as num?;
    final earnDate = _prediction!['earnings_date'] as String? ?? '-';

    return _spacedGlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Verdict badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _verdictColor(verdict).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _verdictColor(verdict).withOpacity(0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _verdictIcon(verdict),
                      color: _verdictColor(verdict),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      verdict,
                      style: TextStyle(
                        color: _verdictColor(verdict),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Icon(Icons.auto_awesome, size: 14, color: _accent),
              const SizedBox(width: 4),
              const Text(
                'AI Prediction',
                style: TextStyle(color: _accent, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Rationale
          Text(
            rationale,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 12),
          // Meta row
          Row(
            children: [
              _metaChip(Icons.calendar_today_rounded, 'Reports $earnDate'),
              const SizedBox(width: 8),
              if (epsEst != null)
                _metaChip(
                  Icons.bar_chart_rounded,
                  'EPS est \$${epsEst.toStringAsFixed(2)}',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _postAnalysisCard() {
    if (_loadingPost) {
      return _spacedGlassCard(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(18),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
            ),
            SizedBox(width: 12),
            Text(
              'Checking for earnings results...',
              style: TextStyle(color: _textDim, fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (_postAnalysis == null) {
      return _spacedGlassCard(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(14),
        child: const Text(
          'Post-earnings analysis will appear here once results are reported.',
          style: TextStyle(color: _textDim, fontSize: 12, height: 1.5),
        ),
      );
    }

    final actual = _postAnalysis!['eps_actual'] as num?;
    final estimate = _postAnalysis!['eps_estimate'] as num?;
    final surprPct = _postAnalysis!['surprise_pct'] as num?;
    final beatMiss = _postAnalysis!['beat_miss'] as String? ?? '';
    final analysis = _postAnalysis!['analysis'] as String? ?? '';
    final period = _postAnalysis!['period'] as String? ?? '';

    final isBeat = beatMiss == 'BEAT';
    final clr = isBeat ? const Color(0xFF26C96F) : const Color(0xFFEF4444);

    return _spacedGlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: clr.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: clr.withOpacity(0.5)),
                ),
                child: Text(
                  beatMiss,
                  style: TextStyle(
                    color: clr,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                period,
                style: const TextStyle(color: _textDim, fontSize: 12),
              ),
              const Spacer(),
              if (surprPct != null)
                Text(
                  '${surprPct >= 0 ? '+' : ''}${surprPct.toStringAsFixed(1)}% surprise',
                  style: TextStyle(
                    color: clr,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // EPS row
          Row(
            children: [
              _metaChip(
                Icons.check_circle_outline,
                'Actual \$${actual?.toStringAsFixed(2) ?? "-"}',
              ),
              const SizedBox(width: 8),
              _metaChip(
                Icons.radio_button_unchecked,
                'Est \$${estimate?.toStringAsFixed(2) ?? "-"}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            analysis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: _textDim),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: _textDim, fontSize: 11)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.symbol,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: _savingAlert
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _accent,
                    ),
                  )
                : const Icon(
                    Icons.notifications_active_outlined,
                    color: _accent,
                  ),
            tooltip: 'Save Earnings Alert',
            onPressed: _savingAlert ? null : _saveEarningsAlert,
          ),
          IconButton(
            icon: const Icon(Icons.candlestick_chart_outlined, color: _accent),
            tooltip: 'View Chart',
            onPressed: _openChart,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('PRE-EARNINGS AI PREDICTION'),
            _predictionCard(),
            _sectionHeader('POST-EARNINGS ANALYSIS'),
            _postAnalysisCard(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
