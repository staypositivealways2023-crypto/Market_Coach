import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/usage_analytics_provider.dart';
import '../../services/backend_service.dart';
import '../../services/usage_analytics_service.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/subscription_gate.dart';

// ── Theme ─────────────────────────────────────────────────────────────────────
const _bg = Color(0xFF0D131A);
const _accent = Color(0xFF12A28C);
const _textDim = Color(0xFF8A9BB5);

// ─────────────────────────────────────────────────────────────────────────────
// MACRO DASHBOARD SCREEN
// Phase 7: Fear/Greed (7.3) + Macro Regime (7.6) + Yield Curve (7.4) + Fed Calendar (7.5)
// ─────────────────────────────────────────────────────────────────────────────
class MacroDashboardScreen extends ConsumerStatefulWidget {
  const MacroDashboardScreen({super.key});

  @override
  ConsumerState<MacroDashboardScreen> createState() =>
      _MacroDashboardScreenState();
}

class _MacroDashboardScreenState extends ConsumerState<MacroDashboardScreen> {
  final _backend = BackendService();

  // Data state
  Map<String, dynamic>? _fearGreed;
  Map<String, dynamic>? _macroRegime;
  List<Map<String, dynamic>> _yieldHistory = [];
  List<Map<String, dynamic>> _econCalendar = [];

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    ref
        .read(usageAnalyticsProvider)
        ?.logFeatureUsed(UsageFeature.macroDashboard);
    try {
      final results = await Future.wait([
        _backend.getFearGreed(),
        _backend.getMacroRegime('SPY'),
        _backend.getMacroSeries('yield_curve', limit: 24),
        _backend.getEconomicCalendar(daysAhead: 21),
      ]);
      if (!mounted) return;
      setState(() {
        _fearGreed = results[0] as Map<String, dynamic>?;
        _macroRegime = results[1] as Map<String, dynamic>?;
        _yieldHistory = (results[2] as List<Map<String, dynamic>>?) ?? [];
        _econCalendar = (results[3] as List<Map<String, dynamic>>?) ?? [];
        _loading = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = 'Failed to load macro data.';
        });
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Color _fearGreedColor(double score) {
    if (score < 20) return const Color(0xFFEF4444); // Extreme Fear
    if (score < 40) return const Color(0xFFFF7043); // Fear
    if (score < 60) return const Color(0xFFFFB547); // Neutral
    if (score < 80) return const Color(0xFF66BB6A); // Greed
    return const Color(0xFF26C96F); // Extreme Greed
  }

  String _componentMeaning(String key) {
    switch (key) {
      case 'vix':
        return 'VIX tracks expected S&P 500 volatility. Higher VIX usually means more fear and wider daily moves.';
      case 'momentum_rsi':
        return 'Momentum RSI shows whether SPY is stretched up or down. Around 50 is balanced; high readings show stronger upside momentum.';
      case 'market_position':
        return 'Market Position compares SPY with its 52-week range. Near the highs often signals confidence; near the lows signals stress.';
      default:
        return 'This input contributes to the combined sentiment score.';
    }
  }

  Widget _infoText(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: _textDim, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: _textDim,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _regimeColor(String? regime) {
    if (regime == null) return _textDim;
    final r = regime.toUpperCase();
    if (r.contains('RISK_ON')) return const Color(0xFF26C96F);
    if (r.contains('RISK_OFF')) return const Color(0xFFEF4444);
    if (r.contains('STAGFLATION')) return const Color(0xFFFF7043);
    return const Color(0xFFFFB547);
  }

  IconData _regimeIcon(String? regime) {
    if (regime == null) return Icons.help_outline_rounded;
    final r = regime.toUpperCase();
    if (r.contains('RISK_ON')) return Icons.trending_up_rounded;
    if (r.contains('RISK_OFF')) return Icons.trending_down_rounded;
    if (r.contains('STAGFLATION')) return Icons.warning_amber_rounded;
    return Icons.trending_flat_rounded;
  }

  // ── Fear & Greed Widget (7.3) ──────────────────────────────────────────────

  Widget _fearGreedCard() {
    if (_fearGreed == null) {
      return _loading
          ? _loadingCard('Loading Fear & Greed...')
          : _unavailableCard('Fear & Greed');
    }

    final score = (_fearGreed!['score'] as num?)?.toDouble() ?? 50.0;
    final label = _fearGreed!['label'] as String? ?? 'Neutral';
    final components = _fearGreed!['components'] as Map<String, dynamic>? ?? {};
    final color = _fearGreedColor(score);

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_rounded, color: _accent, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Fear & Greed Index',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withOpacity(0.5)),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              width: 260,
              height: 156,
              child: CustomPaint(
                painter: _ArcGaugePainter(score: score),
                child: Align(
                  alignment: const Alignment(0, 0.40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        score.toStringAsFixed(0),
                        style: TextStyle(
                          color: color,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        '/ 100',
                        style: TextStyle(color: _textDim, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 10,
            runSpacing: 4,
            children: [
              Text(
                'Extreme Fear',
                style: TextStyle(color: Color(0xFFEF4444), fontSize: 10),
              ),
              Text(
                'Fear',
                style: TextStyle(color: Color(0xFFFF7043), fontSize: 10),
              ),
              Text(
                'Neutral',
                style: TextStyle(color: Color(0xFFFFB547), fontSize: 10),
              ),
              Text(
                'Greed',
                style: TextStyle(color: Color(0xFF66BB6A), fontSize: 10),
              ),
              Text(
                'Extreme Greed',
                style: TextStyle(color: Color(0xFF26C96F), fontSize: 10),
              ),
            ],
          ),
          _infoText(
            'Fear & Greed combines volatility, market momentum, and SPY position into a 0-100 sentiment score. Low scores mean defensive markets; high scores mean risk appetite.',
          ),
          const SizedBox(height: 16),
          // Component breakdown
          if (components.isNotEmpty) ...[
            const Divider(color: Colors.white12),
            const SizedBox(height: 10),
            ...components.entries.map((e) {
              final comp = e.value as Map<String, dynamic>;
              final compScore = (comp['score'] as num?)?.toDouble() ?? 50.0;
              final compColor = _fearGreedColor(compScore);
              final compLabel = e.key.replaceAll('_', ' ').toUpperCase();
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Tooltip(
                      message: _componentMeaning(e.key),
                      child: Text(
                        compLabel,
                        style: const TextStyle(color: _textDim, fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: compScore / 100,
                          backgroundColor: Colors.white10,
                          valueColor: AlwaysStoppedAnimation<Color>(compColor),
                          minHeight: 4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${compScore.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: compColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }),
            _infoText(
              'VIX, Momentum RSI, and Market Position are inputs, not trade signals by themselves. Use them to understand the market backdrop before reading individual charts.',
            ),
          ],
        ],
      ),
    );
  }

  // ── Macro Regime Widget (7.6) ──────────────────────────────────────────────

  Widget _macroRegimeCard() {
    if (_macroRegime == null) {
      return _loading
          ? _loadingCard('Classifying macro regime...')
          : _unavailableCard('Macro Regime');
    }

    final regime =
        _macroRegime!['regime'] as String? ??
        _macroRegime!['macro_regime'] as String? ??
        'UNKNOWN';
    final regColor = _regimeColor(regime);
    final regIcon = _regimeIcon(regime);
    final driftAdj = (_macroRegime!['drift_adj'] as num?)?.toDouble();
    final volAdj = (_macroRegime!['vol_adj'] as num?)?.toDouble();
    final rationale =
        _macroRegime!['rationale'] as String? ??
        _macroRegime!['summary'] as String?;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.language_rounded, color: _accent, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Macro Regime',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: regColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: regColor.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(regIcon, color: regColor, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      regime.replaceAll('_', ' '),
                      style: TextStyle(
                        color: regColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (driftAdj != null || volAdj != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (driftAdj != null)
                  Expanded(
                    child: _regimeStat(
                      'Drift Adj.',
                      '${driftAdj.toStringAsFixed(2)}×',
                      tooltip:
                          'Monte Carlo drift multiplier. 1.00× = neutral; >1.00 = regime boosts expected returns.',
                    ),
                  ),
                if (volAdj != null)
                  Expanded(
                    child: _regimeStat(
                      'Vol Adj.',
                      '${volAdj.toStringAsFixed(2)}×',
                      tooltip:
                          'Volatility scaling factor applied to simulated price paths. >1.00 = higher modelled risk.',
                    ),
                  ),
              ],
            ),
          ],
          if (rationale != null && rationale.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(color: Colors.white12),
            const SizedBox(height: 10),
            Text(
              rationale,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
          _infoText(
            'Macro Regime summarizes whether the broad environment is risk-on, risk-off, neutral, or stressed. It matters because the same stock setup behaves differently when rates, inflation, and growth are supportive or hostile.',
          ),
        ],
      ),
    );
  }

  Widget _regimeStat(String label, String value, {String? tooltip}) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(color: _textDim, fontSize: 11)),
            if (tooltip != null) ...[
              const SizedBox(width: 3),
              const Icon(Icons.info_outline_rounded, color: _textDim, size: 11),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
    if (tooltip != null) {
      return Tooltip(
        message: tooltip,
        textStyle: const TextStyle(color: Colors.white, fontSize: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF1C2940),
          borderRadius: BorderRadius.circular(6),
        ),
        child: content,
      );
    }
    return content;
  }

  // ── Yield Curve Widget (7.4) ───────────────────────────────────────────────

  Widget _yieldCurveCard() {
    if (_yieldHistory.isEmpty) {
      return _loading
          ? _loadingCard('Loading yield curve...')
          : _unavailableCard('Yield Curve');
    }

    // Most recent 12 points
    final recent = _yieldHistory.length > 12
        ? _yieldHistory.sublist(_yieldHistory.length - 12)
        : _yieldHistory;

    final values = recent
        .map((p) => (p['value'] as num?)?.toDouble())
        .whereType<double>()
        .toList();

    if (values.isEmpty) return const SizedBox.shrink();

    final latest = values.last;
    final isInverted = latest < 0;
    final barColor = isInverted
        ? const Color(0xFFEF4444)
        : const Color(0xFF26C96F);
    final maxAbs = values.map((v) => v.abs()).reduce(math.max);

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart_rounded, color: _accent, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Yield Curve (10Y–2Y)',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: barColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: barColor.withOpacity(0.5)),
                ),
                child: Text(
                  isInverted ? 'INVERTED' : 'NORMAL',
                  style: TextStyle(
                    color: barColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Spread: ${latest >= 0 ? "+" : ""}${latest.toStringAsFixed(2)}%',
            style: TextStyle(
              color: barColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '10-year minus 2-year Treasury yield',
            style: TextStyle(color: _textDim, fontSize: 11),
          ),
          _infoText(
            'The 10Y-2Y Spread is long-term Treasury yield minus short-term Treasury yield. A negative spread is an inverted yield curve, often read as a recession warning. A positive spread is usually healthier for growth expectations.',
          ),
          const SizedBox(height: 16),
          // Mini bar chart
          SizedBox(
            height: 60,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: values.map((v) {
                final norm = maxAbs > 0 ? v.abs() / maxAbs : 0.0;
                final h = (norm * 50).clamp(3.0, 50.0);
                final col = v < 0
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF26C96F);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (v >= 0) SizedBox(height: 50 - h),
                        Container(height: h, color: col.withOpacity(0.8)),
                        if (v < 0) SizedBox(height: 50 - h),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '12 months ago',
                style: TextStyle(color: _textDim, fontSize: 10),
              ),
              Text('Today', style: TextStyle(color: _textDim, fontSize: 10)),
            ],
          ),
          if (isInverted) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFEF4444).withOpacity(0.25),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFFEF4444),
                    size: 14,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'An inverted yield curve has historically preceded recessions.',
                      style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Economic / Fed Calendar Widget (7.5) ──────────────────────────────────

  Widget _econCalendarCard() {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.event_rounded, color: _accent, size: 18),
              SizedBox(width: 8),
              Text(
                'Fed & Economic Calendar',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_econCalendar.isEmpty)
            const Text(
              'No upcoming high-impact events.',
              style: TextStyle(color: _textDim, fontSize: 13),
            )
          else
            ..._econCalendar.take(8).map(_econEventTile),
        ],
      ),
    );
  }

  Widget _econEventTile(Map<String, dynamic> event) {
    final date = event['date'] as String? ?? '';
    final name = event['event'] as String? ?? '';
    final impact = event['impact'] as String? ?? 'low';
    final forecast = event['forecast'] as String?;
    final previous = event['previous'] as String?;
    final actual = event['actual'] as String?;

    Color impactColor;
    switch (impact) {
      case 'high':
        impactColor = const Color(0xFFEF4444);
        break;
      case 'medium':
        impactColor = const Color(0xFFFFB547);
        break;
      default:
        impactColor = _textDim;
    }

    String _shortDate(String iso) {
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
        return '${months[d.month - 1]} ${d.day}';
      } catch (_) {
        return iso;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date column
          SizedBox(
            width: 40,
            child: Text(
              _shortDate(date),
              style: const TextStyle(color: _textDim, fontSize: 11),
            ),
          ),
          // Impact dot
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 8),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: impactColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
          // Event name + forecast/actual
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (actual != null)
                  Text(
                    'Actual: $actual  Prev: ${previous ?? "-"}',
                    style: const TextStyle(color: _textDim, fontSize: 10),
                  )
                else if (forecast != null)
                  Text(
                    'Forecast: $forecast  Prev: ${previous ?? "-"}',
                    style: const TextStyle(color: _textDim, fontSize: 10),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  Widget _unavailableCard(String sectionName) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: _textDim, size: 16),
          const SizedBox(width: 10),
          Text(
            '$sectionName data temporarily unavailable',
            style: const TextStyle(color: _textDim, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _loadingCard(String message) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
          ),
          const SizedBox(width: 12),
          Text(message, style: const TextStyle(color: _textDim, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 11,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SubscriptionGateScreen(
      feature: 'Macro Dashboard',
      description:
          'Fear & Greed index, global macro regime, yield curve, and economic calendar.',
      child: Scaffold(
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
            'Macro Dashboard',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: _accent))
            : _error != null
            ? Center(
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFEF4444)),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                children: [
                  _sectionLabel('Market Sentiment'),
                  _fearGreedCard(),
                  _sectionLabel('Global Macro Regime'),
                  _macroRegimeCard(),
                  _sectionLabel('Yield Curve'),
                  _yieldCurveCard(),
                  _sectionLabel('Upcoming Events'),
                  _econCalendarCard(),
                ],
              ),
      ), // Scaffold
    ); // SubscriptionGateScreen
  }
}

