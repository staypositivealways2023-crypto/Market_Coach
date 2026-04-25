import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Uppercase, tracked section label — "MARKET PULSE", "WATCHLIST",
/// "INVESTOR IQ" etc. Optionally renders a trailing widget on the right
/// (e.g. an "Edit" or "View all" action) to match the mocks.
class SectionLabel extends StatelessWidget {
  final String label;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionLabel({
    super.key,
    required this.label,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.screenPad),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(label.toUpperCase(), style: AppText.overline),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Common right-aligned action used next to [SectionLabel].
class SectionAction extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? trailingIcon;

  const SectionAction({
    super.key,
    required this.label,
    this.onTap,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppText.caption.copyWith(
              color: AppColors.accentBright,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 4),
            Icon(trailingIcon, size: 14, color: AppColors.accentBright),
          ],
        ],
      ),
    );
  }
}
