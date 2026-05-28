import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';
import 'bmob_api.dart';

class SyncService {
  static const _lastSyncKey = 'bmob_last_sync_time';
  static const _syncTables = [
    'books',
    'highlights',
    'notes',
    'reading_progress',
    'bookmarks',
    'user_entries',
  ];
  String? _userId;

  SyncService._();
  static final SyncService instance = SyncService._();

  void setUserId(String? userId) {
    _userId = userId;
  }

  /// Full sync: pull then push

  /// Pull remote changes and merge into local DB
  Future<void> pullAll() async {
    if (_userId == null || _userId!.isEmpty) return;
    final lastSync = await _getLastSyncTime();
    final db = await DatabaseService.database;
    final api = BmobApi.instance;

    for (final table in _syncTables) {
      await _pullTable(db, api, table, lastSync);
    }

    await _setLastSyncTime(DateTime.now().toUtc().toIso8601String());
  }

  Future<void> _pullTable(
      Database db, BmobApi api, String table, String lastSync) async {
    try {
      final whereClause = _userId != null
          ? '{"user_id":"$_userId","updatedAt":{"\$gt":"$lastSync"}}'
          : null;
      final bmobTable = table;
      final rows = await api.select(bmobTable,
          whereJson: whereClause, order: 'updatedAt', limit: 500);

      for (final r in rows) {
        final bmobId = r['objectId'] as String;
        final local = await db.query(table,
            where: 'bmob_id = ?', whereArgs: [bmobId]);
        final localRecord = local.isNotEmpty ? local.first : null;

        try {
          if (localRecord == null) {
            // New remote record — insert locally
            final localMap = _toLocal(table, r, bmobId);
            await db.insert(table, localMap,
                conflictAlgorithm: ConflictAlgorithm.replace);
          } else {
            // Compare timestamps, keep newer
            final localUpdated = localRecord['updated_at'] as String? ?? '';
            final remoteUpdated = r['updatedAt'] as String? ?? '';
            if (remoteUpdated.compareTo(localUpdated) > 0) {
              final localMap = _toLocal(table, r, bmobId);
              await db.update(table, localMap,
                  where: 'bmob_id = ?', whereArgs: [bmobId]);
            }
          }
        } catch (e) {
          debugPrint('[SyncService] pullTable($table) merge error for $bmobId: $e');
        }
      }
    } catch (e) {
      debugPrint('[SyncService] pullTable($table) error: $e');
    }
  }

  /// Push local changes to remote
  Future<void> pushAll() async {
    if (_userId == null || _userId!.isEmpty) return;
    final lastSync = await _getLastSyncTime();
    final db = await DatabaseService.database;
    final api = BmobApi.instance;

    for (final table in _syncTables) {
      await _pushTable(db, api, table, lastSync);
    }

    await _setLastSyncTime(DateTime.now().toUtc().toIso8601String());
  }

  Future<void> _pushTable(
      Database db, BmobApi api, String table, String lastSync) async {
    try {
      List<Map<String, dynamic>> records;
      if (lastSync.isNotEmpty) {
        records = await db.query(table,
            where: "updated_at > ? AND user_id = ?",
            whereArgs: [lastSync, _userId!],
            limit: 500);
      } else {
        records = await db.query(table,
            where: 'user_id = ?',
            whereArgs: [_userId!],
            limit: 500);
      }

      final bmobTable = table;
      for (final r in records) {
        final remoteMap = _toRemote(table, r);
        final bmobId = r['bmob_id'] as String? ?? '';

        try {
          if (bmobId.isNotEmpty) {
            // Update existing remote record
            await api.update(bmobTable, bmobId, remoteMap);
            final keyColumn = _localKeyColumn(table);
            await db.update(table, {'bmob_id': bmobId},
                where: '$keyColumn = ?', whereArgs: [r[keyColumn]]);
          } else {
            // Create new remote record
            final result = await api.create(bmobTable, remoteMap);
            if (result != null) {
              final newBmobId = result['objectId'] as String;
              final keyColumn = _localKeyColumn(table);
              await db.update(table, {'bmob_id': newBmobId},
                  where: '$keyColumn = ?', whereArgs: [r[keyColumn]]);
            }
          }
        } catch (e) {
          final keyColumn = _localKeyColumn(table);
          debugPrint(
            '[SyncService] pushTable($table) error for ${r[keyColumn]}: $e',
          );
        }
      }
    } catch (e) {
      debugPrint('[SyncService] pushTable($table) error: $e');
    }
  }

