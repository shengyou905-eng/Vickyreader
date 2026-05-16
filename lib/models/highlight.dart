class Highlight {
  final String id;
  final String userId;
  final String bookId;
  final String chapterIndex;
  final String selectedText;
  final String contextBefore;
  final String contextAfter;
  final int startOffset;
  final int endOffset;
  final String color; // hex color
  final String? note;
  final DateTime createdAt;
  final String updatedAt;

  Highlight({
    required this.id,
    this.userId = '',
    required this.bookId,
    required this.chapterIndex,
    required this.selectedText,
    required this.contextBefore,
    required this.contextAfter,
    required this.startOffset,
    required this.endOffset,
    this.color = '#B39DDB',
    this.note,
    required this.createdAt,
    this.updatedAt = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'bookId': bookId,
      'chapterIndex': chapterIndex,
      'selectedText': selectedText,
      'contextBefore': contextBefore,
      'contextAfter': contextAfter,
      'startOffset': startOffset,
      'endOffset': endOffset,
      'color': color,
      'note': note,
      'createdAt': createdAt.toIso8601String(),
      'updated_at': updatedAt,
    };
  }

  factory Highlight.fromMap(Map<String, dynamic> map) {
    return Highlight(
      id: map['id'] as String,
      userId: (map['user_id'] as String?) ?? '',
      bookId: map['bookId'] as String,
      chapterIndex: map['chapterIndex'] as String,
      selectedText: map['selectedText'] as String,
      contextBefore: map['contextBefore'] as String,
      contextAfter: map['contextAfter'] as String,
      startOffset: (map['startOffset'] as num?)?.toInt() ?? 0,
      endOffset: (map['endOffset'] as num?)?.toInt() ?? 0,
      color: map['color'] as String? ?? '#B39DDB',
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: (map['updated_at'] as String?) ?? '',
    );
  }
}
