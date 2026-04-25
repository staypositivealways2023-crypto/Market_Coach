import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_tokens.dart';

/// Floating pill-shaped bottom navigation used across the redesigned app.
///
/// Matches the mocks: rounded container sitting above the home-indicator,
/// subtle top highlight for the active tab, teal label on the selected item,
/// and a small teal top-edge accent bar above the active tab.
class FloatingBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<FloatingNavItem> items;

  const FloatingBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        bottomPad > 0 ? bottomPad : AppSpacing.md,
      ),
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.nav),
          border: Border.all(color: AppColors.border, width: 0.6),
          boxShadow: AppShadow.navFloat,
        ),
        child: Row(
          children: List.generate(items.length, (i) {
            final item = items[i];
            final selected = selectedIndex == i;
            return Expanded(
              child: _NavButton(
                item: item,
                selected: selected,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap(i);
                },
              ),
            );
          }),
        ),
      ),
    );
  }
}

class FloatingNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const FloatingNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

class _NavButton extends StatelessWidget {
  final FloatingNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accentBright : AppColors.textMuted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // Top-edge accent line above the active tab.
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: selected ? 1 : 0,
            child: Container(
              margin: const EdgeInsets.only(top: 6),
              height: 2,
              width: 24,
              decoration: BoxDecoration(
                color: AppColors.accentBright,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accentBright.withOpacity(0.6),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? item.activeIcon : item.icon,
                  size: 22,
                  color: color,
                ),
                const SizedBox(height: 4),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: color,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