  /// Merge anonymous data into a user account after login
  Future<void> mergeAnonymousData(String newUserId) async {
    final db = await DatabaseService.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.update('books',
        {'user_id': newUserId, 'updated_at': now},
        where: "user_id = '' OR user_id IS NULL");
    await db.update('highlights',
        {'user_id': newUserId, 'updated_at': now},
        where: "user_id = '' OR user_id IS NULL");
    await db.update('notes',
        {'user_id': newUserId, 'updated_at': now},
        where: "user_id = '' OR user_id IS NULL");
    await db.update('reading_progress',
        {'user_id': newUserId, 'updated_at': now},
        where: "user_id = '' OR user_id IS NULL");
    await db.update('bookmarks',
        {'user_id': newUserId, 'updated_at': now},
        where: "user_id = '' OR user_id IS NULL");
    await db.update('user_entries',
        {'user_id': newUserId, 'updated_at': now},
        where: "user_id = '' OR user_id IS NULL");
    await db.execute('''
      CREATE TABLE IF NOT EXISTS free_notes (
        id TEXT PRIMARY KEY,
        user_id TEXT DEFAULT '',
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.update('free_notes',
        {'user_id': newUserId, 'updated_at': now},
        where: "user_id = '' OR user_id IS NULL");

    _userId = newUserId;
    await _setLastSyncTime('');
    await pushAll();
  }

  // ---- Helpers ----

  Future<String> _getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_lastSyncKey}_${_userId ?? 'anon'}';
    return prefs.getString(key) ?? '';
  }

  Future<void> _setLastSyncTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_lastSyncKey}_${_userId ?? 'anon'}';
    if (time.isNotEmpty) {
      await prefs.setString(key, time);
    } else {
      await prefs.remove(key);
    }
  }

  // Column mapping: Bmob remote → SQLite local
  Map<String, dynamic> _toLocal(
      String table, Map<String, dynamic> r, String bmobId) {
    final now = DateTime.now().toUtc().toIso8601String();
    switch (table) {
      case 'books':
        return {
          'id': r['local_id'] ?? bmobId,
          'bmob_id': bmobId,
          'user_id': r['user_id'] ?? '',
          'title': r['title'] ?? '',
          'author': r['author'] ?? '',
          'coverPath': r['cover_path'] ?? '',
          'filePath': r['file_path'] ?? '',
          'format': r['format'] ?? 'epub',
          'description': r['description'] ?? '',
          'addedAt': r['added_at'] ?? now,
          'lastOpenedAt': r['last_opened_at'] ?? now,
          'readingProgress': r['reading_progress'] ?? 0.0,
          'chapterTitles': r['chapter_titles'] ?? '',
          'updated_at': r['updatedAt'] ?? now,
        };
      case 'highlights':
        return {
          'id': r['local_id'] ?? bmobId,
          'bmob_id': bmobId,
          'user_id': r['user_id'] ?? '',
          'bookId': r['book_id'] ?? '',
          'chapterIndex': r['chapter_index'] ?? '',
          'selectedText': r['selected_text'] ?? '',
          'contextBefore': r['context_before'] ?? '',
          'contextAfter': r['context_after'] ?? '',
          'startOffset': r['start_offset'] ?? 0,
          'endOffset': r['end_offset'] ?? 0,
          'color': r['color'] ?? '#B39DDB',
          'note': r['note'] ?? '',
          'createdAt': r['created_at'] ?? now,
          'updated_at': r['updatedAt'] ?? now,
        };
      case 'notes':
        return {
          'id': r['local_id'] ?? bmobId,
          'bmob_id': bmobId,
          'user_id': r['user_id'] ?? '',
          'bookId': r['book_id'] ?? '',
          'chapterIndex': r['chapter_index'] ?? '',
          'selectedText': r['selected_text'] ?? '',
          'chapterTitle': r['chapter_title'] ?? '',
          'content': r['content'] ?? '',
          'createdAt': r['created_at'] ?? now,
          'updatedAt': r['updatedAt'] ?? now,
          'updated_at': r['updatedAt'] ?? now,
        };
      case 'reading_progress':
        return {
          'bookId': r['book_id'] ?? bmobId,
          'bmob_id': bmobId,
          'user_id': r['user_id'] ?? '',
          'chapterIndex': r['chapter_index'] ?? '',
          'scrollOffset': r['scroll_offset'] ?? 0.0,
          'updatedAt': r['updatedAt'] ?? now,
          'updated_at': r['updatedAt'] ?? now,
        };
      case 'bookmarks':
        return {
          'id': r['local_id'] ?? bmobId,
          'bmob_id': bmobId,
          'user_id': r['user_id'] ?? '',
          'bookId': r['book_id'] ?? '',
          'chapterIndex': r['chapter_index'] ?? '',
          'chapterTitle': r['chapter_title'] ?? '',
          'snippet': r['snippet'] ?? '',
          'scrollOffset': r['scroll_offset'] ?? 0.0,
          'progress': r['progress'] ?? 0.0,
          'createdAt': r['created_at'] ?? now,
          'updated_at': r['updatedAt'] ?? now,
        };
      case 'user_entries':
        return {
          'id': r['local_id'] ?? bmobId,
          'bmob_id': bmobId,
          'user_id': r['user_id'] ?? '',
          'source': r['source'] ?? 'manual',
          'book_id': r['book_id'] ?? '',
          'book_title': r['book_title'] ?? '',
          'chapter_index': r['chapter_index'] ?? '',
          'chapter_title': r['chapter_title'] ?? '',
          'original_text': r['original_text'] ?? '',
          'user_input': r['user_input'] ?? '',
          'ai_explanation': r['ai_explanation'] ?? '',
          'auto_tags': _stringifyRemoteValue(r['auto_tags']),
          'auto_summary': r['auto_summary'] ?? '',
          'metadata_json': r['metadata_json'] ?? '',
          'embedding': r['embedding'] ?? '',
          'created_at': r['created_at'] ?? now,
          'updated_at': r['updatedAt'] ?? now,
        };
      default:
        return {};
    }
  }

  // Column mapping: SQLite local → Bmob remote
  Map<String, dynamic> _toRemote(String table, Map<String, dynamic> l) {
    final now = DateTime.now().toUtc().toIso8601String();
    switch (table) {
      case 'books':
        return {
          'local_id': l['id'],
          'user_id': l['user_id'] ?? _userId,
          'title': l['title'],
          'author': l['author'],
          'cover_path': l['coverPath'],
          'file_path': l['filePath'],
          'format': l['format'],
          'description': l['description'],
          'added_at': l['addedAt'],
          'last_opened_at': l['lastOpenedAt'],
          'reading_progress': l['readingProgress'],
          'chapter_titles': l['chapterTitles'],
          'updatedAt': l['updated_at'] ?? now,
        };
      case 'highlights':
        return {
          'local_id': l['id'],
          'user_id': l['user_id'] ?? _userId,
          'book_id': l['bookId'],
          'chapter_index': l['chapterIndex'],
          'selected_text': l['selectedText'],
          'context_before': l['contextBefore'],
          'context_after': l['contextAfter'],
          'start_offset': l['startOffset'],
          'end_offset': l['endOffset'],
          'color': l['color'],
          'note': l['note'],
          'created_at': l['createdAt'],
          'updatedAt': l['updated_at'] ?? now,
        };
      case 'notes':
        return {
          'local_id': l['id'],
          'user_id': l['user_id'] ?? _userId,
          'book_id': l['bookId'],
          'chapter_index': l['chapterIndex'],
          'selected_text': l['selectedText'],
          'chapter_title': l['chapterTitle'],
          'content': l['content'],
          'created_at': l['createdAt'],
          'updatedAt': l['updated_at'] ?? now,
        };
      case 'reading_progress':
        return {
          'local_id': l['bookId'],
          'user_id': l['user_id'] ?? _userId,
          'book_id': l['bookId'],
          'chapter_index': l['chapterIndex'],
          'scroll_offset': l['scrollOffset'],
          'updatedAt': l['updated_at'] ?? now,
        };
      case 'bookmarks':
        return {
          'local_id': l['id'],
          'user_id': l['user_id'] ?? _userId,
          'book_id': l['bookId'],
          'chapter_index': l['chapterIndex'],
          'chapter_title': l['chapterTitle'],
          'snippet': l['snippet'],
          'scroll_offset': l['scrollOffset'],
          'progress': l['progress'],
          'created_at': l['createdAt'],
          'updatedAt': now,
        };
      case 'user_entries':
        return {
          'local_id': l['id'],
          'user_id': l['user_id'] ?? _userId,
          'source': l['source'],
          'book_id': l['book_id'],
          'book_title': l['book_title'],
          'chapter_index': l['chapter_index'],
          'chapter_title': l['chapter_title'],
          'original_text': l['original_text'],
          'user_input': l['user_input'],
          'ai_explanation': l['ai_explanation'],
          'auto_tags': l['auto_tags'],
          'auto_summary': l['auto_summary'],
          'metadata_json': l['metadata_json'],
          'embedding': l['embedding'],
          'created_at': l['created_at'],
          'updatedAt': l['updated_at'] ?? now,
        };
      default:
        return {};
    }
  }

  String _localKeyColumn(String table) {
    return table == 'reading_progress' ? 'bookId' : 'id';
  }

  String _stringifyRemoteValue(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    return jsonEncode(value);
  }
}
