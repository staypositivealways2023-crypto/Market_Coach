import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/market_detail.dart';
import '../../models/quote.dart';
import '../../models/stock_summary.dart';
import '../../utils/market_hours.dart';

/// Premium price hero block — replaces the old _AssetHeader.
/// Shows large live price, absolute + % change, market status badge,
/// and a compact OHLV / mkt-cap metrics grid.
class PriceHeroWidget extends StatefulWidget {
  final StockSummary stock;
  final Quote? liveQuote;
  final MarketRange? marketRange;

  const PriceHeroWidget({
    super.key,
    required this.stock,
    this.liveQuote,
    this.marketRange,
  });

  @override
  State<PriceHeroWidget> createState() => _PriceHeroWidgetState();
}

class _PriceHeroWidgetState extends State<PriceHeroWidget> {
  DateTime _lastUpdate = DateTime.now();
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    // Tick every 15 s so the "Updated X ago" label stays fresh.
    _tickTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(PriceHeroWidget old) {
    super.didUpdateWidget(old);
    // Reset the clock whenever the live price actually changes.
    if (widget.liveQuote?.price != old.liveQuote?.price) {
      _lastUpdate = DateTime.now();
    }
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  // ─── Derived values ───────────────────────────────────────────────

  double get _price =>
      widget.liveQuote?.price ?? widget.stock.price;

  double get _changePct =>
      widget.liveQuote?.changePercent ?? widget.stock.changePercent;

  double get _changeAbs {
    final prev = widget.marketRange?.previousClose;
    if (prev != null && prev > 0) return _price - prev;
    // Fallback: derive from %.
    final pct = _changePct / 100.0;
    if (pct != -1.0) return _price - (_price / (1 + pct));
    return 0.0;
  }

  bool get _isPositive => _changePct >= 0;

  String get _timestampLabel {
    if (widget.liveQuote == null) return '';
    final secs = DateTime.now().difference(_lastUpdate).inSeconds;
    if (secs < 10) return 'just now';
    if (secs < 60) return '${secs}s ago';
    final mins = secs ~/ 60;
    return '${mins}m ago';
  }

  // ─── Formatting ───────────────────────────────────────────────────

  String _fmtPrice(double v) {
    if (v >= 10000) return NumberFormat('#,##0.00').format(v);
    if (v >= 1)     return NumberFormat('#,##0.00').format(v);
    return NumberFormat('#,##0.0000').format(v);
  }

  String _fmtCompact(double v) {
    final abs = v.abs();
    String formatted;
    if (abs >= 1e12)      formatted = '${(v / 1e12).toStringAsFixed(2)}T';
    else if (abs >= 1e9)  formatted = '${(v / 1e9).toStringAsFixed(2)}B';
    else if (abs >= 1e6)  formatted = '${(v / 1e6).toStringAsFixed(2)}M';
    else if (abs >= 1e3)  formatted = '${(v / 1e3).toStringAsFixed(1)}K';
    else                  formatted = v.toStringAsFixed(2);
    return '\$$formatted';
  }

  String _fmtVol(int? v) {
    if (v == null) return '—';
    if (v >= 1000000000) return '${(v / 1000000000).toStringAsFixed(2)}B';
    if (v >= 1000000)    return '${(v / 1000000).toStringAsFixed(2)}M';
    if (v >= 1000)       return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toString();
  }

  // ─── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final status = getMarketStatus(isCrypto: widget.stock.isCrypto);
    final changeColor =
        _isPositive ? const Color(0xFF00C896) : const Color(0xFFFF4D6A);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111925),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        // Subtle teal top accent
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF12A28C).withValues(alpha: 0.12),
            blurRadius: 0,
            offset: Offset.zero,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Teal top border ──────────────────────────────────────
            Container(height: 2, color: const Color(0xFF12A28C)),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Row 1: name + status badge ─────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.stock.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.stock.sector != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  [widget.stock.sector, widget.stock.industry]
                                      .whereType<String>()
                                      .join(' · '),
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _MarketStatusBadge(status: status),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // ── Row 2: large price + change ────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Price (animates on change)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, anim) =>
                            FadeTransition(opacity: anim, child: child),
                        child: Text(
                          '\$${_fmtPrice(_price)}',
                          key: ValueKey(_fmtPrice(_price)),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            height: 1.0,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Change chip
                      _ChangeChip(
                        absChange: _changeAbs,
                        pctChange: _changePct,
                        isPositive: _isPositive,
                        color: changeColor,
                        fmtPrice: _fmtPrice,
                      ),
                    ],
                  ),

                  // ── Row 3: timestamp ──────────────────────────────
                  if (widget.liveQuote != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            color: _isLive(status)
                                ? const Color(0xFF00C896)
                                : Colors.white30,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _isLive(status)
                              ? 'Updated $_timestampLabel'
                              : 'Delayed · $_timestampLabel',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 10),
                        ),
                      ]),
                    ),

                  const SizedBox(height: 14),
                  const Divider(height: 1, color: Colors.white12),
                  const SizedBox(height: 12),

                  // ── Metrics grid ──────────────────────────────────
                  _MetricsGrid(
                    range: widget.marketRange,
                    isCrypto: widget.stock.isCrypto,
                    fmtPrice: _fmtPrice,
                    fmtCompact: _fmtCompact,
                    fmtVol: _fmtVol,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isLive(MarketStatus s) =>
      s == MarketStatus.alwaysOpen || s == MarketStatus.open;
}

