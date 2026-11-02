import 'dart:convert';
import 'user_entry.dart';

/// Immutable evidence, kept outside the rolling dialogue window.
class ReadingAiContext {
  final Map<String, String> _fields;
  ReadingAiContext(Map<String, String> fields)
    : _fields = Map.unmodifiable(fields);

  Map<String, String> toJson() => Map.of(_fields);
  String get path => _fields.containsKey('scope')
      ? '/api/ai/reader-question'
      : '/api/ai/explain';

  ReadingAiContext withAnswer(String answer) =>
      ReadingAiContext({..._fields, 'initialAnswer': answer});

  factory ReadingAiContext.fromEntry(UserEntry entry) {
    Map<String, dynamic> metadata = {};
    try {
      final value = jsonDecode(entry.metadataJson);
      if (value is Map<String, dynamic>) metadata = value;
    } on FormatException {
      /* Old entries may have no metadata. */
    }
    final stored = metadata['reading_ai_context'];
    return ReadingAiContext({
      if (stored is Map)
        for (final key in const [
          'contextBefore',
          'contextAfter',
          'paragraph',
          'scope',
          'pageText',
          'chapterText',
        ])
          if (stored[key] is String) key: stored[key] as String,
      'selectedText': stored is Map && stored['selectedText'] is String
          ? stored['selectedText'] as String
          : entry.originalText,
      'bookTitle': entry.bookTitle,
      'bookAuthor': metadata['book_author'] is String
          ? metadata['book_author'] as String
          : '',
      'chapterTitle': entry.chapterTitle,
      'mode': metadata['explain_mode'] is String
          ? metadata['explain_mode'] as String
          : 'auto',
      'initialQuestion': entry.userInput,
      'initialAnswer': entry.aiExplanation,
    });
  }
}
