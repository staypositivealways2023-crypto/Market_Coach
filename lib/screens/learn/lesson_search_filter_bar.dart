import 'package:flutter/material.dart';
import 'learn_constants.dart';

/// Search field + horizontally-scrollable status filter chips.
/// Replaces the previous full-width DropdownButton.
class LessonSearchFilterBar extends StatelessWidget {
  final String searchQuery;
  final ProgressFilter progressFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ProgressFilter> onFilterChanged;

  const LessonSearchFilterBar({
    super.key,
    required this.searchQuery,
    required this.progressFilter,
    required this.onSearchChanged,
    required this.onFilterChanged,
  });

  static const _filters = [
    (label: 'All', value: ProgressFilter.all),
    (label: 'Bookmarked', value: ProgressFilter.bookmarked),
    (label: 'Completed', value: ProgressFilter.completed),
    (label: 'In Progress', value: ProgressFilter.inProgress),
    (label: 'Not Started', value: ProgressFilter.notStarted),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Search field ──────────────────────────────────────────────
          SizedBox(
            height: 42,
            child: TextField(
              onChanged: onSearchChanged,
              style: const TextStyle(color: kLearnTextPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search lessons...',
                hintStyle: const TextStyle(
                    color: kLearnTextSecondary, fontSize: 14),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: kLearnTextSecondary,
                ),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded,
                            size: 16, color: kLearnTextSecondary),
                        onPressed: () => onSearchChanged(''),
                      )
                    : null,
                filled: true,
                fillColor: kLearnSurface,
                contentPadding: EdgeInsets.zero,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: kLearnBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: kLearnAccent.withValues(alpha: 0.5), width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // ── Status filter chips ───────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filters.map((f) {
                final isSelected = progressFilter == f.value;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => onFilterChanged(f.value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? kLearnAccent.withValues(alpha: 0.14)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? kLearnAccent.withValues(alpha: 0.45)
                              : kLearnBorder,
                        ),
                      ),
                      child: Text(
                        f.label,
                        style: TextStyle(
                          color: isSelected
                              ? kLearnAccent
                              : kLearnTextSecondary,
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
