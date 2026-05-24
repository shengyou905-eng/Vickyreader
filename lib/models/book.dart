class Book {
  final String id;
  final String userId;
  final String title;
  final String author;
  final String? coverPath;
  final String filePath;
  final String format; // 'epub', 'txt', 'pdf', 'public'
  final String? description;
  final DateTime addedAt;
  final DateTime lastOpenedAt;
  double readingProgress; // 0.0 to 1.0
  final List<String> chapterTitles;
  final String updatedAt;

  Book({
    required this.id,
    this.userId = '',
    required this.title,
    required this.author,
    this.coverPath,
    required this.filePath,
    this.format = 'epub',
    this.description,
    required this.addedAt,
    required this.lastOpenedAt,
    this.readingProgress = 0.0,
    this.chapterTitles = const [],
    this.updatedAt = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'author': author,
      'coverPath': coverPath,
      'filePath': filePath,
      'format': format,
      'description': description,
      'addedAt': addedAt.toIso8601String(),
      'lastOpenedAt': lastOpenedAt.toIso8601String(),
      'readingProgress': readingProgress,
      'chapterTitles': chapterTitles.join('\t'),
      'updated_at': updatedAt,
    };
  }

  factory Book.fromMap(Map<String, dynamic> map) {
    final rawTitles = (map['chapterTitles'] as String?) ?? '';
    final filePath = map['filePath'] as String;
    return Book(
      id: map['id'] as String,
      userId: (map['user_id'] as String?) ?? '',
      title: _safeTitle((map['title'] as String?) ?? '', filePath),
      author: _safeAuthor((map['author'] as String?) ?? ''),
      coverPath: map['coverPath'] as String?,
      filePath: filePath,
      format: (map['format'] as String?) ?? 'epub',
      description: map['description'] as String?,
      addedAt: DateTime.parse(map['addedAt'] as String),
      lastOpenedAt: DateTime.parse(map['lastOpenedAt'] as String),
      readingProgress: (map['readingProgress'] as num?)?.toDouble() ?? 0.0,
      chapterTitles: rawTitles.isEmpty ? [] : rawTitles.split('\t'),
      updatedAt: (map['updated_at'] as String?) ?? '',
    );
  }

  static String _safeTitle(String value, String filePath) {
    final trimmed = value.trim();
    final lower = trimmed.toLowerCase();
    if (trimmed.isNotEmpty &&
        lower != 'unknown title' &&
        trimmed != '未知书名') {
      return trimmed;
    }
    final pathParts = filePath
        .split(RegExp(r'[\\/]'))
        .where((part) => part.isNotEmpty)
        .toList();
    final fileName = pathParts.isNotEmpty ? pathParts.last : '';
    final dot = fileName.lastIndexOf('.');
    final name = dot > 0 ? fileName.substring(0, dot) : fileName;
    return name.trim().isNotEmpty ? name.trim() : '未命名文档';
  }

  static String _safeAuthor(String value) {
    final trimmed = value.trim();
    final lower = trimmed.toLowerCase();
    if (trimmed.isEmpty ||
        lower == 'unknown author' ||
        trimmed == '未知作者') {
      return '佚名';
    }
    return trimmed;
  }

  Book copyWith({
    String? id,
    String? userId,
    String? title,
    String? author,
    String? coverPath,
    String? filePath,
    String? format,
    String? description,
    DateTime? addedAt,
    DateTime? lastOpenedAt,
    double? readingProgress,
    List<String>? chapterTitles,
    String? updatedAt,
  }) {
    return Book(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      author: author ?? this.author,
      coverPath: coverPath ?? this.coverPath,
      filePath: filePath ?? this.filePath,
      format: format ?? this.format,
      description: description ?? this.description,
      addedAt: addedAt ?? this.addedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      readingProgress: readingProgress ?? this.readingProgress,
      chapterTitles: chapterTitles ?? this.chapterTitles,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
