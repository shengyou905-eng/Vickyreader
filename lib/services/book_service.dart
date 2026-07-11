import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../config/constants.dart';
import '../models/book.dart';
import '../models/bookmark.dart';
import '../models/highlight.dart';
import '../models/ai_conversation.dart';
import '../models/user_entry.dart';
import 'auth_service.dart';
import 'bmob_api.dart';
import 'database_service.dart';
import 'epub_service.dart';
import 'import_service.dart';
import 'pdf_service.dart';

class MingtaiOverview {
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> allItems;
  final List<String> tags;
  final Map<int, MingtaiInsight> insights;

  const MingtaiOverview({
    required this.items,
    required this.allItems,
    required this.tags,
    required this.insights,
  });

  MingtaiInsight insightFor(int days) {
    return insights[days] ?? MingtaiInsight.empty(days);
  }
}

class MingtaiInsight {
  final int days;
  final int entryCount;
  final List<String> topTags;
  final List<String> topBooks;
  final String topSource;
  final String summary;

  const MingtaiInsight({
    required this.days,
    required this.entryCount,
    required this.topTags,
    required this.topBooks,
    required this.topSource,
    required this.summary,
  });

  factory MingtaiInsight.empty(int days) {
    return MingtaiInsight(
      days: days,
      entryCount: 0,
      topTags: const [],
      topBooks: const [],
      topSource: '',
      summary: '',
    );
  }

  factory MingtaiInsight.fromRemote(int days, Map<String, dynamic> row) {
    return MingtaiInsight(
      days: int.tryParse(row['days']?.toString() ?? '') ?? days,
      entryCount: int.tryParse(row['entry_count']?.toString() ?? '') ?? 0,
      topTags: BookService._remoteTags(row['top_tags']),
      topBooks: BookService._remoteTags(row['top_books']),
      topSource: row['top_source']?.toString() ?? '',
      summary: row['summary']?.toString() ?? '',
    );
  }
}

class XiaouQuickQuestion {
  final String id;
  final String title;

  const XiaouQuickQuestion({required this.id, required this.title});

  factory XiaouQuickQuestion.fromRemote(Map<String, dynamic> row) {
    return XiaouQuickQuestion(
      id: row['id']?.toString() ?? '',
      title: row['title']?.toString() ?? '',
    );
  }
}

class XiaouHomeInsight {
  final Map<int, MingtaiInsight> recentFocus;
  final String weeklySummary;
  final List<String> longTermTopics;
  final List<XiaouQuickQuestion> quickQuestions;
  final List<Map<String, dynamic>> recentEntries;
  final String deepReflection;
  final int authorizedNoteCount;
  final DateTime? refreshedAt;

  const XiaouHomeInsight({
    required this.recentFocus,
    required this.weeklySummary,
    required this.longTermTopics,
    required this.quickQuestions,
    required this.recentEntries,
    required this.deepReflection,
    required this.authorizedNoteCount,
    this.refreshedAt,
  });

  factory XiaouHomeInsight.empty() {
    return XiaouHomeInsight(
      recentFocus: {7: MingtaiInsight.empty(7), 30: MingtaiInsight.empty(30)},
      weeklySummary: '',
      longTermTopics: const [],
      quickQuestions: const [],
      recentEntries: const [],
      deepReflection: '',
      authorizedNoteCount: 0,
    );
  }

