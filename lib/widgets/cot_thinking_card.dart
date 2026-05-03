// CoT Thinking Card — Phase 8
// Displays the DeepSeek-R1 chain-of-thought reasoning block.
// Collapsed by default; user taps to expand.

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import 'glass_card.dart';

class CotThinkingCard extends StatefulWidget {
  /// The raw `<think>…</think>` content extracted from DeepSeek-R1 output.
  final String thinking;

  const CotThinkingCard({super.key, required this.thinking});

  @override
  State<CotThinkingCard> createState() => _CotThinkingCardState();
}

class _CotThinkingCardState extends State<CotThinkingCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _controller.forward() : _controller.reverse();
  }

  // Rough word count for the summary line
  String get _summary {
    final words = widget.thinking.split(RegExp(r'\s+')).length;
    return '$words-word reasoning chain';
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header — always visible ──────────────────────────────────────
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(16),
            splashColor: const Color(0xFF12A28C).withValues(alpha: 0.08),
            highlightColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(children: [
                // Brain icon badge
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xFF12A28C).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.psychology_outlined,
                    color: Color(0xFF12A28C),
                    size: 17,
                  ),
                ),
                const SizedBox(width: 10),

                // Title + summary
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reasoning Chain',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _expanded ? 'Tap to collapse' : _summary,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                // Animated chevron
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 280),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white38,
                    size: 20,
                  ),
                ),
              ]),
            ),
          ),

          // ── Expandable body ──────────────────────────────────────────────
          SizeTransition(
            sizeFactor: _fade,
            axisAlignment: -1,
            child: Column(children: [
              const Divider(height: 1, color: Colors.white10),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12A28C).withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF12A28C).withValues(alpha: 0.15),
                    ),
                  ),
                  child: SelectableText(
                    widget.thinking,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.65,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
