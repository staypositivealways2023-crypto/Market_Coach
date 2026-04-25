import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/candle.dart';

/// Money Flow panel — approximates buy/sell pressure from candle direction.
/// Buy volume  = candles where close >= open (green candles).
/// Sell volume = candles where close <  open (red candles).
/// No backend call required; uses the candle list already loaded by AssetChartScreen.
class MoneyFlowWidget extends StatelessWidget {
  final List<Candle> candles;
  final bool isCrypto;

  const MoneyFlowWidget({
    super.key,
    required this.candles,
    this.isCrypto = false,
  });

  // ── Calculation ────────────────────────────────────────────────────────────

  _FlowData _compute() {
    if (candles.isEmpty) return const _FlowData();

    // Use last 30 candles (or all if fewer)
    final slice = candles.length > 30
        ? candles.sublist(candles.length - 30)
        : candles;

    double buyVol  = 0;
    double sellVol = 0;
    double buyVal  = 0; // buy volume × price
    double sellVal = 0;

    for (final c in slice) {
      final isBull = c.close >= c.open;
      final vol  = c.volume;
      final avg  = (c.open + c.close) / 2;
      if (isBull) {
        buyVol  += vol;
        buyVal  += vol * avg;
      } else {
        sellVol += vol;
        sellVal += vol * avg;
      }
    }

    final totalVol = buyVol + sellVol;
    final totalVal = buyVal + sellVal;
    final buyRatio = totalVol > 0 ? buyVol / totalVol : 0.5;

    // 7-day mini bars
    final dailyBars = <_DayBar>[];
    // Group by day — for intraday candles, use last 7 unique dates
    final dayMap = <String, _DayBar>{};
    for (final c in candles) {
      final key = '${c.time.year}-${c.time.month.toString().padLeft(2,'0')}-${c.time.day.toString().padLeft(2,'0')}';
      final bar = dayMap.putIfAbsent(key, () => _DayBar(date: c.time));
      if (c.close >= c.open) {
        bar.buyVol  += c.volume;
      } else {
        bar.sellVol += c.volume;
      }
    }
    final sorted = dayMap.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    dailyBars.addAll(sorted.length > 7 ? sorted.sublist(sorted.length - 7) : sorted);

    return _FlowData(
      buyRatio:  buyRatio,
      buyVol:    buyVol,
      sellVol:   sellVol,
      buyVal:    buyVal,
      sellVal:   sellVal,
      totalVal:  totalVal,
      dailyBars: dailyBars,
    );
  }

  // ── Formatting ─────────────────────────────────────────────────────────────

  static String _fmtVol(double v) {
    if (v >= 1e12) return '${(v / 1e12).toStringAsFixed(2)}T';
    if (v >= 1e9)  return '${(v / 1e9).toStringAsFixed(2)}B';
    if (v >= 1e6)  return '${(v / 1e6).toStringAsFixed(2)}M';
    if (v >= 1e3)  return '${(v / 1e3).toStringAsFixed(1)}K';
    return NumberFormat('#,##0').format(v);
  }

