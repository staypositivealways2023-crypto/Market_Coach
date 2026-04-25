import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// The default elevated container for the redesigned UI.
///
/// Replaces [GlassCard]'s blue-shadow gradient with the redesign's flat,
/// high-contrast dark card (single-color fill, hairline border, soft black
/// drop shadow). Kept as its own widget so migration can happen screen by
/// screen without breaking existing [GlassCard] usages.
class PremiumCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final double? width;
  final bool bordered;
  final bool glow;

  const PremiumCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.color,
    this.onTap,
    this.borderRadius,
    this.width,
    this.bordered = true,
    this.glow = false,
  });

  @override
  State<PremiumCard> createState() => _PremiumCardState();
}

class _PremiumCardState extends State<PremiumCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(AppRadius.card);
    final content = Container(
      width: widget.width,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.color ?? AppColors.card,
        borderRadius: radius,
        border: widget.bordered
            ? Border.all(color: AppColors.border, width: 0.6)
            : null,
        boxShadow: widget.glow ? AppShadow.accentGlow : AppShadow.card,
      ),
      child: widget.child,
    );

    if (widget.onTap == null) return content;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap!();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 90),
        scale: _pressed ? 0.98 : 1.0,
        curve: Curves.easeOut,
        child: content,
      ),
    );
  }
}
