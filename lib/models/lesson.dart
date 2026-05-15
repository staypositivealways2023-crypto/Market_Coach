import 'package:cloud_firestore/cloud_firestore.dart';

class Lesson {
  final String id;
  final String title;
  final String subtitle;
  final int minutes;
  final String level;
  final String body;
  final String? type;
  final DateTime? publishedAt;

  const Lesson({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.minutes,
    required this.level,
    required this.body,
    this.type,
    this.publishedAt,
  });

  factory Lesson.fromMap(Map<String, dynamic> map, String documentId) {
    return Lesson(
      id: documentId,
      title: map['title'] as String? ?? '',
      subtitle: map['subtitle'] as String? ?? '',
      minutes: map['minutes'] as int? ?? 0,
      level: map['level'] as String? ?? '',
      body: map['body'] as String? ?? '',
      type: map['type'] as String?,
      publishedAt: _parseDateTime(map['published_at']),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