// ── Arc Gauge CustomPainter ───────────────────────────────────────────────────

class _ArcGaugePainter extends CustomPainter {
  final double score; // 0-100

  const _ArcGaugePainter({required this.score});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.88;
    final r = size.width / 2 - 18;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    // Background arc (grey track)
    final trackPaint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, trackPaint);

    const segments = [
      Color(0xFFEF4444),
      Color(0xFFFF7043),
      Color(0xFFFFB547),
      Color(0xFF66BB6A),
      Color(0xFF26C96F),
    ];
    final segmentPaint = Paint()
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    const gap = 0.018;
    final segmentSweep = math.pi / segments.length;
    for (var i = 0; i < segments.length; i++) {
      segmentPaint.color = segments[i];
      canvas.drawArc(
        rect,
        math.pi + (i * segmentSweep) + gap,
        segmentSweep - (gap * 2),
        false,
        segmentPaint,
      );
    }

    final pct = (score / 100).clamp(0.0, 1.0);
    final needleAngle = math.pi + (math.pi * pct);
    final needleBase = Offset(cx, cy);
    final needleEnd = Offset(
      cx + (r - 2) * math.cos(needleAngle),
      cy + (r - 2) * math.sin(needleAngle),
    );
    final needlePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(needleBase, needleEnd, needlePaint);
    canvas.drawCircle(needleBase, 5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_ArcGaugePainter old) => old.score != score;
}
