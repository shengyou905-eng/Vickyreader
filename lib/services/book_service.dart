import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import '../models/book.dart';
import '../models/bookmark.dart';
import '../models/highlight.dart';
import '../models/ai_conversation.dart';
import '../models/user_entry.dart';
import 'bmob_api.dart';
import 'database_service.dart';

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
      summary: '最近还没有新的阅读痕迹，继续读一点，小U会在这里帮你回顾。',
    );
  }
}

class MingtaiQuestionAnswer {
  final String questionId;
  final String question;
  final String answer;
  final DateTime? generatedAt;

  const MingtaiQuestionAnswer({
    required this.questionId,
    required this.question,
    required this.answer,
    this.generatedAt,
  });
}

class BookService {
  static const Map<String, String> _sourceLabels = {
    'highlight': '划线',
    'thought': '想法',
    'ai_explanation': 'AI解释',
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
    await db.insert('books', book.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> updateBook(Book book) async {
    final db = await DatabaseService.database;
    await db.update('books', book.toMap(),
        where: 'id = ?', whereArgs: [book.id]);
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
    final maps = await db.query('highlights',
        where: 'bookId = ?', whereArgs: [bookId], orderBy: 'createdAt DESC');
    return maps.map((m) => Highlight.fromMap(m)).toList();
  }

  static Future<List<Highlight>> getAllHighlights() async {
    final db = await DatabaseService.database;
    final maps = await db.query('highlights', orderBy: 'createdAt DESC');
    return maps.map((m) => Highlight.fromMap(m)).toList();
  }

  static Future<void> insertHighlight(Highlight h) async {
    final db = await DatabaseService.database;
    await db.insert('highlights', h.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> updateHighlightNote(String id, String? note) async {
    final db = await DatabaseService.database;
    await db.update('highlights', {'note': note},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteHighlight(String id) async {
    final db = await DatabaseService.database;
    await db.delete('highlights', where: 'id = ?', whereArgs: [id]);
  }

  // ---- AI Messages ----

  static Future<List<AiMessage>> getAiMessages(String bookId, {int limit = 6}) async {
    final db = await DatabaseService.database;
    final maps = await db.query('ai_messages',
        where: 'bookId = ?',
        whereArgs: [bookId],
        orderBy: 'timestamp DESC',
        limit: limit);
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

    final maps = await db.query('reading_progress',
        where: 'bookId = ?', whereArgs: [bookId]);
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
      String bookId, String chapterIndex, double scrollOffset,
      {String userId = '', String updatedAt = ''}) async {
    final db = await DatabaseService.database;
    final now = updatedAt.isNotEmpty ? updatedAt : DateTime.now().toUtc().toIso8601String();
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

  // ---- Bookmarks ----

  static Future<List<Bookmark>> getAllBookmarks() async {
    final db = await DatabaseService.database;
    final maps = await db.query('bookmarks', orderBy: 'createdAt DESC');
    return maps.map((m) => Bookmark.fromMap(m)).toList();
  }

  static Future<List<Bookmark>> getBookmarks(String bookId) async {
    final db = await DatabaseService.database;
    final maps = await db.query('bookmarks',
        where: 'bookId = ?', whereArgs: [bookId], orderBy: 'createdAt DESC');
    return maps.map((m) => Bookmark.fromMap(m)).toList();
  }

  static Future<void> insertBookmark(Bookmark bm) async {
    final db = await DatabaseService.database;
    await db.insert('bookmarks', bm.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> deleteBookmark(String id) async {
    final db = await DatabaseService.database;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  static Future<bool> hasBookmark(String bookId, String chapterIndex) async {
    final db = await DatabaseService.database;
    final maps = await db.query('bookmarks',
        where: 'bookId = ? AND chapterIndex = ?',
        whereArgs: [bookId, chapterIndex]);
    return maps.isNotEmpty;
  }

  // ---- User Entries ----

  static Future<void> insertUserEntry(UserEntry entry) async {
    final db = await DatabaseService.database;
    await db.insert('user_entries', entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    await _createRemoteUserEntryIfPossible(db, entry);
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
    final remoteId = rows.isNotEmpty ? (rows.first['bmob_id'] as String? ?? '') : '';
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

  static Future<MingtaiQuestionAnswer> answerMingtaiQuestion(String questionId) async {
    final data = await BmobApi.instance.answerInsightQuestion(questionId);
    return MingtaiQuestionAnswer(
      questionId: data['question_id']?.toString() ?? questionId,
      question: data['question']?.toString() ?? '',
      answer: data['answer']?.toString() ?? '',
      generatedAt: _tryParseDate(data['generated_at']),
    );
  }

  static Future<List<Map<String, dynamic>>> getMingtaiItems({String? tag}) async {
    final overview = await getMingtaiOverview(tag: tag);
    return overview.items;
  }

  static Future<List<String>> getMingtaiTags() async {
    final overview = await getMingtaiOverview();
    return overview.tags;
  }

  static Future<MingtaiOverview> getMingtaiOverview({String? tag}) async {
    final api = BmobApi.instance;
    if (!api.isLoggedIn) {
      return MingtaiOverview(
        items: const [],
        allItems: const [],
        tags: const [],
        insights: {
          7: MingtaiInsight.empty(7),
          30: MingtaiInsight.empty(30),
        },
      );
    }

    final rows = await api.listUserEntries(limit: 500);
    final tags = <String>{};
    final items = <Map<String, dynamic>>[];
    final allItems = <Map<String, dynamic>>[];

    for (final row in rows) {
      final rowTags = _remoteTags(row['auto_tags']);
      tags.addAll(rowTags);
      final item = _remoteUserEntryToMingtaiItem(row);
      if (((item['remote_entry_id'] as String?) ?? '').isEmpty) {
        continue;
      }

      allItems.add(item);

      if (tag != null && tag.isNotEmpty && !rowTags.contains(tag)) {
        continue;
      }

      items.add(item);
    }

    return MingtaiOverview(
      items: items,
      allItems: allItems,
      tags: tags.where(_isInsightTag).toList()..sort(),
      insights: {
        7: _buildMingtaiInsight(allItems, 7),
        30: _buildMingtaiInsight(allItems, 30),
      },
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
      return;
    }
    await db.delete('mingtai_items', where: 'id = ?', whereArgs: [id]);
  }

  static Map<String, dynamic> _userEntryToMingtaiItem(UserEntry entry) {
    final understanding = entry.aiExplanation.isNotEmpty
        ? entry.aiExplanation
        : entry.autoSummary;
    final entryId = entry.bmobId.isNotEmpty ? entry.bmobId : entry.id;
    return {
      'id': 'entry:$entryId',
      'local_entry_id': entry.id,
      'remote_entry_id': entry.bmobId,
      'source': entry.source,
      'book_id': entry.bookId,
      'book_title': entry.bookTitle,
      'chapter_index': entry.chapterIndex,
      'original_text': entry.originalText,
      'user_note': entry.userInput,
      'ai_tags': entry.autoTags.join(','),
      'ai_understanding': understanding,
      'created_at': entry.createdAt.toIso8601String(),
      'updated_at': entry.updatedAt,
    };
  }

  static Map<String, dynamic> _remoteUserEntryToMingtaiItem(
    Map<String, dynamic> row,
  ) {
    final remoteId = row['id']?.toString() ?? '';
    final metadata = _metadataToRemote(row['metadata_json']);
    final aiExplanation = row['ai_explanation']?.toString() ?? '';
    final autoSummary = row['auto_summary']?.toString() ?? '';
    final understanding = aiExplanation.isNotEmpty ? aiExplanation : autoSummary;

    return {
      'id': remoteId.isNotEmpty ? 'entry:$remoteId' : '',
      'local_entry_id': metadata['local_id']?.toString() ?? '',
      'remote_entry_id': remoteId,
      'source': row['source']?.toString() ?? 'manual',
      'book_id': row['book_id']?.toString() ?? '',
      'book_title': row['book_title']?.toString() ?? '',
      'chapter_index': row['chapter_index']?.toString() ?? '',
      'chapter_title': row['chapter_title']?.toString() ??
          metadata['chapter_title']?.toString() ??
          '',
      'original_text': row['original_text']?.toString() ?? '',
      'user_note': row['user_input']?.toString() ?? '',
      'ai_tags': _remoteTags(row['auto_tags']).join(','),
      'ai_understanding': understanding,
      'created_at': row['created_at']?.toString() ??
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
    if (entryCount == 0) {
      return '最近还没有新的阅读痕迹，继续读一点，小U会在这里帮你回顾。';
    }

    if (topTags.length >= 2) {
      return '你最近频繁记录关于「${topTags[0]}」与「${topTags[1]}」的内容。';
    }
    if (topTags.length == 1) {
      return '你最近频繁记录关于「${topTags[0]}」的内容。';
    }

    if (topBooks.length >= 2) {
      return '你最近主要在回顾《${topBooks[0]}》和《${topBooks[1]}》里的内容。';
    }
    if (topBooks.length == 1) {
      return '你最近主要在回顾《${topBooks[0]}》里的内容。';
    }

    return '最近留下了 $entryCount 条阅读痕迹，小U会慢慢帮你聚拢它们。';
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
      'AI解释',
      'AI 解释',
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

      final updatedAt = (row['updated_at'] as String?) ??
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
      await db.insert(
        'reading_progress',
        {
          'bookId': bookId,
          'user_id': (row['user_id'] as String?) ?? '',
          'chapterIndex': (row['chapter_index'] as String?) ?? '0',
          'scrollOffset': (row['scroll_offset'] as num?)?.toDouble() ?? 0.0,
          'updatedAt': updatedAt,
          'updated_at': updatedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  static bool _isIsoDateAfter(String candidate, String baseline) {
    try {
      return DateTime.parse(candidate).isAfter(DateTime.parse(baseline));
    } catch (_) {
      return true;
    }
  }

  static Future<void> _createRemoteUserEntryIfPossible(Database db, UserEntry entry) async {
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

  static Map<String, dynamic> _remoteUserEntryToLocal(Map<String, dynamic> row) {
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
      'chapter_title': row['chapter_title']?.toString() ??
          metadata['chapter_title']?.toString() ??
          '',
      'original_text': (row['original_text'] as String?) ?? '',
      'user_input': (row['user_input'] as String?) ?? '',
      'ai_explanation': (row['ai_explanation'] as String?) ?? '',
      'auto_tags': _remoteTagsToLocal(row['auto_tags']),
      'auto_summary': (row['auto_summary'] as String?) ?? '',
      'metadata_json': jsonEncode(metadata),
      'embedding': '',
      'created_at': (row['created_at'] as String?) ??
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
        .map((tag) => tag
            .trim()
            .replaceAll('"', '')
            .replaceAll('[', '')
            .replaceAll(']', ''))
        .where((tag) => tag.isNotEmpty)
        .toList();
  }
}
