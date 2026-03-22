import 'package:flutter/material.dart';

// ─── Shared RSI zone bar ──────────────────────────────────────────────────────
// Used in VisualExplainerStep (animated, read-only) and TapToIdentifyStep
// (interactive zone selection).

const _kOversoldColor = Color(0xFF4CAF50);
const _kNeutralColor = Color(0xFF546E7A);
const _kOverboughtColor = Color(0xFFEF5350);

/// A horizontal 0–100 RSI spectrum bar with three coloured zones.
/// When [interactive] is true each zone is a tappable GestureDetector.
class RsiZoneBar extends StatelessWidget {
  final bool interactive;
  final String? tappedZone;      // 'oversold' | 'neutral' | 'overbought'
  final bool? tapCorrect;
  final void Function(String zoneId)? onTap;
  final double? indicatorValue;  // 0–100; draws an arrow when provided

  const RsiZoneBar({
    super.key,
    this.interactive = false,
    this.tappedZone,
    this.tapCorrect,
    this.onTap,
    this.indicatorValue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Zone labels
        Row(children: [
          Expanded(flex: 30, child: _ZoneLabel('OVERSOLD', _kOversoldColor)),
          Expanded(flex: 40, child: _ZoneLabel('NEUTRAL', _kNeutralColor)),
          Expanded(flex: 30, child: _ZoneLabel('OVERBOUGHT', _kOverboughtColor)),
        ]),
        const SizedBox(height: 8),
        // Bar
        Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 48,
                child: Row(children: [
                  _ZoneSegment(
                    id: 'oversold',
                    flex: 30,
                    color: _kOversoldColor,
                    interactive: interactive,
                    tapped: tappedZone == 'oversold',
                    tapCorrect: tappedZone == 'oversold' ? tapCorrect : null,
                    onTap: onTap,
                  ),
                  _ZoneSegment(
                    id: 'neutral',
                    flex: 40,
                    color: _kNeutralColor,
                    interactive: interactive,
                    tapped: tappedZone == 'neutral',
                    tapCorrect: tappedZone == 'neutral' ? tapCorrect : null,
                    onTap: onTap,
                  ),
                  _ZoneSegment(
                    id: 'overbought',
                    flex: 30,
                    color: _kOverboughtColor,
                    interactive: interactive,
                    tapped: tappedZone == 'overbought',
                    tapCorrect: tappedZone == 'overbought' ? tapCorrect : null,
                    onTap: onTap,
                  ),
                ]),
              ),
            ),
            // Animated indicator arrow
            if (indicatorValue != null)
              _IndicatorArrow(value: indicatorValue!),
          ],
        ),
        const SizedBox(height: 4),
        // Value ticks
        const Row(children: [
          SizedBox(width: 0),
          Expanded(flex: 30, child: Align(alignment: Alignment.centerLeft,  child: Text('0',   style: TextStyle(color: Colors.white38, fontSize: 10)))),
          Expanded(flex: 40, child: Align(alignment: Alignment.centerLeft,  child: Text('30',  style: TextStyle(color: Colors.white38, fontSize: 10)))),
          Expanded(flex: 30, child: Align(alignment: Alignment.centerLeft,  child: Text('70',  style: TextStyle(color: Colors.white38, fontSize: 10)))),
          Align(alignment: Alignment.centerRight, child: Text('100', style: TextStyle(color: Colors.white38, fontSize: 10))),
        ]),
      ],
    );
  }
}

class _ZoneLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _ZoneLabel(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _ZoneSegment extends StatefulWidget {
  final String id;
  final int flex;
  final Color color;
  final bool interactive;
  final bool tapped;
  final bool? tapCorrect;
  final void Function(String)? onTap;

  const _ZoneSegment({
    required this.id,
    required this.flex,
    required this.color,
    required this.interactive,
    required this.tapped,
    required this.tapCorrect,
    required this.onTap,
  });

  @override
  State<_ZoneSegment> createState() => _ZoneSegmentState();
}

class _ZoneSegmentState extends State<_ZoneSegment>
    with SingleTickerProviderStateMixin {
  late AnimationController _shakeCtrl;
  late Animation<double> _shake;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _shake = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticOut));
  }

  @override
  void didUpdateWidget(_ZoneSegment old) {
    super.didUpdateWidget(old);
    // Trigger shake when this zone was tapped incorrectly
    if (widget.tapped && widget.tapCorrect == false && !old.tapped) {
      _shakeCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color bg = widget.color.withValues(alpha: 0.18);
    if (widget.tapped) {
      if (widget.tapCorrect == true) bg = widget.color.withValues(alpha: 0.45);
      if (widget.tapCorrect == false) bg = Colors.red.withValues(alpha: 0.3);
    }

    final content = AnimatedBuilder(
      animation: _shake,
      builder: (_, child) {
        final dx = widget.tapped && widget.tapCorrect == false
            ? 4.0 * (0.5 - (_shake.value % 1)).abs()
            : 0.0;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(
            color: widget.tapped
                ? (widget.tapCorrect == true
                    ? widget.color
                    : Colors.red.withValues(alpha: 0.6))
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Center(
          child: widget.tapped && widget.tapCorrect == true
              ? Icon(Icons.check_circle, color: widget.color, size: 20)
              : widget.tapped && widget.tapCorrect == false
                  ? const Icon(Icons.close, color: Colors.red, size: 20)
                  : widget.interactive
                      ? Icon(Icons.touch_app,
                          color: widget.color.withValues(alpha: 0.5), size: 16)
                      : null,
        ),
      ),
    );

    if (!widget.interactive) return Expanded(flex: widget.flex, child: content);

    return Expanded(
      flex: widget.flex,
      child: GestureDetector(
        onTap: () => widget.onTap?.call(widget.id),
        child: content,
      ),
    );
  }
}

class _IndicatorArrow extends StatelessWidget {
  final double value; // 0–100

  const _IndicatorArrow({required this.value});

  @override
  Widget build(BuildContext context) {
    // The bar occupies full width. Map value 0-100 → 0-1 fraction
    return LayoutBuilder(builder: (context, constraints) {
      final frac = (value / 100).clamp(0.0, 1.0);
      final x = frac * constraints.maxWidth;
      return SizedBox(
        height: 48,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: x - 6,
              bottom: -18,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_drop_up, color: Colors.white, size: 20),
                  Text(
                    value.toStringAsFixed(0),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}
