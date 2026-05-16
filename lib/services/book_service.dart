import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import '../models/book.dart';
import '../models/bookmark.dart';
import '../models/highlight.dart';
import '../models/ai_conversation.dart';
import '../models/user_entry.dart';
import 'bmob_api.dart';
import 'database_service.dart';

class BookService {
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

  static Future<void> updateHighlightNote(
      String id, String? note) async {
    final db = await DatabaseService.database;
    await db.update('highlights', {'note': note},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteHighlight(String id) async {
    final db = await DatabaseService.database;
    await db.delete('highlights', where: 'id = ?', whereArgs: [id]);
  }

  // ---- AI Messages ----

  static Future<List<AiMessage>> getAiMessages(
      String bookId, {int limit = 6}) async {
    final db = await DatabaseService.database;
    final maps = await db.query('ai_messages',
        where: 'bookId = ?',
        whereArgs: [bookId],
        orderBy: 'timestamp DESC',
        limit: limit);
    return maps.reversed.map((m) => AiMessage.fromMap(m)).toList();
  }

  static Future<void> insertAiMessage(
      String bookId, AiMessage msg) async {
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

  static Future<void> saveReadingProgress(
      String bookId, String chapterIndex, double scrollOffset,
      {String userId = '', String updatedAt = ''}) async {
    final db = await DatabaseService.database;
    await db.insert('reading_progress', {
      'bookId': bookId,
      'user_id': userId,
      'chapterIndex': chapterIndex,
      'scrollOffset': scrollOffset,
      'updatedAt': updatedAt.isNotEmpty ? updatedAt : DateTime.now().toIso8601String(),
      'updated_at': updatedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
    await db.delete('user_entries', where: 'id = ?', whereArgs: [id]);
  }

  // ---- MingTai ----

  static Future<void> insertMingtaiItem(Map<String, dynamic> item) async {
    final db = await DatabaseService.database;
    await db.insert('mingtai_items', item, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Map<String, dynamic>>> getMingtaiItems({String? tag}) async {
    final db = await DatabaseService.database;
    final entries = await getUserEntries(tag: tag);
    final entryItems = entries.map(_userEntryToMingtaiItem).toList();

    final legacyRows = await db.query(
      'mingtai_items',
      where: tag != null && tag.isNotEmpty ? 'ai_tags LIKE ?' : null,
      whereArgs: tag != null && tag.isNotEmpty ? ['%$tag%'] : null,
      orderBy: 'created_at DESC',
    );
    final legacyItems = legacyRows.map((m) => Map<String, dynamic>.from(m));

    final items = [...entryItems, ...legacyItems];
    items.sort((a, b) {
      final bTime = (b['created_at'] as String?) ?? '';
      final aTime = (a['created_at'] as String?) ?? '';
      return bTime.compareTo(aTime);
    });
    return items;
  }

  static Future<List<String>> getMingtaiTags() async {
    final db = await DatabaseService.database;
    final tags = <String>{};
    tags.addAll(await getUserEntryTags());

    final maps = await db.query('mingtai_items', columns: ['ai_tags']);
    for (final m in maps) {
      tags.addAll(_parseTags((m['ai_tags'] as String?) ?? ''));
    }
    return tags.toList()..sort();
  }

  static Future<void> deleteMingtaiItem(String id) async {
    final db = await DatabaseService.database;
    if (id.startsWith('entry:')) {
      await deleteUserEntry(id.substring(6));
      return;
    }
    await db.delete('mingtai_items', where: 'id = ?', whereArgs: [id]);
  }

  static Map<String, dynamic> _userEntryToMingtaiItem(UserEntry entry) {
    final understanding = entry.aiExplanation.isNotEmpty
        ? entry.aiExplanation
        : entry.autoSummary;
    return {
      'id': 'entry:${entry.id}',
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

  static Future<void> _createRemoteUserEntryIfPossible(
      Database db, UserEntry entry) async {
    final api = BmobApi.instance;
    if (!api.isLoggedIn) return;

    try {
      final result = await api.createUserEntry(_userEntryToRemote(entry));
      final objectId = result?['objectId'] as String?;
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
    return {
      'local_id': entry.id,
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
      'metadata_json': entry.metadataJson,
      'embedding': entry.embedding,
      'created_at': entry.createdAt.toIso8601String(),
    };
  }

  static Map<String, dynamic> _remoteUserEntryToLocal(
      Map<String, dynamic> row) {
    return {
      'id': (row['local_id'] as String?) ?? (row['objectId'] as String),
      'user_id': (row['user_id'] as String?) ?? '',
      'source': (row['source'] as String?) ?? 'manual',
      'book_id': (row['book_id'] as String?) ?? '',
      'book_title': (row['book_title'] as String?) ?? '',
      'chapter_index': (row['chapter_index'] as String?) ?? '',
      'chapter_title': (row['chapter_title'] as String?) ?? '',
      'original_text': (row['original_text'] as String?) ?? '',
      'user_input': (row['user_input'] as String?) ?? '',
      'ai_explanation': (row['ai_explanation'] as String?) ?? '',
      'auto_tags': _remoteTagsToLocal(row['auto_tags']),
      'auto_summary': (row['auto_summary'] as String?) ?? '',
      'metadata_json': (row['metadata_json'] as String?) ?? '',
      'embedding': (row['embedding'] as String?) ?? '',
      'created_at': (row['created_at'] as String?) ??
          (row['createdAt'] as String?) ??
          DateTime.now().toUtc().toIso8601String(),
      'updated_at': (row['updatedAt'] as String?) ?? '',
      'bmob_id': (row['objectId'] as String?) ?? '',
    };
  }

  static String _remoteTagsToLocal(Object? tags) {
    if (tags is List) {
      return jsonEncode(tags.map((tag) => tag.toString()).toList());
    }
    return tags?.toString() ?? '';
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
        .map((tag) => tag.trim().replaceAll('"', '').replaceAll('[', '').replaceAll(']', ''))
        .where((tag) => tag.isNotEmpty)
        .toList();
  }
}
