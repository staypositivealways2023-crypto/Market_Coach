import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../models/signal_analysis.dart';

// ─── Public entry point ──────────────────────────────────────────────────────

/// Market position panel — support/resistance bars, signal counts,
/// trend badge, and a semicircle sentiment gauge.
/// All data comes from [SignalAnalysis] already loaded by AssetChartScreen.
class MarketPositionWidget extends StatelessWidget {
  final SignalAnalysis signal;
  final double currentPrice;

  const MarketPositionWidget({
    super.key,
    required this.signal,
    required this.currentPrice,
  });

  @override
  Widget build(BuildContext context) {
    final bullish = _countBullish(signal);
    final bearish  = _countBearish(signal);
    final total    = bullish + bearish;
    final score    = signal.compositeScore;          // 0.0–1.0
    final label    = signal.signalLabel;             // STRONG_BUY … STRONG_SELL
    final patterns = signal.patterns;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111925),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────
          Row(children: [
            const Text('MARKET POSITION',
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6)),
            const Spacer(),
            _TrendBadge(
              trend: patterns?.trend ?? 'SIDEWAYS',
              strength: patterns?.trendStrength ?? 'WEAK',
            ),
          ]),
          const SizedBox(height: 14),

          // ── Two-column layout ──────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: sentiment gauge
              _SentimentGauge(score: score, label: label),
              const SizedBox(width: 16),
              // Right: signal counts + S/R bars
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SignalCountRow(bullish: bullish, bearish: bearish, total: total),
                    const SizedBox(height: 12),
                    if (patterns != null && patterns.supportResistance.isNotEmpty)
                      _SRBars(
                        levels: patterns.supportResistance,
                        currentPrice: currentPrice,
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Indicator chips row ────────────────────────────────────
          _IndicatorChips(signal: signal),
        ],
      ),
    );
  }

  // ── Signal counting ─────────────────────────────────────────────────────────

  static int _countBullish(SignalAnalysis s) {
    int n = 0;
    final ind = s.signals.indicators;
    if (ind.rsiSignal == 'OVERSOLD')                                            n++;
    if (ind.macdSignal == 'BULLISH' || ind.macdSignal == 'BULLISH_CROSS')      n++;
    if (ind.emaStack == 'PRICE_ABOVE_ALL' || ind.emaStack == 'PRICE_ABOVE_20_50') n++;
    if (ind.volume == 'ABOVE_AVERAGE')                                          n++;
    if (ind.bbPosition == 'LOWER' || ind.bbPosition == 'BELOW_LOWER')          n++;
    if (s.signals.candlestick.signal == 'BULLISH')                              n++;
    return n;
  }

  static int _countBearish(SignalAnalysis s) {
    int n = 0;
    final ind = s.signals.indicators;
    if (ind.rsiSignal == 'OVERBOUGHT')                                          n++;
    if (ind.macdSignal == 'BEARISH' || ind.macdSignal == 'BEARISH_CROSS')      n++;
    if (ind.emaStack == 'PRICE_BELOW_ALL')                                      n++;
    if (ind.bbPosition == 'ABOVE_UPPER' || ind.bbPosition == 'UPPER')          n++;
    if (s.signals.candlestick.signal == 'BEARISH')                              n++;
    return n;
  }
}

// ─── Trend badge ─────────────────────────────────────────────────────────────

class _TrendBadge extends StatelessWidget {
  final String trend;
  final String strength;
  const _TrendBadge({required this.trend, required this.strength});

  Color get _color {
    switch (trend) {
      case 'UPTREND':   return const Color(0xFF00C896);
      case 'DOWNTREND': return const Color(0xFFFF4D6A);
      default:          return Colors.white38;
    }
  }

  String get _label {
    final t = trend == 'UPTREND' ? '↑ UP' : trend == 'DOWNTREND' ? '↓ DOWN' : '→ SIDE';
    final s = strength == 'STRONG' ? ' ●●●' : strength == 'MEDIUM' ? ' ●●○' : ' ●○○';
    return '$t$s';
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: _color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: _color.withValues(alpha: 0.3)),
    ),
    child: Text(_label,
        style: TextStyle(
            color: _color, fontSize: 10, fontWeight: FontWeight.w700)),
  );
}

// ─── Sentiment gauge (semicircle) ─────────────────────────────────────────────

