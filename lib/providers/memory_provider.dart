/// Riverpod providers for the Phase 4 Deep Memory System.
///
/// memoryTimelineProvider  — loads & caches the ChromaDB timeline.
/// memoryServiceProvider   — singleton MemoryService instance.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/memory_entry.dart';
import '../services/memory_service.dart';

// ── Singleton service ────────────────────────────────────────────────────────

final memoryServiceProvider = Provider<MemoryService>((_) => MemoryService());

// ── Timeline provider ─────────────────────────────────────────────────────────
//
// FutureProvider.family so the caller can pass an optional category filter.
// Pass null to fetch all categories.

final memoryTimelineProvider =
    FutureProvider.family<List<MemoryTimelineEntry>, String?>(
  (ref, category) async {
    final svc = ref.watch(memoryServiceProvider);
    return svc.getTimeline(category: category);
  },
);

// ── Delete notifier ───────────────────────────────────────────────────────────
//
// Stateful notifier that:
//   1. Calls MemoryService.deleteEntry(docId)
//   2. On success, invalidates memoryTimelineProvider so the list refreshes.

class MemoryDeleteNotifier extends StateNotifier<AsyncValue<void>> {
  MemoryDeleteNotifier(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  Future<bool> delete(String docId) async {
    state = const AsyncLoading();
    try {
      final svc = _ref.read(memoryServiceProvider);
      final ok = await svc.deleteEntry(docId);
      state = const AsyncData(null);
      if (ok) {
        // Invalidate all category variants so every open timeline refreshes.
        _ref.invalidate(memoryTimelineProvider);
      }
      return ok;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

final memoryDeleteProvider =
    StateNotifierProvider<MemoryDeleteNotifier, AsyncValue<void>>(
  (ref) => MemoryDeleteNotifier(ref),
);
