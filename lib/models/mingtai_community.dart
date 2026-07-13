class CommunityBook {
  final String id;
  final String title;
  final String author;
  final String translator;
  final String publisher;
  final String publicationYear;
  final String language;
  final String editionLabel;
  final String isbn;
  final String coverUrl;
  final String description;
  final bool canRead;
  final int wantCount;
  final int readingCount;
  final int finishedCount;
  final int postCount;
  final String viewerStatus;

  const CommunityBook({
    required this.id,
    required this.title,
    required this.author,
    this.translator = '',
    this.publisher = '',
    this.publicationYear = '',
    this.language = '',
    this.editionLabel = '',
    this.isbn = '',
    required this.coverUrl,
    required this.description,
    required this.canRead,
    required this.wantCount,
    required this.readingCount,
    required this.finishedCount,
    required this.postCount,
    required this.viewerStatus,
  });

  factory CommunityBook.fromJson(Map<String, dynamic> json) {
    return CommunityBook(
      id: _text(json['id']),
      title: _text(json['title'], fallback: '未命名书籍'),
      author: _text(json['author'], fallback: '佚名'),
      translator: _text(json['translator']),
      publisher: _text(json['publisher']),
      publicationYear: _text(json['publication_year']),
      language: _text(json['language']),
      editionLabel: _text(json['edition_label']),
      isbn: _text(json['isbn']),
      coverUrl: _text(json['cover_url']),
      description: _text(json['description']),
      canRead: _bool(json['can_read']),
      wantCount: _int(json['want_count']),
      readingCount: _int(json['reading_count']),
      finishedCount: _int(json['finished_count']),
      postCount: _int(json['post_count']),
      viewerStatus: _text(json['viewer_status']),
    );
  }
}

class CommunityPost {
  final String id;
  final String userId;
  final String bookId;
  final String postType;
  final String content;
  final String quotedText;
  final String chapterLabel;
  final String readingPosition;
  final double? readingProgress;
  final String source;
  final String sourceEntryId;
  final List<String> topicTags;
  final String bookTitle;
  final String bookAuthor;
  final String bookCoverUrl;
  final String nickname;
  final String avatarUrl;
  final int commentCount;
  final int resonanceCount;
  final bool viewerResonated;
  final int favoriteCount;
  final bool viewerFavorited;
  final DateTime? createdAt;

  const CommunityPost({
    required this.id,
    required this.userId,
    required this.bookId,
    required this.postType,
    required this.content,
    required this.quotedText,
    required this.chapterLabel,
    this.readingPosition = '',
    this.readingProgress,
    this.source = 'mingtai',
    this.sourceEntryId = '',
    this.topicTags = const [],
    required this.bookTitle,
    required this.bookAuthor,
    required this.bookCoverUrl,
    required this.nickname,
    required this.avatarUrl,
    required this.commentCount,
    required this.resonanceCount,
    required this.viewerResonated,
    this.favoriteCount = 0,
    this.viewerFavorited = false,
    required this.createdAt,
  });

  factory CommunityPost.fromJson(Map<String, dynamic> json) {
    return CommunityPost(
      id: _text(json['id']),
      userId: _text(json['user_id']),
      bookId: _text(json['book_id']),
      postType: _text(json['post_type'], fallback: 'thought'),
      content: _text(json['content']),
      quotedText: _text(json['quoted_text']),
      chapterLabel: _text(json['chapter_label']),
      readingPosition: _text(json['reading_position']),
      readingProgress: _doubleOrNull(json['reading_progress']),
      source: _text(json['source'], fallback: 'mingtai'),
      sourceEntryId: _text(json['source_entry_id']),
      topicTags: (json['topic_tags'] as List? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      bookTitle: _text(json['book_title'], fallback: '未命名书籍'),
      bookAuthor: _text(json['book_author'], fallback: '佚名'),
      bookCoverUrl: _text(json['book_cover_url']),
      nickname: _text(json['nickname'], fallback: '读者'),
      avatarUrl: _text(json['avatar_url']),
      commentCount: _int(json['comment_count']),
      resonanceCount: _int(json['resonance_count']),
      viewerResonated: _bool(json['viewer_resonated']),
      favoriteCount: _int(json['favorite_count']),
      viewerFavorited: _bool(json['viewer_favorited']),
      createdAt: DateTime.tryParse(_text(json['created_at']))?.toLocal(),
    );
  }

  CommunityPost copyWith({
    int? resonanceCount,
    bool? viewerResonated,
    int? commentCount,
    int? favoriteCount,
    bool? viewerFavorited,
  }) {
    return CommunityPost(
      id: id,
      userId: userId,
      bookId: bookId,
      postType: postType,
      content: content,
      quotedText: quotedText,
      chapterLabel: chapterLabel,
      readingPosition: readingPosition,
      readingProgress: readingProgress,
      source: source,
      sourceEntryId: sourceEntryId,
      topicTags: topicTags,
      bookTitle: bookTitle,
      bookAuthor: bookAuthor,
      bookCoverUrl: bookCoverUrl,
      nickname: nickname,
      avatarUrl: avatarUrl,
      commentCount: commentCount ?? this.commentCount,
      resonanceCount: resonanceCount ?? this.resonanceCount,
      viewerResonated: viewerResonated ?? this.viewerResonated,
      favoriteCount: favoriteCount ?? this.favoriteCount,
      viewerFavorited: viewerFavorited ?? this.viewerFavorited,
      createdAt: createdAt,
    );
  }
}

class CommunityReader {
  final String userId;
  final String nickname;
  final String avatarUrl;
  final String bio;
  final String status;

