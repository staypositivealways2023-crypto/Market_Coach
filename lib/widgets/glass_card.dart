import 'package:flutter/material.dart';

class GlassCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final double? width;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.onTap,
    this.borderRadius,
    this.width,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius =
        widget.borderRadius ?? BorderRadius.circular(16);
    // Near-black base — premium dark surface
    final effectiveColor = widget.color ?? const Color(0xFF0D1824);

    final cardContent = Container(
      width: widget.width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            effectiveColor.withOpacity(0.85),
            effectiveColor.withOpacity(0.65),
          ],
        ),
        borderRadius: effectiveBorderRadius,
        border: Border.all(
          color: const Color(0xFF2563EB).withOpacity(0.12),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.55),
            blurRadius: 16,
            offset: const Offset(0, 6),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: const Color(0xFF06B6D4).withOpacity(0.04),
            blurRadius: 24,
            offset: const Offset(0, 10),
            spreadRadius: -4,
          ),
        ],
      ),
      padding: widget.padding,
      child: widget.child,
    );

    if (widget.onTap == null) return cardContent;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap!();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        child: cardContent,
      ),
    );
  }
}

/// Wraps any Claude-generated text block with a 2dp teal left border,
/// making AI output visually distinct from raw data at a glance.
class AiTextBlock extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AiTextBlock({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(12, 10, 12, 10),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: const Border(
          left: BorderSide(color: Color(0xFF06B6D4), width: 2),
        ),
        color: const Color(0xFF06B6D4).withOpacity(0.04),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
      ),
      padding: padding,
      child: child,
    );
  }
}