class _SentimentGauge extends StatelessWidget {
  final double score;   // 0.0–1.0
  final String label;
  const _SentimentGauge({required this.score, required this.label});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 110,
    height: 72,
    child: CustomPaint(
      painter: _GaugePainter(score: score.clamp(0.0, 1.0)),
      child: Align(
        alignment: const Alignment(0, 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            '${(score * 100).round()}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.0),
          ),
          Text(
            _shortLabel(label),
            style: TextStyle(
                color: _labelColor(label),
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3),
          ),
        ]),
      ),
    ),
  );

  static String _shortLabel(String l) => switch (l) {
    'STRONG_BUY'  => 'STRONG BUY',
    'BUY'         => 'BUY',
    'SELL'        => 'SELL',
    'STRONG_SELL' => 'STRONG SELL',
    _             => 'NEUTRAL',
  };

  static Color _labelColor(String l) {
    if (l.contains('BUY'))  return const Color(0xFF00C896);
    if (l.contains('SELL')) return const Color(0xFFFF4D6A);
    return Colors.white54;
  }
}

class _GaugePainter extends CustomPainter {
  final double score; // 0.0–1.0
  const _GaugePainter({required this.score});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.88;
    final r  = size.width * 0.46;
    const strokeW = 8.0;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    // Track (grey arc)
    canvas.drawArc(
      rect, math.pi, math.pi, false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..strokeWidth = strokeW
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Coloured progress arc
    final arcColor = Color.lerp(
      const Color(0xFFFF4D6A),
      const Color(0xFF00C896),
      score,
    )!;
    canvas.drawArc(
      rect, math.pi, math.pi * score, false,
      Paint()
        ..color = arcColor
        ..strokeWidth = strokeW
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Needle
    final angle = math.pi + math.pi * score;
    final needleEnd = Offset(
      cx + (r - strokeW / 2) * math.cos(angle),
      cy + (r - strokeW / 2) * math.sin(angle),
    );
    canvas.drawLine(
      Offset(cx, cy), needleEnd,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(cx, cy), 3, Paint()..color = Colors.white);

    // "Sell" / "Buy" end labels
    final sellTp = TextPainter(
      text: const TextSpan(
          text: 'Sell',
          style: TextStyle(
              color: Color(0xFFFF4D6A), fontSize: 7, fontWeight: FontWeight.w700)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    sellTp.paint(canvas, Offset(0, cy - sellTp.height / 2));

    final buyTp = TextPainter(
      text: const TextSpan(
          text: 'Buy',
          style: TextStyle(
              color: Color(0xFF00C896), fontSize: 7, fontWeight: FontWeight.w700)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    buyTp.paint(canvas, Offset(size.width - buyTp.width, cy - buyTp.height / 2));
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.score != score;
}

// ─── Signal count row ─────────────────────────────────────────────────────────

class _SignalCountRow extends StatelessWidget {
  final int bullish;
  final int bearish;
  final int total;
  const _SignalCountRow(
      {required this.bullish, required this.bearish, required this.total});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('SIGNALS',
          style: TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4)),
      const SizedBox(height: 6),
      Row(children: [
        _CountChip(count: bullish, label: 'Bull', color: const Color(0xFF00C896)),
        const SizedBox(width: 6),
        _CountChip(count: bearish, label: 'Bear', color: const Color(0xFFFF4D6A)),
        if (total > 0) ...[
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: total > 0 ? bullish / total : 0.5,
                backgroundColor: const Color(0xFFFF4D6A).withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF00C896)),
                minHeight: 5,
              ),
            ),
          ),
        ],
      ]),
    ]);
  }
}

class _CountChip extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  const _CountChip(
      {required this.count, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$count',
          style: TextStyle(
              color: color, fontSize: 14, fontWeight: FontWeight.w800)),
      const SizedBox(width: 3),
      Text(label,
          style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontSize: 9,
              fontWeight: FontWeight.w600)),
    ]),
  );
}

// ─── Support / Resistance bars ────────────────────────────────────────────────

class _SRBars extends StatelessWidget {
  final List<SupportResistanceLevel> levels;
  final double currentPrice;
  const _SRBars({required this.levels, required this.currentPrice});

  @override
  Widget build(BuildContext context) {
    // Take strongest resistance and support level
    final resistances = levels
        .where((l) => l.type == 'RESISTANCE')
        .toList()
      ..sort((a, b) => b.strength.compareTo(a.strength));
    final supports = levels
        .where((l) => l.type == 'SUPPORT')
        .toList()
      ..sort((a, b) => b.strength.compareTo(a.strength));

    final topResist = resistances.isNotEmpty ? resistances.first : null;
    final topSupport = supports.isNotEmpty ? supports.first : null;

    if (topResist == null && topSupport == null) return const SizedBox.shrink();

    final high = topResist?.price ?? currentPrice * 1.05;
    final low  = topSupport?.price ?? currentPrice * 0.95;
    final range = high - low;
    final ratio = range > 0
        ? ((currentPrice - low) / range).clamp(0.0, 1.0)
        : 0.5;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('SUPPORT / RESISTANCE',
          style: TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4)),
      const SizedBox(height: 8),

