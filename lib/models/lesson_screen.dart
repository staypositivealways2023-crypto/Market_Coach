class LessonScreen {
  final String id;
  final String type;
  final String? title;
  final String? subtitle;
  final int order;
  final Map<String, dynamic> content;

  const LessonScreen({
    required this.id,
    required this.type,
    this.title,
    this.subtitle,
    required this.order,
    required this.content,
  });

  factory LessonScreen.fromMap(Map<String, dynamic> map, String documentId) {
    final rawContent = map['content'];
    final content = rawContent is Map
        ? Map<String, dynamic>.from(rawContent)
        : <String, dynamic>{};
    return LessonScreen(
      id: documentId,
      type: map['type'] as String? ?? 'text',
      title: map['title'] as String?,
      subtitle: map['subtitle'] as String?,
      order: (map['order'] as int?) ?? 0,
      content: content,
    );
  }
}
