import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/candle.dart';
import '../../models/market_flow.dart';

class MoneyFlowWidget extends StatelessWidget {
  final List<Candle> candles;
  final bool isCrypto;
  final MoneyFlowData? backendData;

  const MoneyFlowWidget({
    super.key,
    required this.candles,
    this.isCrypto = false,
    this.backendData,
  });

  _FlowData _compute() {
    if (candles.isEmpty) return const _FlowData();
    final slice = candles.length > 30 ? candles.sublist(candles.length - 30) : candles;
    double buyVol = 0, sellVol = 0, buyVal = 0, sellVal = 0;
    for (final c in slice) {
      final isBull = c.close >= c.open;
      final vol = c.volume;
      final avg = (c.open + c.close) / 2;
      if (isBull) { buyVol += vol; buyVal += vol * avg; }
      else { sellVol += vol; sellVal += vol * avg; }
    }
    final totalVol = buyVol + sellVol;
    final totalVal = buyVal + sellVal;
    final buyRatio = totalVol > 0 ? buyVol / totalVol : 0.5;
    final dayMap = <String, _DayBar>{};
    for (final c in candles) {
      final key = '${c.time.year}-${c.time.month.toString().padLeft(2,'0')}-${c.time.day.toString().padLeft(2,'0')}';
      final bar = dayMap.putIfAbsent(key, () => _DayBar(date: c.time));
      if (c.close >= c.open) { bar.buyVol += c.volume; } else { bar.sellVol += c.volume; }
    }
    final sorted = dayMap.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    final dailyBars = sorted.length > 7 ? sorted.sublist(sorted.length - 7) : sorted;
    return _FlowData(buyRatio: buyRatio, buyVol: buyVol, sellVol: sellVol,
        buyVal: buyVal, sellVal: sellVal, totalVal: totalVal, dailyBars: dailyBars);
  }

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

  @override
  Widget build(BuildContext context) {
    final data = _compute();
    if (candles.isEmpty && backendData == null) return const SizedBox.shrink();
    const green = Color(0xFF00C896);
    const red   = Color(0xFFFF4D6A);
    final buyPct  = (data.buyRatio * 100).round();
    final sellPct = 100 - buyPct;
    final netBull = data.buyRatio >= 0.5;
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
          Row(children: [
            const Text('MONEY FLOW', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            const SizedBox(width: 8),
            const Text('(30 candles)', style: TextStyle(color: Colors.white24, fontSize: 9)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: (netBull ? green : red).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: (netBull ? green : red).withValues(alpha: 0.3)),
              ),
              child: Text(netBull ? '▲ Net Buying' : '▼ Net Selling',
                  style: TextStyle(color: netBull ? green : red, fontSize: 9, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 12),
          if (backendData != null) ...[
            _CmfSection(data: backendData!),
            const SizedBox(height: 14),
            const Divider(color: Color(0xFF1E2A38), height: 1),
            const SizedBox(height: 14),
          ],
          if (candles.isNotEmpty) ...[
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('$buyPct% Buy', style: const TextStyle(color: green, fontSize: 10, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('$sellPct% Sell', style: const TextStyle(color: red, fontSize: 10, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(height: 8, child: Row(children: [
                  Expanded(flex: buyPct, child: Container(color: green)),
                  Expanded(flex: sellPct, child: Container(color: red)),
                ])),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              _StatBlock(label: 'Buy Volume', value: _fmtVol(data.buyVol), color: green),
              const SizedBox(width: 12),
              _StatBlock(label: 'Sell Volume', value: _fmtVol(data.sellVol), color: red),
              if (data.totalVal > 0) ...[
                const SizedBox(width: 12),
                _StatBlock(label: 'Net Flow', value: _fmtVal((data.buyVal - data.sellVal).abs()),
                    color: netBull ? green : red, prefix: netBull ? '+' : '-'),
              ],
            ]),
            if (data.dailyBars.length >= 2) ...[
              const SizedBox(height: 14),
              const Text('DAILY FLOW', style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              const SizedBox(height: 8),
              _DailyMiniChart(bars: data.dailyBars),
            ],
          ],
        ],
      ),
    );
  }
}

class _CmfSection extends StatelessWidget {
  final MoneyFlowData data;
  const _CmfSection({required this.data});

  static const _green = Color(0xFF26A69A);
  static const _red   = Color(0xFFEF5350);
  static const _amber = Color(0xFFFFB300);
  static const _label = Color(0xFF8A95A3);

  @override
  Widget build(BuildContext context) {
    final cmf = data.cmf20;
    final isAccum = cmf > 0.05;
    final isDist  = cmf < -0.05;
    final signalColor = isAccum ? _green : isDist ? _red : _amber;
    final signalText  = isAccum ? 'ACCUMULATION' : isDist ? 'DISTRIBUTION' : 'NEUTRAL';
    final instFlow   = data.institutionalFlow;
    final retailFlow = data.retailFlow;
    final hasSplit   = instFlow != null && retailFlow != null && (instFlow != 0 || retailFlow != 0);
    final total    = hasSplit ? (instFlow.abs() + retailFlow.abs()) : 0.0;
    final instPct  = hasSplit && total > 0 ? instFlow.abs() / total : 0.5;
    final instBull   = hasSplit && instFlow >= 0;
    final retailBull = hasSplit && retailFlow >= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('CMF-20', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: signalColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: signalColor.withValues(alpha: 0.35)),
            ),
            child: Text(signalText, style: TextStyle(color: signalColor, fontSize: 9, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text(
            cmf >= 0 ? '+${cmf.toStringAsFixed(3)}' : cmf.toStringAsFixed(3),
            style: TextStyle(color: signalColor, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('(-1 = full sell  .  +1 = full buy)', style: TextStyle(color: _label, fontSize: 9)),
            const SizedBox(height: 4),
            SizedBox(height: 6, child: CustomPaint(painter: _CmfBarPainter(cmf: cmf), size: const Size(double.infinity, 6))),
          ])),
        ]),
        if (hasSplit) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _FlowSplitBlock(label: 'Institutional', isBullish: instBull, fraction: instPct)),
            const SizedBox(width: 12),
            Expanded(child: _FlowSplitBlock(label: 'Retail', isBullish: retailBull, fraction: 1 - instPct)),
            if (data.volumeTrend != null) ...[
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('VOL TREND', style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
                const SizedBox(height: 3),
                Text(data.volumeTrend!.replaceAll('_', ' ').toUpperCase(),
                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              ])),
            ],
          ]),
        ],
      ],
    );
  }
}