  static String _fmtVal(double v) {
    if (v >= 1e12) return '\$${(v / 1e12).toStringAsFixed(2)}T';
    if (v >= 1e9)  return '\$${(v / 1e9).toStringAsFixed(2)}B';
    if (v >= 1e6)  return '\$${(v / 1e6).toStringAsFixed(2)}M';
    if (v >= 1e3)  return '\$${(v / 1e3).toStringAsFixed(1)}K';
    return '\$${v.toStringAsFixed(0)}';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final data = _compute();
    if (candles.isEmpty) return const SizedBox.shrink();

    const green = Color(0xFF00C896);
    const red   = Color(0xFFFF4D6A);
    final buyPct  = (data.buyRatio * 100).round();
    final sellPct = 100 - buyPct;
    final netBull  = data.buyRatio >= 0.5;

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
          // ── Header ──────────────────────────────────────────────────
          Row(children: [
            const Text('MONEY FLOW',
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6)),
            const SizedBox(width: 8),
            const Text('(30 candles)',
                style: TextStyle(color: Colors.white24, fontSize: 9)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: (netBull ? green : red).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                    color: (netBull ? green : red).withValues(alpha: 0.3)),
              ),
              child: Text(
                netBull ? '▲ Net Buying' : '▼ Net Selling',
                style: TextStyle(
                    color: netBull ? green : red,
                    fontSize: 9,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ]),
          const SizedBox(height: 12),

          // ── Buy/Sell pressure bar ────────────────────────────────────
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('$buyPct% Buy',
                  style: const TextStyle(
                      color: green, fontSize: 10, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('$sellPct% Sell',
                  style: const TextStyle(
                      color: red, fontSize: 10, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(children: [
                  Expanded(
                    flex: buyPct,
                    child: Container(color: green),
                  ),
                  Expanded(
                    flex: sellPct,
                    child: Container(color: red),
                  ),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 14),

          // ── Volume + Value stats ─────────────────────────────────────
          Row(children: [
            _StatBlock(
              label: 'Buy Volume',
              value: _fmtVol(data.buyVol),
              color: green,
            ),
            const SizedBox(width: 12),
            _StatBlock(
              label: 'Sell Volume',
              value: _fmtVol(data.sellVol),
              color: red,
            ),
            if (data.totalVal > 0) ...[
              const SizedBox(width: 12),
              _StatBlock(
                label: 'Net Flow',
                value: _fmtVal((data.buyVal - data.sellVal).abs()),
                color: netBull ? green : red,
                prefix: netBull ? '+' : '-',
              ),
            ],
          ]),

          // ── Mini daily bars ──────────────────────────────────────────
          if (data.dailyBars.length >= 2) ...[
            const SizedBox(height: 14),
            const Text('DAILY FLOW',
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4)),
            const SizedBox(height: 8),
            _DailyMiniChart(bars: data.dailyBars),
          ],
        ],
      ),
    );
  }
}

// ── Stat block ────────────────────────────────────────────────────────────────

class _StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String prefix;

  const _StatBlock({
    required this.label,
    required this.value,
    required this.color,
    this.prefix = '',
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(),
          style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3)),
      const SizedBox(height: 3),
      Text('$prefix$value',
          style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
    ]),
  );
}

// ── Daily mini bar chart ─────────────────────────────────────────────────────

class _DailyMiniChart extends StatelessWidget {
  final List<_DayBar> bars;
  const _DailyMiniChart({required this.bars});

  @override
  Widget build(BuildContext context) {
    final maxVol = bars
        .map((b) => b.buyVol + b.sellVol)
        .fold(0.0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 40,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: bars.map((bar) {
          final total = bar.buyVol + bar.sellVol;
          final height = maxVol > 0 ? (total / maxVol) : 0.0;
          final buyH   = total > 0 ? bar.buyVol  / total : 0.5;
          final label  = _dayLabel(bar.date);

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: height.clamp(0.05, 1.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: Column(children: [
                            // Buy portion (bottom, green)
                            Expanded(
                              flex: (buyH * 100).round().clamp(1, 99),
                              child: Container(color: const Color(0xFF00C896)),
                            ),
                            // Sell portion (top, red)
                            Expanded(
                              flex: ((1 - buyH) * 100).round().clamp(1, 99),
                              child: Container(color: const Color(0xFFFF4D6A)),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white30, fontSize: 7)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  static String _dayLabel(DateTime d) {
    const m = ['','Jan','Feb','Mar','Apr','May','Jun',
                   'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month]}${d.day}';
  }
}

// ── Data models ───────────────────────────────────────────────────────────────

class _FlowData {
  final double buyRatio;
  final double buyVol;
  final double sellVol;
  final double buyVal;
  final double sellVal;
  final double totalVal;
  final List<_DayBar> dailyBars;

  const _FlowData({
    this.buyRatio  = 0.5,
    this.buyVol    = 0,
    this.sellVol   = 0,
    this.buyVal    = 0,
    this.sellVal   = 0,
    this.totalVal  = 0,
    this.dailyBars = const [],
  });
}

class _DayBar {
  final DateTime date;
  double buyVol  = 0;
  double sellVol = 0;
  _DayBar({required this.date});
}