  const CommunityReader({
    required this.userId,
    required this.nickname,
    required this.avatarUrl,
    required this.bio,
    required this.status,
  });

  factory CommunityReader.fromJson(Map<String, dynamic> json) {
    return CommunityReader(
      userId: _text(json['user_id']),
      nickname: _text(json['nickname'], fallback: '读者'),
      avatarUrl: _text(json['avatar_url']),
      bio: _text(json['bio']),
      status: _text(json['status']),
    );
  }
}

class CommunityComment {
  final String id;
  final String userId;
  final String nickname;
  final String avatarUrl;
  final String content;
  final String quotedText;
  final String parentReplyId;
  final DateTime? createdAt;

  const CommunityComment({
    required this.id,
    required this.userId,
    required this.nickname,
    required this.avatarUrl,
    required this.content,
    this.quotedText = '',
    this.parentReplyId = '',
    required this.createdAt,
  });

  factory CommunityComment.fromJson(Map<String, dynamic> json) {
    return CommunityComment(
      id: _text(json['id']),
      userId: _text(json['user_id']),
      nickname: _text(json['nickname'], fallback: '读者'),
      avatarUrl: _text(json['avatar_url']),
      content: _text(json['content']),
      quotedText: _text(json['quoted_text']),
      parentReplyId: _text(json['parent_reply_id']),
      createdAt: DateTime.tryParse(_text(json['created_at']))?.toLocal(),
    );
  }
}

class CommunityProfileData {
  final String userId;
  final String nickname;
  final String avatarUrl;
  final String bio;
  final int followerCount;
  final int followingCount;
  final bool viewerFollowing;
  final List<CommunityBook> wantToRead;
  final List<CommunityBook> reading;
  final List<CommunityBook> finished;
  final List<CommunityPost> posts;
  final List<CommunityPost> favorites;

  const CommunityProfileData({
    required this.userId,
    required this.nickname,
    required this.avatarUrl,
    required this.bio,
    required this.followerCount,
    required this.followingCount,
    required this.viewerFollowing,
    required this.wantToRead,
    required this.reading,
    required this.finished,
    required this.posts,
    this.favorites = const [],
  });

  factory CommunityProfileData.fromJson(Map<String, dynamic> json) {
    final profile = Map<String, dynamic>.from(json['profile'] ?? const {});
    final books = (json['books'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    List<CommunityBook> booksFor(String status) => books
        .where((item) => _text(item['status']) == status)
        .map(CommunityBook.fromJson)
        .toList(growable: false);
    return CommunityProfileData(
      userId: _text(profile['user_id']),
      nickname: _text(profile['nickname'], fallback: '读者'),
      avatarUrl: _text(profile['avatar_url']),
      bio: _text(profile['bio']),
      followerCount: _int(profile['follower_count']),
      followingCount: _int(profile['following_count']),
      viewerFollowing: _bool(profile['viewer_following']),
      wantToRead: booksFor('want_to_read'),
      reading: booksFor('reading'),
      finished: booksFor('finished'),
      posts: (json['posts'] as List? ?? const [])
          .map(
            (item) =>
                CommunityPost.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false),
      favorites: (json['favorites'] as List? ?? const [])
          .map(
            (item) =>
                CommunityPost.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false),
    );
  }
}

class CommunityNotification {
  final String id;
  final String actorNickname;
  final String actorAvatarUrl;
  final String eventType;
  final String preview;
  final String bookTitle;
  final String postId;
  final String bookId;
  final DateTime? createdAt;
  final bool unread;

  const CommunityNotification({
    required this.id,
    required this.actorNickname,
    required this.actorAvatarUrl,
    required this.eventType,
    required this.preview,
    required this.bookTitle,
    required this.postId,
    required this.bookId,
    required this.createdAt,
    required this.unread,
  });

  factory CommunityNotification.fromJson(Map<String, dynamic> json) {
    return CommunityNotification(
      id: _text(json['id']),
      actorNickname: _text(json['actor_nickname'], fallback: '一位读者'),
      actorAvatarUrl: _text(json['actor_avatar_url']),
      eventType: _text(json['event_type']),
      preview: _text(json['preview']),
      bookTitle: _text(json['book_title']),
      postId: _text(json['post_id']),
      bookId: _text(json['book_id']),
      createdAt: DateTime.tryParse(_text(json['created_at']))?.toLocal(),
      unread: _text(json['read_at']).isEmpty,
    );
  }
}

String _text(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

int _int(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;

bool _bool(dynamic value) =>
    value == true || value?.toString().toLowerCase() == 'true';

double? _doubleOrNull(dynamic value) =>
    value == null ? null : double.tryParse(value.toString());