class _CmfBarPainter extends CustomPainter {
  final double cmf;
  const _CmfBarPainter({required this.cmf});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(3)),
        Paint()..color = const Color(0xFF1E2A38));
    final cx = size.width / 2;
    canvas.drawRect(Rect.fromLTWH(cx - 0.5, 0, 1, size.height), Paint()..color = const Color(0xFF3A4A5A));
    final clamp = cmf.clamp(-1.0, 1.0);
    final barW  = (clamp.abs() / 2) * size.width;
    final left  = clamp >= 0 ? cx : cx - barW;
    final color = clamp >= 0 ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left, 0, barW, size.height), const Radius.circular(3)),
        Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CmfBarPainter old) => old.cmf != cmf;
}

class _FlowSplitBlock extends StatelessWidget {
  final String label;
  final bool isBullish;
  final double fraction;
  const _FlowSplitBlock({required this.label, required this.isBullish, required this.fraction});

  @override
  Widget build(BuildContext context) {
    final color = isBullish ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
      const SizedBox(height: 3),
      Text('${isBullish ? "▲" : "▼"} ${(fraction * 100).round()}%',
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    ]);
  }
}

class _StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String prefix;
  const _StatBlock({required this.label, required this.value, required this.color, this.prefix = ''});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
      const SizedBox(height: 3),
      Text('$prefix$value', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
          maxLines: 1, overflow: TextOverflow.ellipsis),
    ]),
  );
}

class _DailyMiniChart extends StatelessWidget {
  final List<_DayBar> bars;
  const _DailyMiniChart({required this.bars});

  @override
  Widget build(BuildContext context) {
    final maxVol = bars.map((b) => b.buyVol + b.sellVol).fold(0.0, (a, b) => a > b ? a : b);
    return SizedBox(
      height: 40,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: bars.map((bar) {
          final total  = bar.buyVol + bar.sellVol;
          final height = maxVol > 0 ? (total / maxVol) : 0.0;
          final buyH   = total > 0 ? bar.buyVol / total : 0.5;
          const m = ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
          final label = '${m[bar.date.month]}${bar.date.day}';
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Expanded(child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: height.clamp(0.05, 1.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: Column(children: [
                        Expanded(flex: ((1 - buyH) * 100).round().clamp(1, 99), child: Container(color: const Color(0xFFFF4D6A))),
                        Expanded(flex: (buyH * 100).round().clamp(1, 99), child: Container(color: const Color(0xFF00C896))),
                      ]),
                    ),
                  ),
                )),
                const SizedBox(height: 3),
                Text(label, style: const TextStyle(color: Colors.white30, fontSize: 7)),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _FlowData {
  final double buyRatio;
  final double buyVol;
  final double sellVol;
  final double buyVal;
  final double sellVal;
  final double totalVal;
  final List<_DayBar> dailyBars;
  const _FlowData({this.buyRatio = 0.5, this.buyVol = 0, this.sellVol = 0,
      this.buyVal = 0, this.sellVal = 0, this.totalVal = 0, this.dailyBars = const []});
}

class _DayBar {
  final DateTime date;
  double buyVol  = 0;
  double sellVol = 0;
  _DayBar({required this.date});
}