// ─── Market status badge ────────────────────────────────────────────────────

class _MarketStatusBadge extends StatelessWidget {
  final MarketStatus status;
  const _MarketStatusBadge({required this.status});

  Color get _color {
    switch (status) {
      case MarketStatus.alwaysOpen:  return const Color(0xFF00C896);
      case MarketStatus.open:        return const Color(0xFF00C896);
      case MarketStatus.preMarket:   return const Color(0xFFFFB74D);
      case MarketStatus.afterHours:  return const Color(0xFFFFB74D);
      case MarketStatus.closed:      return Colors.white38;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _PulseDot(color: _color,
            pulse: status == MarketStatus.alwaysOpen || status == MarketStatus.open),
        const SizedBox(width: 5),
        Text(
          status.label,
          style: TextStyle(
            color: _color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ]),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  final bool pulse;
  const _PulseDot({required this.color, required this.pulse});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _anim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.pulse) _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 6, height: 6,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: widget.pulse ? _anim.value : 0.5),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ─── Change chip ────────────────────────────────────────────────────────────

class _ChangeChip extends StatelessWidget {
  final double absChange;
  final double pctChange;
  final bool isPositive;
  final Color color;
  final String Function(double) fmtPrice;

  const _ChangeChip({
    required this.absChange,
    required this.pctChange,
    required this.isPositive,
    required this.color,
    required this.fmtPrice,
  });

  @override
  Widget build(BuildContext context) {
    final sign = isPositive ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              isPositive ? Icons.arrow_upward : Icons.arrow_downward,
              color: color, size: 13,
            ),
            const SizedBox(width: 3),
            Text(
              '$sign${pctChange.toStringAsFixed(2)}%',
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ]),
          Text(
            '$sign\$${fmtPrice(absChange.abs())}',
            style: TextStyle(
              color: color.withValues(alpha: 0.75),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Metrics grid ───────────────────────────────────────────────────────────

class _MetricsGrid extends StatelessWidget {
  final MarketRange? range;
  final bool isCrypto;
  final String Function(double) fmtPrice;
  final String Function(double) fmtCompact;
  final String Function(int?) fmtVol;

  const _MetricsGrid({
    required this.range,
    required this.isCrypto,
    required this.fmtPrice,
    required this.fmtCompact,
    required this.fmtVol,
  });

  String _p(double? v) => v != null ? '\$${fmtPrice(v)}' : '—';
  String _c(double? v) => v != null ? fmtCompact(v) : '—';

  @override
  Widget build(BuildContext context) {
    final r = range;

    // Turnover = volume × price (approx)
    double? turnover;
    if (r != null && r.volume != null && r.currentPrice != null) {
      turnover = r.volume! * r.currentPrice!;
    }

    final items = <_MetricItem>[
      _MetricItem(isCrypto ? '24H Open' : 'Open',       _p(r?.open)),
      _MetricItem(isCrypto ? '24H High' : 'Day High',   _p(r?.dayHigh)),
      _MetricItem(isCrypto ? '24H Low'  : 'Day Low',    _p(r?.dayLow)),
      _MetricItem('Prev Close', _p(r?.previousClose)),
      _MetricItem('Volume',     fmtVol(r?.volume)),
      _MetricItem('Turnover',   _c(turnover)),
      _MetricItem('Mkt Cap',    _c(r?.marketCap)),
      _MetricItem('52W High',   _p(r?.yearHigh)),
      _MetricItem('52W Low',    _p(r?.yearLow)),
    ];

    // 3-column grid
    return Wrap(
      spacing: 0,
      runSpacing: 10,
      children: items.map((item) => SizedBox(
        width: (MediaQuery.of(context).size.width - 32 - 24) / 3,
        child: _MetricTile(item: item),
      )).toList(),
    );
  }
}

class _MetricItem {
  final String label;
  final String value;
  const _MetricItem(this.label, this.value);
}

class _MetricTile extends StatelessWidget {
  final _MetricItem item;
  const _MetricTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.label.toUpperCase(),
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          item.value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
