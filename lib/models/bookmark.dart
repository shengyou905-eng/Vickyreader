class Bookmark {
  final String id;
  final String userId;
  final String bookId;
  final String chapterIndex;
  final String chapterTitle;
  final String snippet;
  final double scrollOffset;
  final double progress;
  final DateTime createdAt;
  final String updatedAt;
  final String bmobId;

  Bookmark({
    required this.id,
    this.userId = '',
    required this.bookId,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.snippet,
    required this.scrollOffset,
    required this.progress,
    required this.createdAt,
    this.updatedAt = '',
    this.bmobId = '',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'user_id': userId,
    'bookId': bookId,
    'chapterIndex': chapterIndex,
    'chapterTitle': chapterTitle,
    'snippet': snippet,
    'scrollOffset': scrollOffset,
    'progress': progress,
    'createdAt': createdAt.toIso8601String(),
    'updated_at': updatedAt,
    'bmob_id': bmobId,
  };

  factory Bookmark.fromMap(Map<String, dynamic> m) => Bookmark(
    id: m['id'] as String,
    userId: (m['user_id'] as String?) ?? '',
    bookId: m['bookId'] as String,
    chapterIndex: m['chapterIndex'] as String,
    chapterTitle: m['chapterTitle'] as String,
    snippet: m['snippet'] as String,
    scrollOffset: (m['scrollOffset'] as num?)?.toDouble() ?? 0.0,
    progress: (m['progress'] as num?)?.toDouble() ?? 0.0,
    createdAt: DateTime.parse(m['createdAt'] as String),
    updatedAt: (m['updated_at'] as String?) ?? '',
    bmobId: (m['bmob_id'] as String?) ?? '',
  );
}
