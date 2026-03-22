import 'package:flutter/material.dart';
import '../../models/lesson_step.dart';
import '../rsi_zone_bar.dart';

class VisualExplainerWidget extends StatefulWidget {
  final VisualExplainerStep step;
  const VisualExplainerWidget({super.key, required this.step});

  @override
  State<VisualExplainerWidget> createState() => _VisualExplainerWidgetState();
}

class _VisualExplainerWidgetState extends State<VisualExplainerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _indicator;

  @override
  void initState() {
    super.initState();
    // Animate the indicator dot from 50 (neutral) → 78 (overbought) → 22 (oversold) → 50
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2800));
    _indicator = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 50, end: 78), weight: 30),
      TweenSequenceItem(tween: ConstantTween(78), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 78, end: 22), weight: 35),
      TweenSequenceItem(tween: ConstantTween(22), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 22, end: 50), weight: 5),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

    _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF12A28C).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border:
                  Border.all(color: const Color(0xFF12A28C).withValues(alpha: 0.3)),
            ),
            child: const Text(
              'VISUAL',
              style: TextStyle(
                color: Color(0xFF12A28C),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.step.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 32),
          // Animated RSI zone bar
          AnimatedBuilder(
            animation: _indicator,
            builder: (context, _) => RsiZoneBar(
              indicatorValue: _indicator.value,
            ),
          ),
          const SizedBox(height: 40),
          // Zone descriptions
          _ZoneDescription(
            color: const Color(0xFFEF5350),
            label: '70 – 100',
            name: 'Overbought',
            description: 'Buyers have pushed price up rapidly. '
                'The market may be overheating.',
          ),
          const SizedBox(height: 14),
          _ZoneDescription(
            color: const Color(0xFF546E7A),
            label: '30 – 70',
            name: 'Neutral',
            description: 'Normal momentum range. '
                'No extreme signal.',
          ),
          const SizedBox(height: 14),
          _ZoneDescription(
            color: const Color(0xFF4CAF50),
            label: '0 – 30',
            name: 'Oversold',
            description: 'Sellers have driven price down hard. '
                'A bounce may be near.',
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              widget.step.explanation,
              style: const TextStyle(
                color: Color(0xB3FFFFFF),
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoneDescription extends StatelessWidget {
  final Color color;
  final String label;
  final String name;
  final String description;

  const _ZoneDescription({
    required this.color,
    required this.label,
    required this.name,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 52,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text('· $name',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 3),
              Text(description,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 13, height: 1.45)),
            ],
          ),
        ),
      ],
    );
  }
}
