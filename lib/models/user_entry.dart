import 'dart:convert';

class UserEntry {
  final String id;
  final String userId;
  final String source;
  final String bookId;
  final String bookTitle;
  final String chapterIndex;
  final String chapterTitle;
  final String originalText;
  final String userInput;
  final String aiExplanation;
  final List<String> autoTags;
  final String autoSummary;
  final String metadataJson;
  final String embedding;
  final DateTime createdAt;
  final String updatedAt;
  final String bmobId;

  UserEntry({
    required this.id,
    this.userId = '',
    required this.source,
    this.bookId = '',
    this.bookTitle = '',
    this.chapterIndex = '',
    this.chapterTitle = '',
    this.originalText = '',
    this.userInput = '',
    this.aiExplanation = '',
    this.autoTags = const [],
    this.autoSummary = '',
    this.metadataJson = '',
    this.embedding = '',
    required this.createdAt,
    this.updatedAt = '',
    this.bmobId = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'source': source,
      'book_id': bookId,
      'book_title': bookTitle,
      'chapter_index': chapterIndex,
      'chapter_title': chapterTitle,
      'original_text': originalText,
      'user_input': userInput,
      'ai_explanation': aiExplanation,
      'auto_tags': jsonEncode(autoTags),
      'auto_summary': autoSummary,
      'metadata_json': metadataJson,
      'embedding': embedding,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt,
      'bmob_id': bmobId,
    };
  }

  factory UserEntry.fromMap(Map<String, dynamic> map) {
    return UserEntry(
      id: map['id'] as String,
      userId: (map['user_id'] as String?) ?? '',
      source: (map['source'] as String?) ?? 'manual',
      bookId: (map['book_id'] as String?) ?? '',
      bookTitle: (map['book_title'] as String?) ?? '',
      chapterIndex: (map['chapter_index'] as String?) ?? '',
      chapterTitle: (map['chapter_title'] as String?) ?? '',
      originalText: (map['original_text'] as String?) ?? '',
      userInput: (map['user_input'] as String?) ?? '',
      aiExplanation: (map['ai_explanation'] as String?) ?? '',
      autoTags: _parseTags((map['auto_tags'] as String?) ?? ''),
      autoSummary: (map['auto_summary'] as String?) ?? '',
      metadataJson: (map['metadata_json'] as String?) ?? '',
      embedding: (map['embedding'] as String?) ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: (map['updated_at'] as String?) ?? '',
      bmobId: (map['bmob_id'] as String?) ?? '',
    );
  }

  static List<String> _parseTags(String raw) {
    if (raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      }
    } catch (_) {}
    return raw
        .split(',')
        .map((tag) => tag.trim().replaceAll('"', '').replaceAll('[', '').replaceAll(']', ''))
        .where((tag) => tag.isNotEmpty)
        .toList();
  }
}
