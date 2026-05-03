/// MemoryTimelineScreen — Phase 4: Deep Memory System
///
/// Shows the user everything the analyst "knows" about them, grouped
/// by category. Each entry can be deleted (trust feature).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/memory_entry.dart';
import '../../providers/memory_provider.dart';
import '../../widgets/glass_card.dart';

// ── Category metadata ─────────────────────────────────────────────────────────

class _CategoryMeta {
  final String label;
  final IconData icon;
  final Color color;
  const _CategoryMeta(this.label, this.icon, this.color);
}

const _kCategories = <String, _CategoryMeta>{
  'all':                _CategoryMeta('All',          Icons.memory_outlined,         Color(0xFF12A28C)),
  'trade_history':      _CategoryMeta('Trades',       Icons.candlestick_chart,       Color(0xFF10B981)),
  'risk_profile':       _CategoryMeta('Risk',         Icons.shield_outlined,         Color(0xFFEF4444)),
  'watchlist_patterns': _CategoryMeta('Watchlist',    Icons.bookmark_outline,        Color(0xFF8B5CF6)),
  'preference':         _CategoryMeta('Preferences',  Icons.tune,                    Color(0xFF06B6D4)),
  'learning':           _CategoryMeta('Learning',     Icons.school_outlined,         Color(0xFFF59E0B)),
  'portfolio':          _CategoryMeta('Portfolio',    Icons.pie_chart_outline,       Color(0xFFEC4899)),
  'conversation':       _CategoryMeta('Chats',        Icons.chat_bubble_outline,     Color(0xFF64748B)),
  'event':              _CategoryMeta('Events',       Icons.bolt_outlined,           Color(0xFF94A3B8)),
};

_CategoryMeta _meta(String category) =>
    _kCategories[category] ?? _CategoryMeta(category, Icons.circle, Colors.white38);

// ── Screen ────────────────────────────────────────────────────────────────────

class MemoryTimelineScreen extends ConsumerStatefulWidget {
  const MemoryTimelineScreen({super.key});

  @override
  ConsumerState<MemoryTimelineScreen> createState() =>
      _MemoryTimelineScreenState();
}

class _MemoryTimelineScreenState extends ConsumerState<MemoryTimelineScreen> {
  // null = "All"
  String? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timelineAsync =
        ref.watch(memoryTimelineProvider(_selectedCategory));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D131A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Analyst Memory',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              'What Dean knows about you',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh, size: 20, color: Colors.white54),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(memoryTimelineProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          _CategoryFilterBar(
            selected: _selectedCategory,
            onSelect: (cat) =>
                setState(() => _selectedCategory = cat),
          ),
          Expanded(
            child: timelineAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => _EmptyState(
                icon: Icons.error_outline,
                message: 'Could not load memories.',
                subtext: 'Check your connection and try again.',
              ),
              data: (entries) => entries.isEmpty
                  ? _EmptyState(
                      icon: Icons.psychology_outlined,
                      message: 'Dean is still learning about you.',
                      subtext:
                          'Start a voice session or run an analysis to build your memory profile.',
                    )
                  : _TimelineList(entries: entries),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Category filter chips ─────────────────────────────────────────────────────

class _CategoryFilterBar extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onSelect;

  const _CategoryFilterBar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final chips = ['all', 'trade_history', 'risk_profile', 'watchlist_patterns',
                   'preference', 'learning', 'portfolio', 'conversation', 'event'];

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final key      = chips[i];
          final meta     = _meta(key);
          final isActive = (key == 'all' && selected == null) ||
              (key != 'all' && selected == key);

          return GestureDetector(
            onTap: () => onSelect(key == 'all' ? null : key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? meta.color.withValues(alpha: 0.20)
                    : const Color(0xFF111925),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive ? meta.color : Colors.white12,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(meta.icon,
                      size: 13,
                      color: isActive ? meta.color : Colors.white38),
                  const SizedBox(width: 5),
                  Text(
                    meta.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isActive
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: isActive ? meta.color : Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Timeline list ─────────────────────────────────────────────────────────────

class _TimelineList extends ConsumerWidget {
  final List<MemoryTimelineEntry> entries;
  const _TimelineList({required this.entries});

  static final _dateFormat = DateFormat('d MMM yyyy, HH:mm');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        return _MemoryEntryCard(
          entry: entry,
          dateFormat: _dateFormat,
          onDelete: () => _confirmDelete(context, ref, entry),
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    MemoryTimelineEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111925),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove memory?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text(
          'Dean won\'t remember this anymore:\n\n"${entry.text.length > 100 ? '${entry.text.substring(0, 100)}…' : entry.text}"',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Remove', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final ok = await ref.read(memoryDeleteProvider.notifier).delete(entry.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'Memory removed.' : 'Could not remove memory.'),
            backgroundColor: ok ? const Color(0xFF12A28C) : Colors.redAccent,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}

// ── Individual memory card ────────────────────────────────────────────────────

class _MemoryEntryCard extends StatelessWidget {
  final MemoryTimelineEntry entry;
  final DateFormat dateFormat;
  final VoidCallback onDelete;

  const _MemoryEntryCard({
    required this.entry,
    required this.dateFormat,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final meta = _meta(entry.category);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: Key(entry.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async {
          onDelete();
          // Return false — let the delete notifier handle list refresh
          // rather than removing the item optimistically from Dismissible.
          return false;
        },
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.delete_outline, color: Colors.redAccent),
        ),
        child: GlassCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: meta.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(meta.icon, size: 17, color: meta.color),
              ),
              const SizedBox(width: 12),
              // Text block
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category chip + optional symbol
                    Row(
                      children: [
                        _Chip(label: entry.categoryLabel, color: meta.color),
                        if (entry.symbol != null) ...[
                          const SizedBox(width: 6),
                          _Chip(label: entry.symbol!, color: Colors.white24),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Memory text
                    Text(
                      entry.text,
                      style: const TextStyle(
                          color: Color(0xDEFFFFFF), fontSize: 13, height: 1.45),
                    ),
                    const SizedBox(height: 6),
                    // Timestamp
                    Text(
                      dateFormat.format(entry.dateTime.toLocal()),
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              // Delete button
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Colors.white24),
                tooltip: 'Remove memory',
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Small chip ────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String subtext;

  const _EmptyState({
    required this.icon,
    required this.message,
    required this.subtext,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.white12),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              subtext,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
