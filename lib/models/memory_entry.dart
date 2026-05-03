/// MemoryTimelineEntry — one ChromaDB memory entry returned by
/// GET /api/voice/memory/timeline.
///
/// Phase 4 — Deep Memory System.
library;

class MemoryTimelineEntry {
  final String id;
  final String text;
  final String category;
  final int timestamp; // Unix epoch seconds
  final String? symbol;

  const MemoryTimelineEntry({
    required this.id,
    required this.text,
    required this.category,
    required this.timestamp,
    this.symbol,
  });

  factory MemoryTimelineEntry.fromJson(Map<String, dynamic> json) {
    return MemoryTimelineEntry(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      category: json['category'] as String? ?? 'event',
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      symbol: json['symbol'] as String?,
    );
  }

  DateTime get dateTime =>
      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);

  /// Human-readable category label for display.
  String get categoryLabel => switch (category) {
        'trade_history'    => 'Trade History',
        'risk_profile'     => 'Risk Profile',
        'watchlist_patterns' => 'Watchlist',
        'preference'       => 'Preferences',
        'portfolio'        => 'Portfolio',
        'learning'         => 'Learning',
        'conversation'     => 'Conversation',
        'event'            => 'Event',
        _                  => category,
      };
}

class MemoryTimelineResponse {
  final List<MemoryTimelineEntry> entries;
  final int total;

  const MemoryTimelineResponse({required this.entries, required this.total});

  factory MemoryTimelineResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['entries'] as List<dynamic>? ?? [];
    return MemoryTimelineResponse(
      entries: raw
          .map((e) => MemoryTimelineEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }
}
