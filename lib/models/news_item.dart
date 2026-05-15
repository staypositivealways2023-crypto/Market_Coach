class NewsItem {
  final String title;
  final String source;
  final String timeAgo;
  final String summary;
  final String sentiment; // e.g., Bullish, Bearish, Neutral

  const NewsItem({
    required this.title,
    required this.source,
    required this.timeAgo,
    required this.summary,
    required this.sentiment,
  });
}
