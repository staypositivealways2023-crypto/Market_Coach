import 'package:flutter/material.dart';
import '../../models/lesson_step.dart';

class RecapStepWidget extends StatefulWidget {
  final RecapStep step;
  const RecapStepWidget({super.key, required this.step});

  @override
  State<RecapStepWidget> createState() => _RecapStepWidgetState();
}

class _RecapStepWidgetState extends State<RecapStepWidget>
    with TickerProviderStateMixin {
  late List<AnimationController> _ctrls;
  late List<Animation<double>> _fades;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(
      widget.step.points.length,
      (i) => AnimationController(
          vsync: this, duration: const Duration(milliseconds: 400)),
    );
    _fades = _ctrls
        .map((c) =>
            CurvedAnimation(parent: c, curve: Curves.easeOut))
        .toList();
    // Stagger the reveals
    for (int i = 0; i < _ctrls.length; i++) {
      Future.delayed(Duration(milliseconds: 120 * i), () {
        if (mounted) _ctrls[i].forward();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.checklist_rtl, color: Color(0xFF12A28C), size: 22),
            const SizedBox(width: 10),
            Text(
              widget.step.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ]),
          const SizedBox(height: 28),
          ...List.generate(widget.step.points.length, (i) {
            return FadeTransition(
              opacity: _fades[i],
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF12A28C).withValues(alpha: 0.15),
                        border: Border.all(
                            color: const Color(0xFF12A28C).withValues(alpha: 0.4)),
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            color: Color(0xFF12A28C),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          widget.step.points[i],
                          style: const TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 15,
                            height: 1.55,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