  factory XiaouHomeInsight.fromRemote(Map<String, dynamic> row) {
    final focus = Map<String, dynamic>.from(row['recent_focus'] ?? {});
    final questions = (row['high_value_questions'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              XiaouQuickQuestion.fromRemote(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
        .toList();
    return XiaouHomeInsight(
      recentFocus: {
        7: MingtaiInsight.fromRemote(
          7,
          Map<String, dynamic>.from(focus['7'] ?? {}),
        ),
        30: MingtaiInsight.fromRemote(
          30,
          Map<String, dynamic>.from(focus['30'] ?? {}),
        ),
      },
      weeklySummary: row['weekly_summary']?.toString() ?? '',
      longTermTopics: BookService._remoteTags(row['long_term_topics']),
      quickQuestions: questions,
      recentEntries: (row['recent_entries'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
      deepReflection: row['deep_reflection']?.toString() ?? '',
      authorizedNoteCount:
          int.tryParse(row['authorized_note_count']?.toString() ?? '') ?? 0,
      refreshedAt: BookService._tryParseDate(row['refreshed_at']),
    );
  }

  String get activeDiscovery {
    final weekly = weeklySummary.trim();
    if (weekly.isNotEmpty) return weekly;
    return deepReflection.trim();
  }

  bool get hasActiveDiscovery => activeDiscovery.isNotEmpty;
}

class MingtaiPublicBook {
  final String id;
  final String uploaderUserId;
  final String sourceBookId;
  final String title;
  final String author;
  final String coverUrl;
  final String fileUrl;
  final String storagePath;
  final String fileType;
  final int fileSize;
  final int chapterCount;
  final String description;
  final String authoritativeDescription;
  final String authoritativeDescriptionSource;
  final String authoritativeDescriptionUrl;
  final String oneLineSummary;
  final String oneLineSummarySource;
  final String encounterSummary;
  final String expandedGuide;
  final List<String> readingThemes;
  final String copyrightStatus;
  final int borrowCount;
  final int readingCount;
  final int annotationCount;
  final int recentDiscussionCount;
  final DateTime? createdAt;

  const MingtaiPublicBook({
    required this.id,
    required this.uploaderUserId,
    required this.sourceBookId,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.fileUrl,
    required this.storagePath,
    required this.fileType,
    required this.fileSize,
    required this.chapterCount,
    required this.description,
    required this.authoritativeDescription,
    required this.authoritativeDescriptionSource,
    required this.authoritativeDescriptionUrl,
    required this.oneLineSummary,
    required this.oneLineSummarySource,
    required this.encounterSummary,
    required this.expandedGuide,
    required this.readingThemes,
    required this.copyrightStatus,
    required this.borrowCount,
    required this.readingCount,
    required this.annotationCount,
    required this.recentDiscussionCount,
    required this.createdAt,
  });

  factory MingtaiPublicBook.fromRemote(Map<String, dynamic> row) {
    final title = _safePublicTitle(row['title']?.toString() ?? '');
    final author = _safePublicAuthor(row['author']?.toString() ?? '');
    final fileUrl = (row['file_url']?.toString() ?? '').trim();
    final originalFileUrl = (row['original_file_url']?.toString() ?? '').trim();
    return MingtaiPublicBook(
      id: row['id']?.toString() ?? '',
      uploaderUserId:
          row['uploader_user_id']?.toString() ??
          row['publisher_user_id']?.toString() ??
          '',
      sourceBookId: row['source_book_id']?.toString() ?? '',
      title: title,
      author: author,
      coverUrl: row['cover_url']?.toString() ?? '',
      fileUrl: fileUrl.isNotEmpty ? fileUrl : originalFileUrl,
      storagePath: row['storage_path']?.toString() ?? '',
      fileType: _safeFileType(
        row['file_type']?.toString() ?? '',
        row['file_url']?.toString() ?? '',
      ),
      fileSize: int.tryParse(row['file_size']?.toString() ?? '') ?? 0,
      chapterCount: int.tryParse(row['chapter_count']?.toString() ?? '') ?? 0,
      description: row['description']?.toString() ?? '',
      authoritativeDescription:
          row['authoritative_description']?.toString() ?? '',
      authoritativeDescriptionSource:
          row['authoritative_description_source']?.toString() ?? '',
      authoritativeDescriptionUrl:
          row['authoritative_description_url']?.toString() ?? '',
      oneLineSummary: row['one_line_summary']?.toString() ?? '',
      oneLineSummarySource: row['one_line_summary_source']?.toString() ?? '',
      encounterSummary: row['encounter_summary']?.toString() ?? '',
      expandedGuide: row['expanded_guide']?.toString() ?? '',
      readingThemes: BookService._remoteTags(row['reading_themes']),
      copyrightStatus: row['copyright_status']?.toString() ?? '',
      borrowCount: int.tryParse(row['borrow_count']?.toString() ?? '') ?? 0,
      readingCount:
          int.tryParse(row['reading_count']?.toString() ?? '') ??
          int.tryParse(row['read_count']?.toString() ?? '') ??
          int.tryParse(row['borrow_count']?.toString() ?? '') ??
          0,
      annotationCount:
          int.tryParse(row['annotation_count']?.toString() ?? '') ?? 0,
      recentDiscussionCount:
          int.tryParse(row['recent_discussion_count']?.toString() ?? '') ?? 0,
      createdAt: BookService._tryParseDate(row['created_at']),
    );
  }

  static String _safePublicTitle(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        trimmed.toLowerCase() == 'unknown title' ||
        trimmed == '未知书名') {
      return '未命名文档';
    }
    return trimmed;
  }

  static String _safePublicAuthor(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        trimmed.toLowerCase() == 'unknown author' ||
        trimmed == '未知作者') {
      return '佚名';
    }
    return trimmed;
  }

  static String _safeFileType(String value, String fileUrl) {
    final type = value.trim().toLowerCase().replaceAll('.', '');
    if (type == 'epub' || type == 'txt' || type == 'pdf') return type;
    final uriPath = Uri.tryParse(fileUrl)?.path ?? fileUrl;
    final ext = p.extension(uriPath).toLowerCase().replaceAll('.', '');
    if (ext == 'epub' || ext == 'txt' || ext == 'pdf') return ext;
    return 'epub';
  }
}

class MingtaiBookDetail {
  final MingtaiPublicBook book;
  final List<MingtaiFeedItem> annotations;

  const MingtaiBookDetail({required this.book, required this.annotations});
}

class MingtaiPageMoment {
  final String id;
  final String publicBookId;
  final String source;
  final String text;
  final String annotationText;
  final String chapterIndex;
  final String chapterTitle;
  final String bookTitle;
  final String bookAuthor;
  final String bookCover;
  final String bookOneLineSummary;

  const MingtaiPageMoment({
    required this.id,
    required this.publicBookId,
    required this.source,
    required this.text,
    required this.annotationText,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.bookTitle,
    required this.bookAuthor,
    required this.bookCover,
    required this.bookOneLineSummary,
  });

  factory MingtaiPageMoment.fromRemote(Map<String, dynamic> row) {
    return MingtaiPageMoment(
      id: row['id']?.toString() ?? '',
      publicBookId: row['public_book_id']?.toString() ?? '',
      source: row['source']?.toString() ?? 'excerpt',
      text: row['text']?.toString() ?? '',
      annotationText: row['annotation_text']?.toString() ?? '',
      chapterIndex: row['chapter_index']?.toString() ?? '',
      chapterTitle: row['chapter_title']?.toString() ?? '',
      bookTitle: row['book_title']?.toString() ?? '未命名文档',
      bookAuthor: row['book_author']?.toString() ?? '佚名',
      bookCover: row['book_cover']?.toString() ?? '',
      bookOneLineSummary: row['book_one_line_summary']?.toString() ?? '',
    );
  }
}

class MingtaiDiscussionPreview {
  final MingtaiPublicBook book;
  final String excerpt;
  final String source;

  const MingtaiDiscussionPreview({
    required this.book,
    required this.excerpt,
    required this.source,
  });

  factory MingtaiDiscussionPreview.fromRemote(Map<String, dynamic> row) {
    return MingtaiDiscussionPreview(
      book: MingtaiPublicBook.fromRemote(
        Map<String, dynamic>.from(row['book'] ?? {}),
      ),
      excerpt: row['excerpt']?.toString() ?? '',
      source: row['source']?.toString() ?? '',
    );
  }
}

class MingtaiHomeData {
  final MingtaiPageMoment? todayPage;
  final List<MingtaiPageMoment> encounterPool;
  final List<MingtaiFeedItem> recentThoughts;
  final List<MingtaiDiscussionPreview> recentDiscussions;
  final List<MingtaiPublicBook> readingNow;
  final List<MingtaiPublicBook> latestBooks;

  const MingtaiHomeData({
    required this.todayPage,
    required this.encounterPool,
    required this.recentThoughts,
    required this.recentDiscussions,
    required this.readingNow,
    required this.latestBooks,
  });

  factory MingtaiHomeData.fromRemote(Map<String, dynamic> row) {
    final today = row['today_page'];
    return MingtaiHomeData(
      todayPage: today is Map
          ? MingtaiPageMoment.fromRemote(Map<String, dynamic>.from(today))
          : null,
      encounterPool: _remoteMaps(
        row['encounter_pool'],
      ).map(MingtaiPageMoment.fromRemote).toList(),
      recentThoughts: _remoteMaps(
        row['recent_thoughts'],
      ).map(MingtaiFeedItem.fromRemote).toList(),
      recentDiscussions: _remoteMaps(
        row['recent_discussions'],
      ).map(MingtaiDiscussionPreview.fromRemote).toList(),
      readingNow: _remoteMaps(
        row['reading_now'],
      ).map(MingtaiPublicBook.fromRemote).toList(),
      latestBooks: _remoteMaps(
        row['latest_books'],
      ).map(MingtaiPublicBook.fromRemote).toList(),
    );
  }

  static List<Map<String, dynamic>> _remoteMaps(Object? raw) {
    return (raw as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}

class MingtaiFeedItem {
  final String id;
  final String entryId;
  final String source;
  final String bookId;
  final String bookTitle;
  final String bookAuthor;
  final String bookCover;
  final String chapterIndex;
  final String chapterTitle;
  final String originalText;
  final String annotationText;
  final List<String> tags;
  final Map<String, dynamic> metadata;
  final int resonanceCount;
  final int commentCount;
  final DateTime? createdAt;

  const MingtaiFeedItem({
    required this.id,
    required this.entryId,
    required this.source,
    required this.bookId,
    required this.bookTitle,
    required this.bookAuthor,
    required this.bookCover,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.originalText,
    required this.annotationText,
    required this.tags,
    required this.metadata,
    required this.resonanceCount,
    required this.commentCount,
    required this.createdAt,
  });

  factory MingtaiFeedItem.fromRemote(Map<String, dynamic> row) {
    final metadata = BookService._metadataToRemote(row['metadata_json']);
    return MingtaiFeedItem(
      id: row['id']?.toString() ?? '',
      entryId: row['entry_id']?.toString() ?? '',
      source: row['source']?.toString() ?? 'manual',
      bookId: row['book_id']?.toString() ?? '',
      bookTitle: row['book_title']?.toString() ?? '未命名文档',
      bookAuthor:
          row['book_author']?.toString() ??
          metadata['book_author']?.toString() ??
          metadata['author']?.toString() ??
          '佚名',
      bookCover:
          row['book_cover']?.toString() ??
          metadata['book_cover']?.toString() ??
          metadata['cover_path']?.toString() ??
          '',
      chapterIndex: row['chapter_index']?.toString() ?? '',
      chapterTitle:
          row['chapter_title']?.toString() ??
          metadata['chapter_title']?.toString() ??
          '',
      originalText: row['original_text']?.toString() ?? '',
      annotationText: row['annotation_text']?.toString() ?? '',
      tags: BookService._remoteTags(row['auto_tags']),
      metadata: metadata,
      resonanceCount:
          int.tryParse(row['resonance_count']?.toString() ?? '') ?? 0,
      commentCount: int.tryParse(row['comment_count']?.toString() ?? '') ?? 0,
      createdAt: BookService._tryParseDate(row['created_at']),
    );
  }

  MingtaiFeedItem copyWithInteractionCounts({
    int? resonanceCount,
    int? commentCount,
  }) {
    return MingtaiFeedItem(
      id: id,
      entryId: entryId,
      source: source,
      bookId: bookId,
      bookTitle: bookTitle,
      bookAuthor: bookAuthor,
      bookCover: bookCover,
      chapterIndex: chapterIndex,
      chapterTitle: chapterTitle,
      originalText: originalText,
      annotationText: annotationText,
      tags: tags,
      metadata: metadata,
      resonanceCount: resonanceCount ?? this.resonanceCount,
      commentCount: commentCount ?? this.commentCount,
      createdAt: createdAt,
    );
  }
}

class MingtaiUserProfile {
  final String userId;
  final String nickname;
  final String avatarUrl;
  final String bio;

  const MingtaiUserProfile({
    required this.userId,
    required this.nickname,
    required this.avatarUrl,
    required this.bio,
  });

  factory MingtaiUserProfile.fromRemote(Map<String, dynamic> row) {
    final nickname = row['nickname']?.toString().trim() ?? '';
    return MingtaiUserProfile(
      userId: row['user_id']?.toString() ?? row['id']?.toString() ?? '',
      nickname: nickname.isEmpty ? '知读读者' : nickname,
      avatarUrl: row['avatar_url']?.toString() ?? '',
      bio: row['bio']?.toString() ?? '',
    );
  }
}

class MingtaiBookReview {
  final String id;
  final String publicBookId;
  final String bookTitle;
  final String bookAuthor;
  final String bookCover;
  final MingtaiUserProfile user;
  final String content;
  final int resonanceCount;
  final int commentCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const MingtaiBookReview({
    required this.id,
    required this.publicBookId,
    required this.bookTitle,
    required this.bookAuthor,
    required this.bookCover,
    required this.user,
    required this.content,
    required this.resonanceCount,
    required this.commentCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MingtaiBookReview.fromRemote(Map<String, dynamic> row) {
    return MingtaiBookReview(
      id: row['id']?.toString() ?? '',
      publicBookId: row['public_book_id']?.toString() ?? '',
      bookTitle: row['book_title']?.toString() ?? '',
      bookAuthor: row['book_author']?.toString() ?? '',
      bookCover: row['book_cover']?.toString() ?? '',
      user: MingtaiUserProfile.fromRemote(
        Map<String, dynamic>.from(row['user'] ?? {}),
      ),
      content: row['content']?.toString() ?? '',
      resonanceCount:
          int.tryParse(row['resonance_count']?.toString() ?? '') ?? 0,
      commentCount: int.tryParse(row['comment_count']?.toString() ?? '') ?? 0,
      createdAt: BookService._tryParseDate(row['created_at']),
      updatedAt: BookService._tryParseDate(row['updated_at']),
    );
  }

  MingtaiBookReview copyWithInteractionCounts({
    int? resonanceCount,
    int? commentCount,
  }) {
    return MingtaiBookReview(
      id: id,
      publicBookId: publicBookId,
      bookTitle: bookTitle,
      bookAuthor: bookAuthor,
      bookCover: bookCover,
      user: user,
      content: content,
      resonanceCount: resonanceCount ?? this.resonanceCount,
      commentCount: commentCount ?? this.commentCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class MingtaiInteractionComment {
  final String id;
  final String targetId;
  final String content;
  final MingtaiUserProfile user;
  final DateTime? createdAt;

  const MingtaiInteractionComment({
    required this.id,
    required this.targetId,
    required this.content,
    required this.user,
    required this.createdAt,
  });

  factory MingtaiInteractionComment.fromRemote(Map<String, dynamic> row) {
    return MingtaiInteractionComment(
      id: row['id']?.toString() ?? '',
      targetId: row['target_id']?.toString() ?? '',
      content: row['content']?.toString() ?? '',
      user: MingtaiUserProfile.fromRemote(
        Map<String, dynamic>.from(row['user'] ?? {}),
      ),
      createdAt: BookService._tryParseDate(row['created_at']),
    );
  }
}

class MingtaiNotification {
  final String id;
  final String eventType;
  final String targetType;
  final String targetId;
  final String publicBookId;
  final String bookTitle;
  final String bookAuthor;
  final String bookCover;
  final String preview;
  final MingtaiUserProfile actor;
  final DateTime? readAt;
  final DateTime? createdAt;

  const MingtaiNotification({
    required this.id,
    required this.eventType,
    required this.targetType,
    required this.targetId,
    required this.publicBookId,
    required this.bookTitle,
    required this.bookAuthor,
    required this.bookCover,
    required this.preview,
    required this.actor,
    required this.readAt,
    required this.createdAt,
  });

  bool get isRead => readAt != null;

  factory MingtaiNotification.fromRemote(Map<String, dynamic> row) {
    return MingtaiNotification(
      id: row['id']?.toString() ?? '',
      eventType: row['event_type']?.toString() ?? '',
      targetType: row['target_type']?.toString() ?? '',
      targetId: row['target_id']?.toString() ?? '',
      publicBookId: row['public_book_id']?.toString() ?? '',
      bookTitle: row['book_title']?.toString() ?? '',
      bookAuthor: row['book_author']?.toString() ?? '',
      bookCover: row['book_cover']?.toString() ?? '',
      preview: row['preview']?.toString() ?? '',
      actor: MingtaiUserProfile.fromRemote(
        Map<String, dynamic>.from(row['actor'] ?? {}),
      ),
      readAt: BookService._tryParseDate(row['read_at']),
      createdAt: BookService._tryParseDate(row['created_at']),
    );
  }
}

class MingtaiPublicProfile {
  final MingtaiUserProfile profile;
  final int publicBooks;
  final int publicThoughts;
  final int publicReviews;
  final int mingtaiStops;
  final List<MingtaiPublicBook> recentBooks;
  final List<MingtaiBookReview> reviews;
  final List<MingtaiFeedItem> annotations;

  const MingtaiPublicProfile({
    required this.profile,
    required this.publicBooks,
    required this.publicThoughts,
    required this.publicReviews,
    required this.mingtaiStops,
    required this.recentBooks,
    required this.reviews,
    required this.annotations,
  });

  factory MingtaiPublicProfile.fromRemote(Map<String, dynamic> row) {
    final stats = Map<String, dynamic>.from(row['stats'] ?? {});
    return MingtaiPublicProfile(
      profile: MingtaiUserProfile.fromRemote(
        Map<String, dynamic>.from(row['profile'] ?? {}),
      ),
      publicBooks: int.tryParse(stats['public_books']?.toString() ?? '') ?? 0,
      publicThoughts:
          int.tryParse(stats['public_thoughts']?.toString() ?? '') ?? 0,
      publicReviews:
          int.tryParse(stats['public_reviews']?.toString() ?? '') ?? 0,
      mingtaiStops: int.tryParse(stats['mingtai_stops']?.toString() ?? '') ?? 0,
      recentBooks: MingtaiHomeData._remoteMaps(
        row['recent_books'],
      ).map(MingtaiPublicBook.fromRemote).toList(),
      reviews: MingtaiHomeData._remoteMaps(
        row['reviews'],
      ).map(MingtaiBookReview.fromRemote).toList(),
      annotations: MingtaiHomeData._remoteMaps(
        row['annotations'],
      ).map(MingtaiFeedItem.fromRemote).toList(),
    );
  }
}

class BookService {
  static final Uuid _uuid = Uuid();
  static const String _freeNotesBackupKey = 'free_notes_local_backup_v1';
  static const String _xiaouHomeDiskCacheKey = 'xiaou_home_cache_v4';
  static const String _xiaouOverviewDiskCacheKey = 'xiaou_overview_cache_v4';
  static const String _mingtaiHomeDiskCacheKey = 'mingtai_home_cache_v1';
  static List<MingtaiPublicBook>? _mingtaiBooksCache;
  static DateTime? _mingtaiBooksCacheAt;
  static MingtaiHomeData? _mingtaiHomeCache;
  static DateTime? _mingtaiHomeCacheAt;
  static Future<MingtaiHomeData>? _mingtaiHomeInFlight;
  static final Map<String, MingtaiBookDetail> _mingtaiBookDetailCache = {};
  static final Map<String, DateTime> _mingtaiBookDetailCacheAt = {};
  static final Map<String, Future<String>> _publicBookDownloadTasks = {};
  static final Map<String, Future<String>> _mingtaiChapterContentTasks = {};
  static final Map<String, Future<void>> _mingtaiOpeningPrefetchTasks = {};
  static MingtaiOverview? _mingtaiOverviewCache;
  static DateTime? _mingtaiOverviewCacheAt;
  static Future<MingtaiOverview>? _mingtaiOverviewInFlight;
  static XiaouHomeInsight? _xiaouHomeInsightCache;
  static DateTime? _xiaouHomeInsightCacheAt;
  static Future<XiaouHomeInsight>? _xiaouHomeInsightInFlight;
  static const Duration _mingtaiBooksCacheTtl = Duration(seconds: 90);
  static const Duration _mingtaiBookDetailCacheTtl = Duration(seconds: 60);
  static const Duration _mingtaiOverviewCacheTtl = Duration(seconds: 60);
  static const Duration _xiaouHomeInsightCacheTtl = Duration(minutes: 2);

  static const Map<String, String> _sourceLabels = {
    'highlight': '划线',
    'thought': '想法',
    'ai_explanation': '小U解释',
    'manual': '手动',
  };

  static String mingtaiSourceLabel(String source) {
    return _sourceLabels[source] ?? source;
  }

  static List<String> mingtaiItemTags(Map<String, dynamic> item) {
    return _parseTags((item['ai_tags'] as String?) ?? '');
  }

  static DateTime? mingtaiItemCreatedAt(Map<String, dynamic> item) {
    return _tryParseDate(item['created_at']);
  }

  static bool isMingtaiTopicTag(String tag) {
    return _isInsightTag(tag);
  }

  // ---- Books ----

  static Future<List<Book>> getBooks() async {
    final db = await DatabaseService.database;
    final maps = await db.query('books', orderBy: 'lastOpenedAt DESC');
    return maps.map((m) => Book.fromMap(m)).toList();
  }

  static Future<Book?> getBook(String id) async {
    final db = await DatabaseService.database;
    final maps = await db.query('books', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Book.fromMap(maps.first);
  }

  static Future<void> insertBook(Book book) async {
    final db = await DatabaseService.database;
    await db.insert(
      'books',
      book.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> updateBook(Book book) async {
    final db = await DatabaseService.database;
    await db.update(
      'books',
      book.toMap(),
      where: 'id = ?',
      whereArgs: [book.id],
    );
  }

  static Future<void> deleteBook(String id) async {
    final db = await DatabaseService.database;
    await db.delete('books', where: 'id = ?', whereArgs: [id]);
    await db.delete('highlights', where: 'bookId = ?', whereArgs: [id]);
    await db.delete('notes', where: 'bookId = ?', whereArgs: [id]);
    await db.delete('ai_messages', where: 'bookId = ?', whereArgs: [id]);
    await db.delete('reading_progress', where: 'bookId = ?', whereArgs: [id]);
    await db.delete('bookmarks', where: 'bookId = ?', whereArgs: [id]);
    await db.delete('user_entries', where: 'book_id = ?', whereArgs: [id]);
  }

  // ---- Highlights ----

  static Future<List<Highlight>> getHighlights(String bookId) async {
    final db = await DatabaseService.database;
    final maps = await db.query(
      'highlights',
      where: 'bookId = ?',
      whereArgs: [bookId],
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => Highlight.fromMap(m)).toList();
  }

  static Future<List<Highlight>> getAllHighlights() async {
    final db = await DatabaseService.database;
    final maps = await db.query('highlights', orderBy: 'createdAt DESC');
    return maps.map((m) => Highlight.fromMap(m)).toList();
  }

  static Future<void> insertHighlight(Highlight h) async {
    final db = await DatabaseService.database;
    await db.insert(
      'highlights',
      h.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> updateHighlightNote(String id, String? note) async {
    final db = await DatabaseService.database;
    await db.update(
      'highlights',
      {'note': note},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> deleteHighlight(String id) async {
    final db = await DatabaseService.database;
    await db.delete('highlights', where: 'id = ?', whereArgs: [id]);
  }

  // ---- AI Messages ----

  static Future<List<AiMessage>> getAiMessages(
    String bookId, {
    int limit = 6,
  }) async {
    final db = await DatabaseService.database;
    final maps = await db.query(
      'ai_messages',
      where: 'bookId = ?',
      whereArgs: [bookId],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return maps.reversed.map((m) => AiMessage.fromMap(m)).toList();
  }

  static Future<void> insertAiMessage(String bookId, AiMessage msg) async {
    final db = await DatabaseService.database;
    await db.insert('ai_messages', {
      'id': msg.timestamp.microsecondsSinceEpoch.toString(),
      'bookId': bookId,
      'role': msg.role,
      'content': msg.content,
      'timestamp': msg.timestamp.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---- Reading Progress ----

  static Future<({String chapterIndex, double scrollOffset})?>
  getReadingProgress(String bookId) async {
    final db = await DatabaseService.database;

    final maps = await db.query(
      'reading_progress',
      where: 'bookId = ?',
      whereArgs: [bookId],
    );
    if (maps.isEmpty) return null;
    return (
      chapterIndex: maps.first['chapterIndex'] as String,
      scrollOffset: (maps.first['scrollOffset'] as num).toDouble(),
    );
  }

  static Future<({String chapterIndex, double scrollOffset})?>
  refreshRemoteReadingProgress(String bookId) async {
    final db = await DatabaseService.database;
    await _pullRemoteReadingProgressIfPossible(db, bookId);
    return getReadingProgress(bookId);
  }

  static Future<void> saveReadingProgress(
    String bookId,
    String chapterIndex,
    double scrollOffset, {
    String userId = '',
    String updatedAt = '',
  }) async {
    final db = await DatabaseService.database;
    final now = updatedAt.isNotEmpty
        ? updatedAt
        : DateTime.now().toUtc().toIso8601String();
    final chapter = int.tryParse(chapterIndex) ?? 0;
    final totalChapters = (await getBook(bookId))?.chapterTitles.length ?? 0;
    final progress = totalChapters > 0
        ? ((chapter + 1) / totalChapters).clamp(0.0, 1.0).toDouble()
        : 0.0;

    await db.insert('reading_progress', {
      'bookId': bookId,
      'user_id': userId,
      'chapterIndex': chapterIndex,
      'scrollOffset': scrollOffset,
      'updatedAt': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await _saveRemoteReadingProgressIfPossible(
      bookId: bookId,
      progress: progress,
      chapterIndex: chapterIndex,
      scrollOffset: scrollOffset,
    );
  }

  // ---- Notes ----

  static Future<List<Map<String, dynamic>>> getAllNotes() async {
    final db = await DatabaseService.database;
    return db.query('notes', orderBy: 'updatedAt DESC');
  }

  static Future<void> insertNote({
    required String id,
    required String bookId,
    String? chapterIndex,
    String? selectedText,
    String? chapterTitle,
    required String content,
    String userId = '',
  }) async {
    final db = await DatabaseService.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('notes', {
      'id': id,
      'user_id': userId,
      'bookId': bookId,
      'chapterIndex': chapterIndex,
      'selectedText': selectedText,
      'chapterTitle': chapterTitle,
      'content': content,
      'createdAt': now,
      'updatedAt': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> deleteNote(String id) async {
    final db = await DatabaseService.database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  // ---- Free Notes ----

  static Future<List<Map<String, dynamic>>> getFreeNotes({
    String? query,
  }) async {
    final db = await DatabaseService.database;
    await _ensureFreeNotesTable(db);
    await BmobApi.instance.init();
    await _restoreFreeNotesBackup(db);
    final q = query?.trim() ?? '';

    if (q.isEmpty) {
      var localNotes = await _queryFreeNotes(db);
      if (localNotes.isEmpty) {
        localNotes = await _claimAnonymousFreeNotes(db);
      }
      if (localNotes.isEmpty) {
        await _syncFreeNotesIfPossible(db);
        return _queryFreeNotes(db);
      }
      unawaited(_syncFreeNotesIfPossible(db));
      return localNotes;
    }

    var notes = await _queryFreeNotes(db, query: q);
    if (notes.isEmpty) {
      notes = await _claimAnonymousFreeNotes(db, query: q);
    }
    return notes;
  }

  static Future<void> syncFreeNotes() async {
    final db = await DatabaseService.database;
    await _ensureFreeNotesTable(db);
    await _restoreFreeNotesBackup(db);
    await _syncFreeNotesIfPossible(db);
  }

  static Future<void> saveFreeNote({
    String? id,
    String userId = '',
    String title = '',
    required String content,
    bool waitForRemote = false,
  }) async {
    final db = await DatabaseService.database;
    await _ensureFreeNotesTable(db);
    final now = DateTime.now().toUtc().toIso8601String();
    final noteId = id?.trim().isNotEmpty == true ? id!.trim() : _uuid.v4();
    final resolvedUserId = userId.trim().isNotEmpty
        ? userId.trim()
        : _currentFreeNotesUserId();

    final existing = await db.query(
      'free_notes',
      columns: ['created_at', 'xiaou_authorized'],
      where: 'id = ?',
      whereArgs: [noteId],
      limit: 1,
    );
    final createdAt = existing.isEmpty
        ? now
        : existing.first['created_at']?.toString() ?? now;
    final xiaouAuthorized =
        existing.isNotEmpty && existing.first['xiaou_authorized'] == 1 ? 1 : 0;

    await db.insert('free_notes', {
      'id': noteId,
      'user_id': resolvedUserId,
      'title': title.trim(),
      'content': content,
      'xiaou_authorized': xiaouAuthorized,
      'created_at': createdAt,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _backupFreeNotes(db);
    final remoteSync = _upsertRemoteFreeNoteIfPossible(
      id: noteId,
      title: title.trim(),
      content: content,
      createdAt: createdAt,
      updatedAt: now,
      throwOnFailure: waitForRemote,
    );
    if (waitForRemote) {
      await remoteSync;
    } else {
      unawaited(remoteSync);
    }
  }

  static Future<void> deleteFreeNote(String id) async {
    final db = await DatabaseService.database;
    await _ensureFreeNotesTable(db);
    await db.delete('free_notes', where: 'id = ?', whereArgs: [id]);
    await _backupFreeNotes(db);
    unawaited(_deleteRemoteFreeNoteIfPossible(id));
  }

  static Future<void> _ensureFreeNotesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS free_notes (
        id TEXT PRIMARY KEY,
        user_id TEXT DEFAULT '',
        title TEXT DEFAULT '',
        content TEXT NOT NULL,
        xiaou_authorized INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await _addFreeNoteColumnIfMissing(db, 'title', "TEXT DEFAULT ''");
    await _addFreeNoteColumnIfMissing(
      db,
      'xiaou_authorized',
      'INTEGER NOT NULL DEFAULT 0',
    );
  }

  static Future<void> _addFreeNoteColumnIfMissing(
    Database db,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info(free_notes)');
    if (columns.any((item) => item['name'] == column)) return;
    await db.execute('ALTER TABLE free_notes ADD COLUMN $column $definition');
  }

  static Future<void> _backupFreeNotes(Database db) async {
    final prefs = await SharedPreferences.getInstance();
    final notes = await db.query(
      'free_notes',
      orderBy: 'updated_at DESC, created_at DESC',
    );
    await prefs.setString(_freeNotesBackupKey, jsonEncode(notes));
  }

  static Future<void> _restoreFreeNotesBackup(Database db) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_freeNotesBackupKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is! Map) continue;
        final note = Map<String, dynamic>.from(item);
        final id = note['id']?.toString() ?? '';
        final content = note['content']?.toString() ?? '';
        if (id.isEmpty || content.isEmpty) continue;
        await db.insert('free_notes', {
          'id': id,
          'user_id': note['user_id']?.toString() ?? '',
          'title': note['title']?.toString() ?? '',
          'content': content,
          'xiaou_authorized':
              note['xiaou_authorized'] == true || note['xiaou_authorized'] == 1
              ? 1
              : 0,
          'created_at':
              note['created_at']?.toString() ??
              DateTime.now().toUtc().toIso8601String(),
          'updated_at':
              note['updated_at']?.toString() ??
              DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    } catch (_) {
      // Keep SQLite as source of truth if the backup is unreadable.
    }
  }

  static Future<List<Map<String, dynamic>>> _queryFreeNotes(
    Database db, {
    String? query,
  }) {
    final q = query?.trim() ?? '';
    final userId = _currentFreeNotesUserId();
    final where = <String>[];
    final args = <Object?>[];

    if (userId.isEmpty) {
      where.add("(user_id = '' OR user_id IS NULL)");
    } else {
      where.add("(user_id = ? OR user_id = '' OR user_id IS NULL)");
      args.add(userId);
    }

    if (q.isNotEmpty) {
      where.add('(title LIKE ? OR content LIKE ?)');
      args.add('%$q%');
      args.add('%$q%');
    }

    return db.query(
      'free_notes',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'updated_at DESC, created_at DESC',
    );
  }

  static Future<List<Map<String, dynamic>>> _claimAnonymousFreeNotes(
    Database db, {
    String? query,
  }) async {
    final q = query?.trim() ?? '';
    final userId = _currentFreeNotesUserId();
    final where = <String>[];
    final args = <Object?>[];

    where.add("(user_id = '' OR user_id IS NULL)");

    if (q.isNotEmpty) {
      where.add('(title LIKE ? OR content LIKE ?)');
      args.add('%$q%');
      args.add('%$q%');
    }

    final notes = await db.query(
      'free_notes',
      where: where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'updated_at DESC, created_at DESC',
    );

    if (notes.isNotEmpty && userId.isNotEmpty) {
      await db.update('free_notes', {
        'user_id': userId,
      }, where: "user_id = '' OR user_id IS NULL");
      await _backupFreeNotes(db);
      return _queryFreeNotes(db, query: q);
    }

    return notes;
  }

  static String _currentFreeNotesUserId() {
    final apiUserId = BmobApi.instance.userId?.trim() ?? '';
    if (apiUserId.isNotEmpty) return apiUserId;
    return AuthService.userId?.trim() ?? '';
  }

  static Future<void> _syncFreeNotesIfPossible(Database db) async {
    final api = BmobApi.instance;
    await api.init();
    final userId = api.userId?.trim() ?? AuthService.userId?.trim() ?? '';
    if (!api.isLoggedIn || userId.isEmpty) return;

    try {
      await _pullRemoteFreeNotesIfPossible(db, api, userId);
      await _pushLocalFreeNotesIfPossible(db, api, userId);
      await _backupFreeNotes(db);
    } catch (_) {
      // 随心记以本地可用为先，云端同步失败不阻塞用户继续写。
    }
  }

  static Future<void> _pullRemoteFreeNotesIfPossible(
    Database db,
    BmobApi api,
    String userId,
  ) async {
    final rows = await api.listFreeNotes(limit: 1000);
    for (final row in rows) {
      final id = row['id']?.toString() ?? '';
      final content = row['content']?.toString() ?? '';
      if (id.isEmpty || content.isEmpty) continue;

      final remoteUpdated =
          row['updated_at']?.toString() ??
          DateTime.now().toUtc().toIso8601String();
      final local = await db.query(
        'free_notes',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (local.isNotEmpty) {
        final localUpdated = local.first['updated_at']?.toString() ?? '';
        final localTime = DateTime.tryParse(localUpdated);
        final remoteTime = DateTime.tryParse(remoteUpdated);
        if (localTime != null &&
            remoteTime != null &&
            localTime.isAfter(remoteTime)) {
          await db.update(
            'free_notes',
            {
              'xiaou_authorized':
                  row['xiaou_authorized'] == true ||
                      row['xiaou_authorized'] == 1
                  ? 1
                  : 0,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
          continue;
        }
      }

      await db.insert('free_notes', {
        'id': id,
        'user_id': userId,
        'title': row['title']?.toString() ?? '',
        'content': content,
        'xiaou_authorized':
            row['xiaou_authorized'] == true || row['xiaou_authorized'] == 1
            ? 1
            : 0,
        'created_at': row['created_at']?.toString() ?? remoteUpdated,
        'updated_at': remoteUpdated,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  static Future<void> _pushLocalFreeNotesIfPossible(
    Database db,
    BmobApi api,
    String userId,
  ) async {
    final rows = await db.query(
      'free_notes',
      where: "user_id = ? OR user_id = '' OR user_id IS NULL",
      whereArgs: [userId],
      orderBy: 'updated_at ASC',
    );

    for (final row in rows) {
      final id = row['id']?.toString() ?? '';
      final content = row['content']?.toString() ?? '';
      if (id.isEmpty || content.isEmpty) continue;

      final createdAt =
          row['created_at']?.toString() ??
          DateTime.now().toUtc().toIso8601String();
      final updatedAt = row['updated_at']?.toString() ?? createdAt;
      await api.upsertFreeNote(
        id: id,
        title: row['title']?.toString() ?? '',
        content: content,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final rowUserId = row['user_id']?.toString() ?? '';
      if (rowUserId.isEmpty) {
        await db.update(
          'free_notes',
          {'user_id': userId},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  static Future<void> _upsertRemoteFreeNoteIfPossible({
    required String id,
    required String title,
    required String content,
    required String createdAt,
    required String updatedAt,
    bool throwOnFailure = false,
  }) async {
    try {
      final api = BmobApi.instance;
      await api.init();
      if (!api.isLoggedIn) {
        if (throwOnFailure) {
          throw Exception('请先登录，再把这条随心记交给小U观察');
        }
        return;
      }
      await api.upsertFreeNote(
        id: id,
        title: title,
        content: content,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    } catch (error) {
      if (throwOnFailure) rethrow;
      // 本地已保存，稍后进入随心记时会再次尝试同步。
    }
  }

  static Future<void> _deleteRemoteFreeNoteIfPossible(String id) async {
    try {
      final api = BmobApi.instance;
      await api.init();
      if (!api.isLoggedIn) return;
      await api.deleteFreeNote(id);
    } catch (_) {
      // 删除失败时保留本地删除结果，避免用户被网络问题卡住。
    }
  }

  static Future<void> setFreeNoteXiaouAuthorization(
    String id, {
    required bool authorized,
  }) async {
    final api = BmobApi.instance;
    await api.init();
    if (!api.isLoggedIn) {
      throw Exception('请先登录，再把这条随心记交给小U观察');
    }
    await api.setFreeNoteXiaouAuthorization(id, authorized: authorized);
    final db = await DatabaseService.database;
    await _ensureFreeNotesTable(db);
    await db.update(
      'free_notes',
      {'xiaou_authorized': authorized ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _backupFreeNotes(db);
  }

  // ---- Bookmarks ----

  static Future<List<Bookmark>> getAllBookmarks() async {
    final db = await DatabaseService.database;
    final maps = await db.query('bookmarks', orderBy: 'createdAt DESC');
    return maps.map((m) => Bookmark.fromMap(m)).toList();
  }

  static Future<List<Bookmark>> getBookmarks(String bookId) async {
    final db = await DatabaseService.database;
    final maps = await db.query(
      'bookmarks',
      where: 'bookId = ?',
      whereArgs: [bookId],
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => Bookmark.fromMap(m)).toList();
  }

  static Future<void> insertBookmark(Bookmark bm) async {
    final db = await DatabaseService.database;
    await db.insert(
      'bookmarks',
      bm.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> deleteBookmark(String id) async {
    final db = await DatabaseService.database;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  static Future<bool> hasBookmark(String bookId, String chapterIndex) async {
    final db = await DatabaseService.database;
    final maps = await db.query(
      'bookmarks',
      where: 'bookId = ? AND chapterIndex = ?',
      whereArgs: [bookId, chapterIndex],
    );
    return maps.isNotEmpty;
  }

  // ---- User Entries ----

  static Future<void> insertUserEntry(UserEntry entry) async {
    final db = await DatabaseService.database;
    await db.insert(
      'user_entries',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _createRemoteUserEntryIfPossible(db, entry);
    _invalidateMingtaiOverviewCache();
  }

  static Future<List<UserEntry>> getUserEntries({
    String? bookId,
    String? source,
    String? tag,
    DateTime? createdAtFrom,
    DateTime? createdAtTo,
  }) async {
    final db = await DatabaseService.database;
    await _pullRemoteUserEntriesIfPossible(
      db,
      bookId: bookId,
      source: source,
      tag: tag,
      createdAtFrom: createdAtFrom,
      createdAtTo: createdAtTo,
    );

    final whereParts = <String>[];
    final whereArgs = <Object?>[];
    if (bookId != null && bookId.isNotEmpty) {
      whereParts.add('book_id = ?');
      whereArgs.add(bookId);
    }
    if (source != null && source.isNotEmpty) {
      whereParts.add('source = ?');
      whereArgs.add(source);
    }
    if (tag != null && tag.isNotEmpty) {
      whereParts.add('auto_tags LIKE ?');
      whereArgs.add('%$tag%');
    }
    if (createdAtFrom != null) {
      whereParts.add('created_at >= ?');
      whereArgs.add(createdAtFrom.toIso8601String());
    }
    if (createdAtTo != null) {
      whereParts.add('created_at <= ?');
      whereArgs.add(createdAtTo.toIso8601String());
    }

    final maps = await db.query(
      'user_entries',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => UserEntry.fromMap(m)).toList();
  }

  static Future<List<String>> getUserEntryTags() async {
    final db = await DatabaseService.database;
    final maps = await db.query('user_entries', columns: ['auto_tags']);
    final tags = <String>{};
    for (final m in maps) {
      tags.addAll(_parseTags((m['auto_tags'] as String?) ?? ''));
    }
    return tags.toList()..sort();
  }

  static Future<void> deleteUserEntry(String id) async {
    final db = await DatabaseService.database;
    final rows = await db.query(
      'user_entries',
      columns: ['id', 'bmob_id'],
      where: 'id = ? OR bmob_id = ?',
      whereArgs: [id, id],
      limit: 1,
    );
    final localId = rows.isNotEmpty ? (rows.first['id'] as String? ?? id) : id;
    final remoteId = rows.isNotEmpty
        ? (rows.first['bmob_id'] as String? ?? '')
        : '';
    final api = BmobApi.instance;
    if (api.isLoggedIn) {
      final idToDelete = remoteId.isNotEmpty
          ? remoteId
          : rows.isEmpty
          ? id
          : await _findRemoteEntryIdByLocalId(localId);
      if (idToDelete.isEmpty) {
        throw Exception('找不到远端 entry id，无法确认线上删除');
      }

      final deleted = await api.deleteUserEntry(idToDelete);
      if (!deleted) {
        final fallbackId = await _findRemoteEntryIdByLocalId(localId);
        if (fallbackId.isEmpty || fallbackId == idToDelete) {
          throw Exception('线上 entry 不存在或已被删除');
        }
        final fallbackDeleted = await api.deleteUserEntry(fallbackId);
        if (!fallbackDeleted) {
          throw Exception('线上 entry 不存在或已被删除');
        }
      }
    }
    await db.delete(
      'user_entries',
      where: 'id = ? OR bmob_id = ?',
      whereArgs: [localId, id],
    );
  }

  // ---- MingTai ----

  static Future<void> insertMingtaiItem(Map<String, dynamic> item) async {
    final db = await DatabaseService.database;
    await db.insert(
      'mingtai_items',
      item,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static XiaouHomeInsight? cachedXiaouHomeInsight() {
    return _xiaouHomeInsightCache;
  }

  static Future<XiaouHomeInsight?> restoreCachedXiaouHomeInsight() async {
    final memory = _xiaouHomeInsightCache;
    if (memory != null) return memory;

    final row = await _readDiskMap(_xiaouHomeDiskCacheKey);
    if (row == null) return null;
    final insight = XiaouHomeInsight.fromRemote(row);
    _xiaouHomeInsightCache = insight;
    _xiaouHomeInsightCacheAt = DateTime.now();
    return insight;
  }

  static Future<XiaouHomeInsight> getXiaouHomeInsight({
    bool forceRefresh = false,
  }) async {
    if (!BmobApi.instance.isLoggedIn) return XiaouHomeInsight.empty();
    final cached = _xiaouHomeInsightCache;
    final cacheAt = _xiaouHomeInsightCacheAt;
    final cacheFresh =
        cached != null &&
        cacheAt != null &&
        DateTime.now().difference(cacheAt) < _xiaouHomeInsightCacheTtl;
    if (!forceRefresh && cacheFresh) return cached;

    final running = _xiaouHomeInsightInFlight;
    if (running != null) return running;

    late final Future<XiaouHomeInsight> request;
    request = (() async {
      try {
        final row = await BmobApi.instance.getXiaouHomeInsight();
        final insight = XiaouHomeInsight.fromRemote(row);
        _xiaouHomeInsightCache = insight;
        _xiaouHomeInsightCacheAt = DateTime.now();
        unawaited(_writeDiskMap(_xiaouHomeDiskCacheKey, row));
        return insight;
      } catch (_) {
        if (cached != null) return cached;
        final disk = await restoreCachedXiaouHomeInsight();
        if (disk != null) return disk;
        rethrow;
      }
    })();
    _xiaouHomeInsightInFlight = request;
    try {
      return await request;
    } finally {
      if (identical(_xiaouHomeInsightInFlight, request)) {
        _xiaouHomeInsightInFlight = null;
      }
    }
  }

  static List<Map<String, dynamic>> xiaouSnapshotItems(
    XiaouHomeInsight insight,
  ) {
    return insight.recentEntries
        .map(_remoteUserEntryToMingtaiItem)
        .where(
          (item) => ((item['remote_entry_id'] as String?) ?? '').isNotEmpty,
        )
        .toList();
  }

  static List<MingtaiPublicBook> cachedMingtaiBooks({int limit = 50}) {
    final cached = _mingtaiBooksCache ?? const <MingtaiPublicBook>[];
    return cached.take(limit).toList();
  }

  static MingtaiHomeData? cachedMingtaiHome() {
    return _mingtaiHomeCache;
  }

  static Future<void> clearMingtaiHomeCache() async {
    _mingtaiHomeCache = null;
    _mingtaiHomeCacheAt = null;
    _mingtaiBooksCache = null;
    _mingtaiBooksCacheAt = null;
    _mingtaiBookDetailCache.clear();
    _mingtaiBookDetailCacheAt.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_mingtaiHomeDiskCacheKey);
    } catch (_) {}
  }

  static Future<int> deleteMyMingtaiBooks() async {
    final data = await BmobApi.instance.deleteMyMingtaiBooks();
    await clearMingtaiHomeCache();
    return int.tryParse(data['deleted_count']?.toString() ?? '') ?? 0;
  }

  static Future<void> deleteMyMingtaiBook(String bookId) async {
    await BmobApi.instance.deleteMyMingtaiBook(bookId);
    await clearMingtaiHomeCache();
  }

  static Future<MingtaiHomeData?> restoreCachedMingtaiHome() async {
    final memory = _mingtaiHomeCache;
    if (memory != null) return memory;

    final row = await _readDiskMap(_mingtaiHomeDiskCacheKey);
    if (row == null) return null;
    final home = MingtaiHomeData.fromRemote(row);
    _mingtaiHomeCache = home;
    _mingtaiHomeCacheAt = DateTime.now();
    return home;
  }

  static Future<MingtaiHomeData> getMingtaiHome({
    bool forceRefresh = false,
  }) async {
    final cached = _mingtaiHomeCache;
    final cacheAt = _mingtaiHomeCacheAt;
    final cacheFresh =
        cached != null &&
        cacheAt != null &&
        DateTime.now().difference(cacheAt) < _mingtaiBooksCacheTtl;
    if (!forceRefresh && cacheFresh) return cached;

    final running = _mingtaiHomeInFlight;
    if (running != null) return running;

    late final Future<MingtaiHomeData> request;
    request = (() async {
      try {
        final data = await BmobApi.instance.getMingtaiHome();
        final home = MingtaiHomeData.fromRemote(data);
        _mingtaiHomeCache = home;
        _mingtaiHomeCacheAt = DateTime.now();
        unawaited(_writeDiskMap(_mingtaiHomeDiskCacheKey, data));
        return home;
      } catch (_) {
        if (!forceRefresh) {
          if (cached != null) return cached;
          final disk = await restoreCachedMingtaiHome();
          if (disk != null) return disk;
        }
        rethrow;
      }
    })();
    _mingtaiHomeInFlight = request;
    try {
      return await request;
    } finally {
      if (identical(_mingtaiHomeInFlight, request)) {
        _mingtaiHomeInFlight = null;
      }
    }
  }

  static Future<List<MingtaiPublicBook>> getMingtaiBooks({
    int limit = 50,
    bool forceRefresh = false,
    String search = '',
  }) async {
    final q = search.trim();
    if (q.isNotEmpty) {
      final rows = await BmobApi.instance.listMingtaiBooks(
        limit: limit,
        search: q,
      );
      return rows.map(MingtaiPublicBook.fromRemote).toList();
    }

    final cached = _mingtaiBooksCache;
    final cacheAt = _mingtaiBooksCacheAt;
    final cacheFresh =
        cached != null &&
        cacheAt != null &&
        DateTime.now().difference(cacheAt) < _mingtaiBooksCacheTtl;
    if (!forceRefresh && cacheFresh) {
      return cached.take(limit).toList();
    }

    List<Map<String, dynamic>> rows;
    try {
      rows = await BmobApi.instance.listMingtaiBooks(limit: limit);
    } catch (_) {
      if (cached != null && cached.isNotEmpty) {
        return cached.take(limit).toList();
      }
      rethrow;
    }
    final books = rows.map(MingtaiPublicBook.fromRemote).toList();
    _mingtaiBooksCache = books;
    _mingtaiBooksCacheAt = DateTime.now();
    return books;
  }

  static Future<MingtaiBookDetail> getMingtaiBookDetail(
    String bookId, {
    bool forceRefresh = false,
  }) async {
    final cached = _mingtaiBookDetailCache[bookId];
    final cacheAt = _mingtaiBookDetailCacheAt[bookId];
    final cacheFresh =
        cached != null &&
        cacheAt != null &&
        DateTime.now().difference(cacheAt) < _mingtaiBookDetailCacheTtl;
    if (!forceRefresh && cacheFresh) {
      return cached;
    }

    final data = await BmobApi.instance.getMingtaiBook(bookId);
    final book = MingtaiPublicBook.fromRemote(
      Map<String, dynamic>.from(data['book'] ?? {}),
    );
    final annotations = List<Map<String, dynamic>>.from(
      data['annotations'] ?? [],
    ).map(MingtaiFeedItem.fromRemote).toList();
    final detail = MingtaiBookDetail(book: book, annotations: annotations);
    _mingtaiBookDetailCache[bookId] = detail;
    _mingtaiBookDetailCacheAt[bookId] = DateTime.now();
    return detail;
  }

  static Future<List<MingtaiBookReview>> listMingtaiBookReviews(
    String bookId,
  ) async {
    final rows = await BmobApi.instance.listMingtaiBookReviews(bookId);
    return rows.map(MingtaiBookReview.fromRemote).toList();
  }

  static Future<MingtaiBookReview> createMingtaiBookReview({
    required String bookId,
    required String content,
  }) async {
    final data = await BmobApi.instance.createMingtaiBookReview(
      bookId: bookId,
      content: content,
      clientRequestId: _uuid.v4(),
    );
    _mingtaiBookDetailCache.remove(bookId);
    _mingtaiBookDetailCacheAt.remove(bookId);
    final review = data['review'];
    return MingtaiBookReview.fromRemote(
      Map<String, dynamic>.from(review ?? {}),
    );
  }

  static Future<MingtaiBookReview> updateMingtaiBookReview({
    required String reviewId,
    required String content,
  }) async {
    final data = await BmobApi.instance.updateMingtaiBookReview(
      reviewId: reviewId,
      content: content,
    );
    final review = data['review'];
    final parsed = MingtaiBookReview.fromRemote(
      Map<String, dynamic>.from(review ?? {}),
    );
    if (parsed.publicBookId.isNotEmpty) {
      _mingtaiBookDetailCache.remove(parsed.publicBookId);
      _mingtaiBookDetailCacheAt.remove(parsed.publicBookId);
    }
    return parsed;
  }

  static Future<void> deleteMingtaiBookReview(MingtaiBookReview review) async {
    await BmobApi.instance.deleteMingtaiBookReview(review.id);
    if (review.publicBookId.isNotEmpty) {
      _mingtaiBookDetailCache.remove(review.publicBookId);
      _mingtaiBookDetailCacheAt.remove(review.publicBookId);
    }
  }

  static Future<List<MingtaiInteractionComment>> listMingtaiComments({
    required String targetType,
    required String targetId,
  }) async {
    final rows = await BmobApi.instance.listMingtaiComments(
      targetType: targetType,
      targetId: targetId,
    );
    return rows.map(MingtaiInteractionComment.fromRemote).toList();
  }

  static Future<MingtaiInteractionComment> createMingtaiComment({
    required String targetType,
    required String targetId,
    required String content,
  }) async {
    final data = await BmobApi.instance.createMingtaiComment(
      targetType: targetType,
      targetId: targetId,
      content: content,
    );
    return MingtaiInteractionComment.fromRemote(
      Map<String, dynamic>.from(data['comment'] ?? {}),
    );
  }

  static Future<int> createMingtaiTargetResonance({
    required String targetType,
    required String targetId,
  }) async {
    final data = await BmobApi.instance.createMingtaiTargetResonance(
      targetType: targetType,
      targetId: targetId,
    );
    final payload = Map<String, dynamic>.from(data['resonance'] ?? {});
    return int.tryParse(payload['resonance_count']?.toString() ?? '') ?? 0;
  }

  static Future<List<MingtaiNotification>> listMingtaiNotifications() async {
    final data = await BmobApi.instance.listMingtaiNotifications();
    final rows = MingtaiHomeData._remoteMaps(data['notifications']);
    return rows.map(MingtaiNotification.fromRemote).toList();
  }

  static Future<int> getMingtaiUnreadNotificationCount() {
    return BmobApi.instance.getMingtaiUnreadNotificationCount();
  }

  static Future<void> markMingtaiNotificationRead(String notificationId) {
    return BmobApi.instance.markMingtaiNotificationRead(notificationId);
  }

  static Future<void> markAllMingtaiNotificationsRead() {
    return BmobApi.instance.markAllMingtaiNotificationsRead();
  }

  static Future<MingtaiPublicProfile> getMingtaiMyProfile() async {
    final data = await BmobApi.instance.getMingtaiMyProfile();
    return MingtaiPublicProfile.fromRemote(data);
  }

  static Future<MingtaiUserProfile> updateMingtaiMyProfile({
    required String nickname,
    required String avatarUrl,
    required String bio,
  }) async {
    final data = await BmobApi.instance.updateMingtaiMyProfile(
      nickname: nickname,
      avatarUrl: avatarUrl,
      bio: bio,
    );
    return MingtaiUserProfile.fromRemote(
      Map<String, dynamic>.from(data['profile'] ?? {}),
    );
  }

  static Future<MingtaiUserProfile> uploadMingtaiProfileAvatar({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
    required String nickname,
    required String bio,
  }) async {
    final data = await BmobApi.instance.uploadMingtaiProfileAvatar(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      nickname: nickname,
      bio: bio,
    );
    return MingtaiUserProfile.fromRemote(
      Map<String, dynamic>.from(data['profile'] ?? {}),
    );
  }

  static Future<MingtaiPublicProfile> getMingtaiPublicProfile(
    String userId,
  ) async {
    final data = await BmobApi.instance.getMingtaiPublicProfile(userId);
    return MingtaiPublicProfile.fromRemote(data);
  }

  static Future<void> publishBookToMingtai({
    required Book book,
    required String copyrightStatus,
    required List<String> entryIds,
  }) async {
    final api = BmobApi.instance;
    await api.init();
    if (!api.isLoggedIn || (api.token?.trim().isEmpty ?? true)) {
      throw Exception('请先登录后再发布到明台');
    }

    final sourceBookId = _sourceBookIdForPublish(book);
    final fileType = _fileTypeForPublish(book);
    final epubMetadata = fileType == 'epub'
        ? await EpubService.readMetadata(book.filePath)
        : null;
    final title = _safeBookTitleForPublish(
      book,
      metadataTitle: epubMetadata?.title,
    );
    final author = _safeBookAuthorForPublish(
      book.author,
      metadataAuthor: epubMetadata?.author,
    );
    final coverPath = await _coverPathForMingtaiPublish(book, fileType);
    await api.publishMingtaiBook(
      sourceBookId: sourceBookId,
      title: title,
      author: author,
      coverPath: coverPath,
      description: book.description,
      copyrightStatus: copyrightStatus,
      filePath: book.filePath,
      fileType: fileType,
      entryIds: entryIds,
    );
    _invalidateMingtaiBooksCache();
  }

  static Future<String?> _coverPathForMingtaiPublish(
    Book book,
    String fileType,
  ) async {
    final existingPath = book.coverPath?.trim() ?? '';
    if (existingPath.isNotEmpty && await File(existingPath).exists()) {
      return _optimizedCoverPathForMingtaiPublish(existingPath);
    }
    if (fileType == 'epub') {
      final extractedPath = await EpubService.extractCover(book.filePath);
      if (extractedPath == null || extractedPath.trim().isEmpty) return null;
      return _optimizedCoverPathForMingtaiPublish(extractedPath);
    }
    return null;
  }

  static Future<String> _optimizedCoverPathForMingtaiPublish(
    String coverPath,
  ) async {
    const maxUsefulBytes = 220 * 1024;
    const targetWidth = 420;

    try {
      final source = File(coverPath);
      final bytes = await source.readAsBytes();
      if (bytes.length <= maxUsefulBytes) return coverPath;

      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
      );
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      frame.image.dispose();
      if (byteData == null) return coverPath;

      final optimizedBytes = byteData.buffer.asUint8List();
      if (optimizedBytes.length >= bytes.length) return coverPath;

      final tempDir = await getTemporaryDirectory();
      final outputDir = Directory(
        p.join(tempDir.path, 'mingtai_cover_uploads'),
      );
      await outputDir.create(recursive: true);
      final digest = md5.convert(bytes).toString().substring(0, 12);
      final output = File(p.join(outputDir.path, 'cover_$digest.png'));
      await output.writeAsBytes(
        Uint8List.fromList(optimizedBytes),
        flush: true,
      );
      return output.path;
    } catch (_) {
      return coverPath;
    }
  }

  static String _sourceBookIdForPublish(Book book) {
    final id = book.id.trim();
    if (id.isNotEmpty) return id;

    final path = book.filePath.trim();
    if (path.isNotEmpty) {
      final digest = md5.convert(utf8.encode(path)).toString();
      return 'local_path_$digest';
    }

    final fileName = p.basename(book.filePath).trim();
    final importedAt = book.addedAt.millisecondsSinceEpoch;
    final seed = '$importedAt:$fileName:${book.title}';
    return 'local_import_${md5.convert(utf8.encode(seed))}';
  }

  static String _fileTypeForPublish(Book book) {
    final format = book.format.trim().toLowerCase().replaceAll('.', '');
    if (_supportedFormat(format)) return format;
    final ext = p.extension(book.filePath).toLowerCase().replaceAll('.', '');
    if (_supportedFormat(ext)) return ext;
    return 'epub';
  }

  static String _safeBookTitleForPublish(Book book, {String? metadataTitle}) {
    final title = book.title.trim();
    if (title.isNotEmpty &&
        title.toLowerCase() != 'unknown title' &&
        title != '未知书名' &&
        title != '未命名文档') {
      return title;
    }
    final epubTitle = metadataTitle?.trim() ?? '';
    if (epubTitle.isNotEmpty &&
        epubTitle.toLowerCase() != 'unknown title' &&
        epubTitle != '未知书名') {
      return epubTitle;
    }
    final pathParts = book.filePath
        .split(RegExp(r'[\\/]'))
        .where((part) => part.isNotEmpty)
        .toList();
    final fileName = pathParts.isNotEmpty ? pathParts.last : '';
    final dot = fileName.lastIndexOf('.');
    final name = dot > 0 ? fileName.substring(0, dot) : fileName;
    return name.trim().isNotEmpty ? name.trim() : '未命名文档';
  }

  static String _safeBookAuthorForPublish(
    String author, {
    String? metadataAuthor,
  }) {
    final trimmed = author.trim();
    if (trimmed.isNotEmpty &&
        trimmed.toLowerCase() != 'unknown author' &&
        trimmed != '未知作者' &&
        trimmed != '佚名') {
      return trimmed;
    }
    final epubAuthor = metadataAuthor?.trim() ?? '';
    if (epubAuthor.isNotEmpty &&
        epubAuthor.toLowerCase() != 'unknown author' &&
        epubAuthor != '未知作者') {
      return epubAuthor;
    }
    return '佚名';
  }

  static Future<Book> borrowMingtaiBook(MingtaiPublicBook publicBook) async {
    final data = await BmobApi.instance.borrowMingtaiBook(publicBook.id);
    final remoteBook = MingtaiPublicBook.fromRemote(
      Map<String, dynamic>.from(data['book'] ?? {}),
    );
    if (!canReadMingtaiBook(remoteBook)) {
      throw Exception('这本明台书还没有可阅读内容');
    }
    final now = DateTime.now();
    final book = Book(
      id: publicShelfBookId(remoteBook.id),
      title: remoteBook.title,
      author: remoteBook.author,
      coverPath: null,
      filePath: remoteBook.fileUrl,
      format: remoteBook.fileType,
      description: remoteBook.description,
      addedAt: now,
      lastOpenedAt: now,
      updatedAt: now.toUtc().toIso8601String(),
    );
    await insertBook(book);
    return book;
  }

  static Future<void> recordMingtaiBookRead(String publicBookId) async {
    try {
      await BmobApi.instance.recordMingtaiBookRead(publicBookId);
      _mingtaiHomeCache = null;
      _mingtaiHomeCacheAt = null;
    } catch (_) {
      // Reading should open even when this quiet activity marker fails.
    }
  }

  static Book readableBookFromMingtai(MingtaiPublicBook publicBook) {
    return Book(
      id: publicShelfBookId(publicBook.id),
      title: publicBook.title,
      author: publicBook.author,
      coverPath: null,
      filePath: publicBook.fileUrl,
      format: publicBook.fileType,
      description: publicBook.description,
      addedAt: DateTime.now(),
      lastOpenedAt: DateTime.now(),
      chapterTitles: const [],
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  static String publicShelfBookId(String publicBookId) =>
      'mingtai_$publicBookId';

  static String publicBookIdFromShelfId(String id) {
    if (id.startsWith('mingtai_')) return id.substring('mingtai_'.length);
    if (id.startsWith('mingtai:')) return id.substring('mingtai:'.length);
    return id;
  }

  static bool isMingtaiShelfBook(Book book) {
    return book.id.startsWith('mingtai_') || book.id.startsWith('mingtai:');
  }

  static bool canReadMingtaiBook(MingtaiPublicBook book) {
    final format = book.fileType.toLowerCase();
    if (format == 'epub' || format == 'txt') {
      return book.chapterCount > 0;
    }
    if (format == 'pdf') return book.fileUrl.isNotEmpty;
    return book.chapterCount > 0;
  }

  static Future<void> prefetchMingtaiBookChapters(
    MingtaiPublicBook publicBook,
  ) async {
    final shelfBookId = publicShelfBookId(publicBook.id);
    final runningTask = _mingtaiOpeningPrefetchTasks[shelfBookId];
    if (runningTask != null) return runningTask;

    late final Future<void> task;
    task = _prefetchMingtaiBookOpening(shelfBookId).whenComplete(() {
      if (identical(_mingtaiOpeningPrefetchTasks[shelfBookId], task)) {
        _mingtaiOpeningPrefetchTasks.remove(shelfBookId);
      }
    });
    _mingtaiOpeningPrefetchTasks[shelfBookId] = task;
    return task;
  }

  static Future<void> _prefetchMingtaiBookOpening(String shelfBookId) async {
    final shells = await getMingtaiChapterShells(
      shelfBookId,
    ).catchError((_) => const <EpubChapter>[]);
    if (shells.isEmpty) return;

    final firstIndexes = shells.take(1).map((chapter) => chapter.index).toSet();
    await Future.wait([
      for (final index in firstIndexes)
        getMingtaiChapterContent(shelfBookId, index).catchError((_) => ''),
    ]);
  }

  static Future<Book> prepareBookForReading(Book book) async {
    if (!isMingtaiShelfBook(book)) {
      return book;
    }
    final format = _supportedFormat(book.format)
        ? book.format
        : _formatFromUrl(book.filePath);

    if (format == 'epub' || format == 'txt') {
      final shells = await getMingtaiChapterShells(book.id);
      if (shells.isEmpty) {
        throw Exception('这本明台书尚未生成章节缓存，请重新发布后再阅读');
      }
      final titles = shells.map((chapter) => chapter.title).toList();
      unawaited(
        _refreshCachedPublicBookMetadata(
          book,
          format: format,
          chapterTitles: titles,
        ),
      );
      return book.copyWith(format: format, chapterTitles: titles);
    }

    if (format != 'pdf') {
      throw Exception('暂不支持这种明台书籍格式');
    }
    if (book.filePath.isEmpty) {
      throw Exception('这本明台书还没有可阅读内容');
    }
    if (!_isRemoteUrl(book.filePath)) {
      return book;
    }

    final pdfPath = await PdfService.getPdfPath(book.id);
    if (await File(pdfPath).exists()) {
      await _refreshCachedPublicBookMetadata(
        book,
        format: 'pdf',
        chapterTitles: const ['PDF 文档'],
      );
      return book.copyWith(filePath: pdfPath, format: 'pdf');
    }

    final localPath = await _downloadPublicBookFile(book, format);
    final imported = await ImportService.importFile(
      localPath,
      bookId: book.id,
      title: book.title,
      author: book.author,
    );
    await _refreshCachedPublicBookMetadata(
      book,
      format: imported.format,
      chapterTitles: imported.chapterTitles,
    );
    return imported.copyWith(
      id: book.id,
      title: book.title,
      author: book.author,
      description: book.description,
      format: imported.format,
    );
  }

  static Future<List<EpubChapter>> getMingtaiChapterShells(
    String bookId,
  ) async {
    final cachedShells = await _readCachedMingtaiChapterShells(bookId);
    if (cachedShells.isNotEmpty) return cachedShells;

    final publicBookId = publicBookIdFromShelfId(bookId);
    late final List<Map<String, dynamic>> rows;
    try {
      rows = await BmobApi.instance.listMingtaiBookChapters(publicBookId);
    } catch (_) {
      final titles = await EpubService.getChapterTitles(bookId);
      if (titles.isEmpty) rethrow;
      return [
        for (var i = 0; i < titles.length; i++)
          EpubChapter(title: titles[i], content: '', index: i),
      ];
    }

    final shells =
        rows
            .map(
              (row) => EpubChapter(
                title:
                    row['chapter_title']?.toString() ??
                    row['title']?.toString() ??
                    '第${(int.tryParse(row['chapter_index']?.toString() ?? '') ?? 0) + 1}章',
                content: '',
                index:
                    int.tryParse(row['chapter_index']?.toString() ?? '') ?? 0,
                href: row['href']?.toString() ?? '',
              ),
            )
            .toList()
          ..sort((a, b) => a.index.compareTo(b.index));

    if (shells.isNotEmpty) {
      await _cacheMingtaiChapterShells(bookId, shells);
    }
    return shells;
  }

  static Future<String> getMingtaiChapterContent(
    String bookId,
    int index,
  ) async {
    final filePath = await EpubService.getChapterFilePath(bookId, index);
    final file = File(filePath);
    if (await file.exists() && await file.length() > 0) {
      return file.readAsString();
    }

    final cacheKey = '$bookId:$index';
    final runningTask = _mingtaiChapterContentTasks[cacheKey];
    if (runningTask != null) return runningTask;

    late final Future<String> task;
    task =
        _fetchAndCacheMingtaiChapterContent(
          bookId: bookId,
          index: index,
          file: file,
        ).whenComplete(() {
          if (identical(_mingtaiChapterContentTasks[cacheKey], task)) {
            _mingtaiChapterContentTasks.remove(cacheKey);
          }
        });
    _mingtaiChapterContentTasks[cacheKey] = task;
    return task;
  }

  static Future<String> _fetchAndCacheMingtaiChapterContent({
    required String bookId,
    required int index,
    required File file,
  }) async {
    final publicBookId = publicBookIdFromShelfId(bookId);
    final row = await BmobApi.instance.getMingtaiBookChapter(
      publicBookId,
      index,
    );
    final content =
        row['content_html']?.toString() ?? row['content']?.toString() ?? '';
    if (content.isNotEmpty) {
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
    }
    return content;
  }

  static Future<List<EpubChapter>> _readCachedMingtaiChapterShells(
    String bookId,
  ) async {
    final appDir = await getApplicationDocumentsDirectory();
    final chapterDir = Directory(
      p.join(appDir.path, AppConstants.booksDir, bookId),
    );
    final shellFile = File(p.join(chapterDir.path, 'chapter_shells.json'));
    if (!await shellFile.exists()) return const [];

    try {
      final rows = (jsonDecode(await shellFile.readAsString()) as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final shells =
          rows
              .map(
                (row) => EpubChapter(
                  title: row['title']?.toString() ?? '',
                  content: '',
                  index: int.tryParse(row['index']?.toString() ?? '') ?? 0,
                  href: row['href']?.toString() ?? '',
                ),
              )
              .where((chapter) => chapter.title.trim().isNotEmpty)
              .toList()
            ..sort((a, b) => a.index.compareTo(b.index));
      return shells;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _cacheMingtaiChapterShells(
    String bookId,
    List<EpubChapter> shells,
  ) async {
    final appDir = await getApplicationDocumentsDirectory();
    final chapterDir = Directory(
      p.join(appDir.path, AppConstants.booksDir, bookId),
    );
    await chapterDir.create(recursive: true);

    final shellFile = File(p.join(chapterDir.path, 'chapter_shells.json'));
    await shellFile.writeAsString(
      jsonEncode([
        for (final chapter in shells)
          {
            'index': chapter.index,
            'title': chapter.title,
            'href': chapter.href,
          },
      ]),
    );

    final titlesFile = File(p.join(chapterDir.path, 'titles.json'));
    await titlesFile.writeAsString(
      jsonEncode(shells.map((chapter) => chapter.title).toList()),
    );
  }

  static Future<void> _refreshCachedPublicBookMetadata(
    Book book, {
    required String format,
    required List<String> chapterTitles,
  }) async {
    final existing = await getBook(book.id);
    if (existing == null) return;
    await updateBook(
      existing.copyWith(
        title: book.title,
        author: book.author,
        format: format,
        chapterTitles: chapterTitles,
      ),
    );
  }

  static Future<String> _downloadPublicBookFile(Book book, String format) {
    final taskKey = '${book.id}:$format';
    final runningTask = _publicBookDownloadTasks[taskKey];
    if (runningTask != null) return runningTask;

    late final Future<String> task;
    task = _downloadPublicBookFileInner(book, format).whenComplete(() {
      if (identical(_publicBookDownloadTasks[taskKey], task)) {
        _publicBookDownloadTasks.remove(taskKey);
      }
    });
    _publicBookDownloadTasks[taskKey] = task;
    return task;
  }

  static Future<String> _downloadPublicBookFileInner(
    Book book,
    String format,
  ) async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(p.join(dir.path, 'public_books'));
    await cacheDir.create(recursive: true);
    final localPath = p.join(
      cacheDir.path,
      '${_safeFileName(book.id)}.$format',
    );
    final localFile = File(localPath);
    if (await localFile.exists() && await localFile.length() > 0) {
      if (await _isPublicBookFileReadable(localFile, format)) {
        return localPath;
      }
      await localFile.delete();
    }

    final tempFile = File('$localPath.download');
    Object? lastError;
    for (var attempt = 1; attempt <= 4; attempt += 1) {
      try {
        final completed = await _downloadPublicBookAttempt(
          url: book.filePath,
          tempFile: tempFile,
          localFile: localFile,
        );
        if (completed) {
          if (await _isPublicBookFileReadable(localFile, format)) {
            return localPath;
          }
          lastError = _invalidPublicBookFileMessage(format);
          if (await localFile.exists()) await localFile.delete();
          if (await tempFile.exists()) await tempFile.delete();
        }
      } catch (e) {
        lastError = e;
        if (attempt == 4) break;
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    throw Exception('下载明台书籍失败，请检查网络后重试：$lastError');
  }

  static Future<bool> _isPublicBookFileReadable(
    File file,
    String format,
  ) async {
    if (!await file.exists() || await file.length() == 0) return false;
    switch (format.toLowerCase()) {
      case 'epub':
        return EpubService.isReadableEpub(file.path);
      case 'pdf':
        final header = await _readFileHeader(file, 4);
        final text = utf8.decode(header, allowMalformed: true);
        return header.length >= 4 && text == '%PDF';
      case 'txt':
        return true;
      default:
        return true;
    }
  }

  static Future<List<int>> _readFileHeader(File file, int length) async {
    final stream = file.openRead(0, length);
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
      if (bytes.length >= length) break;
    }
    return bytes.take(length).toList();
  }

  static String _invalidPublicBookFileMessage(String format) {
    if (format.toLowerCase() == 'epub') {
      return '这本明台书的文件不是标准 EPUB，或缓存已损坏。请重新发布原始 EPUB 文件。';
    }
    return '这本明台书文件无法读取，请重新发布原始文件。';
  }

  static Future<bool> _downloadPublicBookAttempt({
    required String url,
    required File tempFile,
    required File localFile,
  }) async {
    final existingBytes = await tempFile.exists() ? await tempFile.length() : 0;
    final client = http.Client();
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..headers['Accept'] = '*/*'
        ..headers['Accept-Encoding'] = 'identity';
      if (existingBytes > 0) {
        request.headers['Range'] = 'bytes=$existingBytes-';
      }

      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 416 && existingBytes > 0) {
        await _promoteDownloadedFile(tempFile, localFile);
        return true;
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final shouldAppend = response.statusCode == 206 && existingBytes > 0;
      if (!shouldAppend && await tempFile.exists()) {
        await tempFile.delete();
      }
      final expectedTotal = _expectedDownloadSize(response);
      sink = tempFile.openWrite(
        mode: shouldAppend ? FileMode.append : FileMode.write,
      );

      await for (final chunk in response.stream.timeout(
        const Duration(minutes: 3),
      )) {
        sink.add(chunk);
      }
      await sink.close();
      sink = null;

      final finalSize = await tempFile.length();
      if (finalSize == 0) {
        throw Exception('文件为空');
      }
      if (expectedTotal != null && finalSize < expectedTotal) {
        return false;
      }

      await _promoteDownloadedFile(tempFile, localFile);
      return true;
    } on TimeoutException {
      throw Exception('连接超时');
    } on SocketException catch (e) {
      throw Exception('连接中断：${e.message}');
    } on http.ClientException catch (e) {
      throw Exception('连接中断：${e.message}');
    } finally {
      await sink?.close();
      client.close();
    }
  }

  static int? _expectedDownloadSize(http.StreamedResponse response) {
    final contentRange = response.headers['content-range'];
    if (contentRange != null) {
      final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
      if (match != null) return int.tryParse(match.group(1)!);
    }
    return response.contentLength;
  }

  static Future<void> _promoteDownloadedFile(
    File tempFile,
    File localFile,
  ) async {
    if (await localFile.exists()) {
      await localFile.delete();
    }
    await tempFile.rename(localFile.path);
  }

  static bool _isRemoteUrl(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  static bool _supportedFormat(String value) {
    final format = value.toLowerCase();
    return format == 'epub' || format == 'txt' || format == 'pdf';
  }

  static String _formatFromUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final ext = p.extension(path).toLowerCase().replaceAll('.', '');
    return _supportedFormat(ext) ? ext : 'epub';
  }

  static String _safeFileName(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
  }

  static Future<List<Map<String, dynamic>>> getPublishableEntriesForBook(
    String bookId,
  ) async {
    final rows = await BmobApi.instance.listUserEntries(
      bookId: bookId,
      limit: 200,
    );
    return rows.where((row) {
      final id = row['id']?.toString() ?? '';
      final source = row['source']?.toString() ?? '';
      return id.isNotEmpty && (source == 'thought' || source == 'manual');
    }).toList();
  }

  static Future<void> createMingtaiResonance({
    required String annotationId,
    String content = '',
  }) async {
    await BmobApi.instance.createMingtaiResonance(
      annotationId: annotationId,
      content: content,
    );
  }

  static Future<void> createMingtaiAnnotationComment({
    required String annotationId,
    required String content,
  }) async {
    await BmobApi.instance.createMingtaiAnnotationComment(
      annotationId: annotationId,
      content: content,
    );
  }

  static Future<void> createPublicAnnotationForCurrentBook({
    required Book book,
    required int chapterIndex,
    required String chapterTitle,
    required String source,
    required String originalText,
    String annotationText = '',
    Map<String, dynamic> positionJson = const {},
  }) async {
    if (!isMingtaiShelfBook(book)) return;
    if (source == 'highlight') return;
    final publicBookId = publicBookIdFromShelfId(book.id);
    await BmobApi.instance.createMingtaiBookAnnotation(
      bookId: publicBookId,
      chapterIndex: chapterIndex,
      chapterTitle: chapterTitle,
      source: source,
      originalText: originalText,
      annotationText: annotationText,
      positionJson: positionJson,
    );
    _mingtaiBookDetailCache.remove(publicBookId);
    _mingtaiBookDetailCacheAt.remove(publicBookId);
    _invalidateMingtaiBooksCache();
  }

  static Future<void> publishEntryToMingtai(String itemId) async {
    final entryId = itemId.startsWith('entry:') ? itemId.substring(6) : itemId;
    if (entryId.isEmpty) {
      throw Exception('找不到远端 entry id，无法公开到明台');
    }
    await BmobApi.instance.publishMingtaiAnnotations([entryId]);
  }

  static Future<void> quoteMingtaiItemToXiaou(MingtaiFeedItem item) async {
    final api = BmobApi.instance;
    if (!api.isLoggedIn) {
      throw Exception('请先登录后再引用到小U');
    }

    final metadata = Map<String, dynamic>.from(item.metadata);
    metadata['source'] = 'mingtai';
    metadata['public_annotation_id'] = item.id;
    metadata['public_entry_id'] = item.entryId;

    await api.createUserEntry({
      'source': 'manual',
      'book_id': item.bookId,
      'book_title': item.bookTitle,
      'chapter_index': item.chapterIndex,
      'chapter_title': item.chapterTitle,
      'original_text': item.originalText,
      'user_input': item.annotationText.isNotEmpty
          ? '引用明台批注：${item.annotationText}'
          : '引用明台页边笔记',
      'auto_tags': ['明台引用', ...item.tags],
      'auto_summary': item.annotationText,
      'metadata_json': metadata,
    });
  }

  static Future<List<Map<String, dynamic>>> getMingtaiItems({
    String? tag,
  }) async {
    final overview = await getMingtaiOverview(tag: tag);
    return overview.items;
  }

  static Future<List<String>> getMingtaiTags() async {
    final overview = await getMingtaiOverview();
    return overview.tags;
  }

  static MingtaiOverview? cachedMingtaiOverview({String? tag}) {
    final cached = _mingtaiOverviewCache;
    if (cached == null) return null;
    return _filterMingtaiOverview(cached, tag);
  }

  static Future<MingtaiOverview?> restoreCachedMingtaiOverview({
    String? tag,
  }) async {
    final memory = _mingtaiOverviewCache;
    if (memory != null) return _filterMingtaiOverview(memory, tag);

    final rows = await _readDiskMapList(_xiaouOverviewDiskCacheKey);
    if (rows == null) return null;
    final overview = _buildMingtaiOverviewFromRows(rows);
    _mingtaiOverviewCache = overview;
    _mingtaiOverviewCacheAt = DateTime.now();
    return _filterMingtaiOverview(overview, tag);
  }

  static Future<MingtaiOverview> getMingtaiOverview({
    String? tag,
    bool forceRefresh = false,
  }) async {
    final api = BmobApi.instance;
    if (!api.isLoggedIn) {
      return MingtaiOverview(
        items: const [],
        allItems: const [],
        tags: const [],
        insights: {7: MingtaiInsight.empty(7), 30: MingtaiInsight.empty(30)},
      );
    }

    final cached = _mingtaiOverviewCache;
    final cacheAt = _mingtaiOverviewCacheAt;
    final cacheFresh =
        cached != null &&
        cacheAt != null &&
        DateTime.now().difference(cacheAt) < _mingtaiOverviewCacheTtl;
    if (!forceRefresh && cacheFresh) {
      return _filterMingtaiOverview(cached, tag);
    }

    final running = _mingtaiOverviewInFlight;
    if (running != null) {
      return _filterMingtaiOverview(await running, tag);
    }

    late final Future<MingtaiOverview> request;
    request = (() async {
      List<Map<String, dynamic>> rows;
      try {
        rows = await api.listUserEntries(limit: 300);
      } catch (_) {
        if (cached != null) return cached;
        final disk = await restoreCachedMingtaiOverview();
        if (disk != null) return disk;
        rethrow;
      }
      unawaited(_writeDiskMapList(_xiaouOverviewDiskCacheKey, rows));

      final overview = _buildMingtaiOverviewFromRows(rows);
      _mingtaiOverviewCache = overview;
      _mingtaiOverviewCacheAt = DateTime.now();
      return overview;
    })();
    _mingtaiOverviewInFlight = request;
    try {
      return _filterMingtaiOverview(await request, tag);
    } finally {
      if (identical(_mingtaiOverviewInFlight, request)) {
        _mingtaiOverviewInFlight = null;
      }
    }
  }

  static MingtaiOverview _buildMingtaiOverviewFromRows(
    List<Map<String, dynamic>> rows,
  ) {
    final tags = <String>{};
    final allItems = <Map<String, dynamic>>[];

    for (final row in rows) {
      final rowTags = _remoteTags(row['auto_tags']);
      tags.addAll(rowTags);
      final item = _remoteUserEntryToMingtaiItem(row);
      if (((item['remote_entry_id'] as String?) ?? '').isEmpty) {
        continue;
      }

      allItems.add(item);
    }

    return MingtaiOverview(
      items: allItems,
      allItems: allItems,
      tags: tags.where(_isInsightTag).toList()..sort(),
      insights: {
        7: _buildMingtaiInsight(allItems, 7),
        30: _buildMingtaiInsight(allItems, 30),
      },
    );
  }

  static MingtaiOverview _filterMingtaiOverview(
    MingtaiOverview overview,
    String? tag,
  ) {
    final normalizedTag = tag?.trim() ?? '';
    if (normalizedTag.isEmpty) return overview;
    return MingtaiOverview(
      items: overview.allItems.where((item) {
        return _parseTags(
          (item['ai_tags'] as String?) ?? '',
        ).contains(normalizedTag);
      }).toList(),
      allItems: overview.allItems,
      tags: overview.tags,
      insights: overview.insights,
    );
  }

  static Future<void> deleteMingtaiItem(String id) async {
    final db = await DatabaseService.database;
    if (id.startsWith('entry:')) {
      final remoteId = id.substring(6);
      if (remoteId.isEmpty) {
        throw Exception('远端 entry id 为空，无法删除线上数据');
      }

      final api = BmobApi.instance;
      if (api.isLoggedIn) {
        final deleted = await api.deleteUserEntry(remoteId);
        if (!deleted) {
          throw Exception('线上 entry 不存在或 DELETE /api/entries/:id 未生效');
        }
      } else {
        await deleteUserEntry(remoteId);
      }

      await db.delete(
        'user_entries',
        where: 'id = ? OR bmob_id = ?',
        whereArgs: [remoteId, remoteId],
      );
      _invalidateMingtaiOverviewCache();
      return;
    }
    await db.delete('mingtai_items', where: 'id = ?', whereArgs: [id]);
    _invalidateMingtaiOverviewCache();
  }

  static void _invalidateMingtaiBooksCache() {
    _mingtaiBooksCache = null;
    _mingtaiBooksCacheAt = null;
    _mingtaiBookDetailCache.clear();
    _mingtaiBookDetailCacheAt.clear();
    _mingtaiHomeCache = null;
    _mingtaiHomeCacheAt = null;
  }

  static void _invalidateMingtaiOverviewCache() {
    _mingtaiOverviewCache = null;
    _mingtaiOverviewCacheAt = null;
    _xiaouHomeInsightCache = null;
    _xiaouHomeInsightCacheAt = null;
  }

  static Map<String, dynamic> _remoteUserEntryToMingtaiItem(
    Map<String, dynamic> row,
  ) {
    final remoteId = row['id']?.toString() ?? '';
    final metadata = _metadataToRemote(row['metadata_json']);
    final aiExplanation = row['ai_explanation']?.toString() ?? '';
    final autoSummary = row['auto_summary']?.toString() ?? '';
    final understanding = aiExplanation.isNotEmpty
        ? aiExplanation
        : autoSummary;

    return {
      'id': remoteId.isNotEmpty ? 'entry:$remoteId' : '',
      'local_entry_id': metadata['local_id']?.toString() ?? '',
      'remote_entry_id': remoteId,
      'source': row['source']?.toString() ?? 'manual',
      'book_id': row['book_id']?.toString() ?? '',
      'book_title': row['book_title']?.toString() ?? '',
      'chapter_index': row['chapter_index']?.toString() ?? '',
      'chapter_title':
          row['chapter_title']?.toString() ??
          metadata['chapter_title']?.toString() ??
          '',
      'original_text': row['original_text']?.toString() ?? '',
      'user_note': row['user_input']?.toString() ?? '',
      'ai_tags': _remoteTags(row['auto_tags']).join(','),
      'ai_understanding': understanding,
      'created_at':
          row['created_at']?.toString() ??
          DateTime.now().toUtc().toIso8601String(),
      'updated_at': row['updated_at']?.toString() ?? '',
    };
  }

  static MingtaiInsight _buildMingtaiInsight(
    List<Map<String, dynamic>> items,
    int days,
  ) {
    final since = DateTime.now().subtract(Duration(days: days));
    final tagCounts = <String, int>{};
    final bookCounts = <String, int>{};
    final sourceCounts = <String, int>{};
    var entryCount = 0;

    for (final item in items) {
      final createdAt = _tryParseDate(item['created_at']);
      if (createdAt == null || createdAt.isBefore(since)) continue;

      entryCount++;
      for (final tag in _parseTags((item['ai_tags'] as String?) ?? '')) {
        if (!_isInsightTag(tag)) continue;
        tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
      }

      final bookTitle = (item['book_title'] as String?)?.trim() ?? '';
      if (bookTitle.isNotEmpty) {
        bookCounts[bookTitle] = (bookCounts[bookTitle] ?? 0) + 1;
      }

      final source = (item['source'] as String?)?.trim() ?? '';
      if (source.isNotEmpty) {
        sourceCounts[source] = (sourceCounts[source] ?? 0) + 1;
      }
    }

    final topTags = _topCountKeys(tagCounts, limit: 3);
    final topBooks = _topCountKeys(bookCounts, limit: 2);
    final topSources = _topCountKeys(sourceCounts, limit: 1);
    final topSource = topSources.isEmpty ? '' : topSources.first;

    return MingtaiInsight(
      days: days,
      entryCount: entryCount,
      topTags: topTags,
      topBooks: topBooks,
      topSource: topSource,
      summary: _buildMingtaiInsightSummary(
        entryCount: entryCount,
        topTags: topTags,
        topBooks: topBooks,
      ),
    );
  }

  static String _buildMingtaiInsightSummary({
    required int entryCount,
    required List<String> topTags,
    required List<String> topBooks,
  }) {
    return '';
  }

  static List<String> _topCountKeys(
    Map<String, int> counts, {
    required int limit,
  }) {
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) return countCompare;
        return a.key.compareTo(b.key);
      });
    return entries.take(limit).map((entry) => entry.key).toList();
  }

  static bool _isInsightTag(String tag) {
    const actionTags = {
      '划线',
      '想法',
      '小U解释',
      '手动',
      'highlight',
      'thought',
      'ai_explanation',
      'manual',
    };
    return !actionTags.contains(tag.trim());
  }

  static DateTime? _tryParseDate(Object? raw) {
    final value = raw?.toString() ?? '';
    if (value.isEmpty) return null;
    try {
      return DateTime.parse(value).toLocal();
    } catch (_) {
      return null;
    }
  }

  static Future<String> _findRemoteEntryIdByLocalId(String localId) async {
    final api = BmobApi.instance;
    try {
      final rows = await api.listUserEntries(limit: 500);
      for (final row in rows) {
        final remoteId = (row['id'] as String?) ?? '';
        if (remoteId == localId) return remoteId;

        final metadata = _metadataToRemote(row['metadata_json']);
        if (metadata['local_id'] == localId && remoteId.isNotEmpty) {
          return remoteId;
        }
      }
    } catch (_) {}
    return '';
  }

  static Future<void> _saveRemoteReadingProgressIfPossible({
    required String bookId,
    required double progress,
    required String chapterIndex,
    required double scrollOffset,
  }) async {
    final api = BmobApi.instance;
    if (!api.isLoggedIn) return;

    try {
      await api.saveReadingProgress(
        bookId: bookId,
        progress: progress,
        chapterIndex: chapterIndex,
        scrollOffset: scrollOffset,
      );
    } catch (_) {}
  }

  static Future<void> _pullRemoteReadingProgressIfPossible(
    Database db,
    String bookId,
  ) async {
    final api = BmobApi.instance;
    if (!api.isLoggedIn) return;

    try {
      final row = await api.getReadingProgress(bookId);
      if (row == null) return;

      final updatedAt =
          (row['updated_at'] as String?) ??
          DateTime.now().toUtc().toIso8601String();
      final localRows = await db.query(
        'reading_progress',
        columns: ['updatedAt', 'updated_at'],
        where: 'bookId = ?',
        whereArgs: [bookId],
        limit: 1,
      );
      if (localRows.isNotEmpty) {
        final localUpdatedAt =
            (localRows.first['updated_at'] as String?) ??
            (localRows.first['updatedAt'] as String?) ??
            '';
        if (localUpdatedAt.isNotEmpty &&
            !_isIsoDateAfter(updatedAt, localUpdatedAt)) {
          return;
        }
      }
      await db.insert('reading_progress', {
        'bookId': bookId,
        'user_id': (row['user_id'] as String?) ?? '',
        'chapterIndex': (row['chapter_index'] as String?) ?? '0',
        'scrollOffset': (row['scroll_offset'] as num?)?.toDouble() ?? 0.0,
        'updatedAt': updatedAt,
        'updated_at': updatedAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {}
  }

  static bool _isIsoDateAfter(String candidate, String baseline) {
    try {
      return DateTime.parse(candidate).isAfter(DateTime.parse(baseline));
    } catch (_) {
      return true;
    }
  }

  static Future<void> _createRemoteUserEntryIfPossible(
    Database db,
    UserEntry entry,
  ) async {
    final api = BmobApi.instance;
    if (!api.isLoggedIn) return;

    try {
      final result = await api.createUserEntry(_userEntryToRemote(entry));
      final objectId = result?['id'] as String?;
      if (objectId != null && objectId.isNotEmpty) {
        await db.update(
          'user_entries',
          {'bmob_id': objectId},
          where: 'id = ?',
          whereArgs: [entry.id],
        );
      }
    } catch (_) {
      // Keep local entry; SyncService can retry later.
    }
  }

  static Future<void> _pullRemoteUserEntriesIfPossible(
    Database db, {
    String? bookId,
    String? source,
    String? tag,
    DateTime? createdAtFrom,
    DateTime? createdAtTo,
  }) async {
    final api = BmobApi.instance;
    if (!api.isLoggedIn) return;

    try {
      final rows = await api.listUserEntries(
        bookId: bookId,
        source: source,
        tag: tag,
        createdAtFrom: createdAtFrom?.toIso8601String(),
        createdAtTo: createdAtTo?.toIso8601String(),
        limit: 500,
      );
      for (final row in rows) {
        await db.insert(
          'user_entries',
          _remoteUserEntryToLocal(row),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (_) {
      // Local cache remains the source of truth while offline.
    }
  }

  static Map<String, dynamic> _userEntryToRemote(UserEntry entry) {
    final metadata = _metadataToRemote(entry.metadataJson);
    metadata['local_id'] = entry.id;
    if (entry.chapterTitle.isNotEmpty) {
      metadata['chapter_title'] = entry.chapterTitle;
    }
    return {
      'source': entry.source,
      'book_id': entry.bookId,
      'book_title': entry.bookTitle,
      'chapter_index': entry.chapterIndex,
      'chapter_title': entry.chapterTitle,
      'original_text': entry.originalText,
      'user_input': entry.userInput,
      'ai_explanation': entry.aiExplanation,
      'auto_tags': entry.autoTags,
      'auto_summary': entry.autoSummary,
      'metadata_json': metadata,
    };
  }

  static Map<String, dynamic> _remoteUserEntryToLocal(
    Map<String, dynamic> row,
  ) {
    final metadata = _metadataToRemote(row['metadata_json']);
    final remoteId = (row['id'] as String?) ?? '';
    final localId = (metadata['local_id'] as String?) ?? remoteId;
    return {
      'id': localId,
      'user_id': (row['user_id'] as String?) ?? '',
      'source': (row['source'] as String?) ?? 'manual',
      'book_id': (row['book_id'] as String?) ?? '',
      'book_title': (row['book_title'] as String?) ?? '',
      'chapter_index': (row['chapter_index'] as String?) ?? '',
      'chapter_title':
          row['chapter_title']?.toString() ??
          metadata['chapter_title']?.toString() ??
          '',
      'original_text': (row['original_text'] as String?) ?? '',
      'user_input': (row['user_input'] as String?) ?? '',
      'ai_explanation': (row['ai_explanation'] as String?) ?? '',
      'auto_tags': _remoteTagsToLocal(row['auto_tags']),
      'auto_summary': (row['auto_summary'] as String?) ?? '',
      'metadata_json': jsonEncode(metadata),
      'embedding': '',
      'created_at':
          (row['created_at'] as String?) ??
          (row['createdAt'] as String?) ??
          DateTime.now().toUtc().toIso8601String(),
      'updated_at': (row['updatedAt'] as String?) ?? '',
      'bmob_id': remoteId,
    };
  }

  static Map<String, dynamic> _metadataToRemote(Object? metadata) {
    if (metadata is Map<String, dynamic>) {
      return Map<String, dynamic>.from(metadata);
    }
    if (metadata is Map) {
      return metadata.map((key, value) => MapEntry(key.toString(), value));
    }
    if (metadata is String && metadata.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(metadata);
        if (decoded is Map<String, dynamic>) {
          return Map<String, dynamic>.from(decoded);
        }
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {}
    }
    return {};
  }

  static String _remoteTagsToLocal(Object? tags) {
    final parsedTags = _remoteTags(tags);
    if (parsedTags.isNotEmpty) return jsonEncode(parsedTags);
    return tags?.toString() ?? '';
  }

  static List<String> _remoteTags(Object? tags) {
    if (tags is List) {
      return tags
          .map((tag) => tag.toString().trim())
          .where((tag) => tag.isNotEmpty)
          .toList();
    }
    if (tags is String && tags.trim().isNotEmpty) {
      return _parseTags(tags);
    }
    return [];
  }

  static List<String> _parseTags(String raw) {
    if (raw.isEmpty) return [];
    final cleaned = raw.trim();
    if (cleaned.startsWith('[') && cleaned.endsWith(']')) {
      return cleaned
          .substring(1, cleaned.length - 1)
          .split(',')
          .map((tag) => tag.trim().replaceAll('"', '').replaceAll("'", ''))
          .where((tag) => tag.isNotEmpty)
          .toList();
    }
    return raw
        .split(',')
        .map(
          (tag) => tag
              .trim()
              .replaceAll('"', '')
              .replaceAll('[', '')
              .replaceAll(']', ''),
        )
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  static Future<Map<String, dynamic>?> _readDiskMap(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static Future<List<Map<String, dynamic>>?> _readDiskMapList(
    String key,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _writeDiskMap(
    String key,
    Map<String, dynamic> value,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(value));
    } catch (_) {}
  }

  static Future<void> _writeDiskMapList(
    String key,
    List<Map<String, dynamic>> value,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(value));
    } catch (_) {}
  }
}
