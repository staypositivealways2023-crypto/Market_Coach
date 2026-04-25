import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Small "label / value" stack used under hero cards:
///
///     Cash            Holdings         Return
///     $837.9K         $171.7K          +0.96%
///
/// Keep the label uppercase overline style and the value heavy-weight.
class MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final TextStyle? valueStyle;
  final CrossAxisAlignment align;

  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.valueStyle,
    this.align = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(), style: AppText.overline),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: (valueStyle ?? AppText.bodyStrong).copyWith(
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// A row of [MetricTile]s separated by [AppColors.divider] spacing.
class MetricRow extends StatelessWidget {
  final List<MetricTile> tiles;
  final bool withDividers;

  const MetricRow({
    super.key,
    required this.tiles,
    this.withDividers = false,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      children.add(Expanded(child: tiles[i]));
      if (withDividers && i != tiles.length - 1) {
        children.add(Container(
          height: 28,
          width: 1,
          color: AppColors.divider,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        ));
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