      // Resistance label
      if (topResist != null)
        Row(children: [
          const Text('R', style: TextStyle(color: Color(0xFFFF4D6A), fontSize: 9, fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          Text('\$${_fmt(topResist.price)}',
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
          const Spacer(),
          Text('str ${topResist.strength}',
              style: const TextStyle(color: Colors.white30, fontSize: 9)),
        ]),
      const SizedBox(height: 4),

      // Gradient bar with current price dot
      SizedBox(
        height: 14,
        child: LayoutBuilder(builder: (_, c) {
          final w = c.maxWidth;
          final dotX = (ratio * w).clamp(6.0, w - 6.0);
          return Stack(children: [
            // Track
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF00C896), Color(0xFFFF4D6A)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                ),
              ),
            ),
            // Current price dot
            Positioned(
              left: dotX - 6,
              top: 1,
              child: Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 4)
                  ],
                ),
              ),
            ),
          ]);
        }),
      ),
      const SizedBox(height: 4),

      // Support label
      if (topSupport != null)
        Row(children: [
          const Text('S', style: TextStyle(color: Color(0xFF00C896), fontSize: 9, fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          Text('\$${_fmt(topSupport.price)}',
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
          const Spacer(),
          Text('str ${topSupport.strength}',
              style: const TextStyle(color: Colors.white30, fontSize: 9)),
        ]),
    ]);
  }

  static String _fmt(double v) => v >= 1000
      ? v.toStringAsFixed(0)
      : v >= 1
          ? v.toStringAsFixed(2)
          : v.toStringAsFixed(4);
}

// ─── Indicator chips ──────────────────────────────────────────────────────────

class _IndicatorChips extends StatelessWidget {
  final SignalAnalysis signal;
  const _IndicatorChips({required this.signal});

  @override
  Widget build(BuildContext context) {
    final ind = signal.signals.indicators;
    final chips = <_Chip>[
      _chipFromSignal('RSI', ind.rsiSignal,
          bull: 'OVERSOLD', bear: 'OVERBOUGHT'),
      _chipFromSignal('MACD', ind.macdSignal,
          bull: 'BULLISH', bear: 'BEARISH',
          altBull: 'BULLISH_CROSS', altBear: 'BEARISH_CROSS'),
      _chipFromSignal('EMA', ind.emaStack,
          bull: 'PRICE_ABOVE_ALL', bear: 'PRICE_BELOW_ALL'),
      _chipFromSignal('VOL', ind.volume,
          bull: 'ABOVE_AVERAGE', bear: 'BELOW_AVERAGE'),
      _chipFromSignal('BB', ind.bbPosition,
          bear: 'ABOVE_UPPER', bull: 'BELOW_LOWER'),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips.map((c) => _IndicatorChip(chip: c)).toList(),
    );
  }

  static _Chip _chipFromSignal(String label, String value,
      {required String bull,
      required String bear,
      String? altBull,
      String? altBear}) {
    Color color;
    String display;
    if (value == bull || value == altBull) {
      color = const Color(0xFF00C896);
      display = _shorten(value);
    } else if (value == bear || value == altBear) {
      color = const Color(0xFFFF4D6A);
      display = _shorten(value);
    } else {
      color = Colors.white38;
      display = _shorten(value);
    }
    return _Chip(label: label, value: display, color: color);
  }

  static String _shorten(String v) => switch (v) {
    'OVERSOLD'        => 'Oversold',
    'OVERBOUGHT'      => 'Overbought',
    'BULLISH'         => 'Bull',
    'BEARISH'         => 'Bear',
    'BULLISH_CROSS'   => '↑ Cross',
    'BEARISH_CROSS'   => '↓ Cross',
    'PRICE_ABOVE_ALL' => 'Above All',
    'PRICE_BELOW_ALL' => 'Below All',
    'PRICE_ABOVE_20_50' => 'Above 20/50',
    'ABOVE_AVERAGE'   => 'High Vol',
    'BELOW_AVERAGE'   => 'Low Vol',
    'ABOVE_UPPER'     => 'Above BB',
    'BELOW_LOWER'     => 'Below BB',
    _                 => v,
  };
}

class _Chip {
  final String label;
  final String value;
  final Color color;
  const _Chip({required this.label, required this.value, required this.color});
}

class _IndicatorChip extends StatelessWidget {
  final _Chip chip;
  const _IndicatorChip({required this.chip});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: chip.color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: chip.color.withValues(alpha: 0.22)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('${chip.label} ',
          style: const TextStyle(
              color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w600)),
      Text(chip.value,
          style: TextStyle(
              color: chip.color,
              fontSize: 9,
              fontWeight: FontWeight.w700)),
    ]),
  );
}
