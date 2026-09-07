import 'dart:convert';
import 'dart:io';

import 'package:ai_reader/models/book.dart';
import 'package:ai_reader/services/book_service.dart';
import 'package:ai_reader/services/database_service.dart';
import 'package:ai_reader/services/reliable_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Remote implements ReliableUploadClient {
  final traces = <String>{'trace'};
  final progresses = <String>{'book'};
  List<Map<String, dynamic>> books = [];
  @override
  Future<void> replaceLibraryBooks(List<Map<String, dynamic>> value) async {
    books = value;
  }

  @override
  Future<void> deleteTrace(String id, Map<String, dynamic> version) async {
    traces.remove(id);
  }

  @override
  Future<void> deleteReadingProgress(
    String id,
    Map<String, dynamic> version,
  ) async {
    progresses.remove(id);
  }

  @override
  Future<void> permanentlyDeleteBookData(String id) async {
    traces.clear();
    progresses.remove(id);
    books.removeWhere((book) => book['book_id'] == id);
  }

  @override
  Future<void> upsertReadingProgress(Map<String, dynamic> payload) async {
    progresses.add(payload['book_id'] as String);
  }

  @override
  Future<Map<String, dynamic>?> upsertTrace(
    String id,
    Map<String, dynamic> payload,
  ) async {
    traces.add(id);
    return null;
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late Database db;
  late Book book;
  test(
    'late remote progress GET cannot overwrite a pending or acknowledged local revision',
    () async {
      final incoming = {
        'user_id': 'user-a',
        'book_id': 'book',
        'chapter_index': '9',
        'scroll_offset': 99,
        'updated_at': '2099-01-01',
      };
      await BookService.applyRemoteReadingProgress(
        db,
        'book',
        'user-a',
        incoming,
        isCurrentUser: () => false,
      );
      expect((await db.query('reading_progress')).single['scrollOffset'], 42);
      await ReliableUploadService.instance.enqueueReadingProgress(
        db,
        userId: 'user-a',
        bookId: 'book',
        operation: 'upsert',
        payload: {'book_id': 'book', 'progress': 0.8},
      );
      await BookService.applyRemoteReadingProgress(
        db,
        'book',
        'user-a',
        incoming,
        isCurrentUser: () => true,
      );
      expect((await db.query('reading_progress')).single['scrollOffset'], 42);
      await db.delete('pending_upload_operations');
      await BookService.applyRemoteReadingProgress(
        db,
        'book',
        'user-a',
        incoming,
        isCurrentUser: () => true,
      );
      expect((await db.query('reading_progress')).single['scrollOffset'], 42);
      await ReliableUploadService.instance.enqueueReadingProgress(
        db,
        userId: 'user-a',
        bookId: 'book',
        operation: 'delete',
      );
      await db.delete('reading_progress');
      await db.delete('pending_upload_operations');
      await BookService.applyRemoteReadingProgress(
        db,
        'book',
        'user-a',
        incoming,
        isCurrentUser: () => true,
      );
      expect(await db.query('reading_progress'), isEmpty);
    },
  );

  test(
    'remote progress bootstrap is allowed only for the matching authenticated user and book',
    () async {
      final incoming = {
        'user_id': 'user-a',
        'book_id': 'book',
        'chapter_index': '9',
        'scroll_offset': 99,
        'updated_at': '2099-01-01',
      };
      await BookService.applyRemoteReadingProgress(
        db,
        'book',
        'user-b',
        incoming,
        isCurrentUser: () => true,
      );
      expect((await db.query('reading_progress')).single['scrollOffset'], 42);
      await BookService.applyRemoteReadingProgress(
        db,
        'book',
        'user-a',
        incoming,
        isCurrentUser: () => true,
      );
      expect((await db.query('reading_progress')).single['scrollOffset'], 99);
    },
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zhidu-book-removal-');
    db = await DatabaseService.openForTesting('${directory.path}/books.db');
    await db.execute('PRAGMA foreign_keys = ON');
    book = Book(
      id: 'book',
      title: 'Test',
      author: 'Author',
      filePath: '/test.epub',
      addedAt: DateTime.utc(2026),
      lastOpenedAt: DateTime.utc(2026),
    );
    await BookService.insertBook(book);
    await db.insert('highlights', {
      'id': 'highlight',
      'bookId': 'book',
      'chapterIndex': '0',
      'selectedText': 'test',
      'startOffset': 0,
      'endOffset': 4,
      'createdAt': '2026-01-01',
    });
    await db.insert('notes', {
      'id': 'note',
      'bookId': 'book',
      'content': 'test',
      'createdAt': '2026-01-01',
      'updatedAt': '2026-01-01',
    });
    await db.insert('reading_progress', {
      'bookId': 'book',
      'chapterIndex': '0',
      'scrollOffset': 42,
      'updatedAt': '2026-01-01',
    });
    await db.insert('bookmarks', {
      'id': 'bookmark',
      'bookId': 'book',
      'chapterIndex': '0',
      'chapterTitle': 'First',
      'snippet': 'test',
      'createdAt': '2026-01-01',
    });
    await db.insert('user_entries', {
      'id': 'trace',
      'source': 'thought',
      'book_id': 'book',
      'created_at': '2026-01-01',
    });
    await db.insert('ai_messages', {
      'id': 'chat',
      'bookId': 'book',
      'role': 'user',
      'content': 'private',
      'timestamp': '2026-01-01',
    });
    await db.delete('pending_upload_operations');
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'ordinary removal archives with foreign keys enabled and keeps all history',
    () async {
      await BookService.deleteBook('book');
      expect(await BookService.getBooks(), isEmpty);
      expect(await BookService.getBook('book'), isNotNull);
      for (final table in [
        'highlights',
        'notes',
        'reading_progress',
        'bookmarks',
        'user_entries',
        'ai_messages',
      ]) {
        expect(await db.query(table), hasLength(1), reason: table);
      }
      final pending = await db.query('pending_upload_operations');
      expect(pending, hasLength(1));
      expect(pending.single['entity_type'], 'book');
      expect(
        jsonDecode(pending.single['payload_json'] as String)['books'],
        isEmpty,
      );
    },
  );

  test(
    'offline removal survives restart and retry never deletes remote history',
    () async {
      await BookService.removeFromLibrary('book');
      await db.close();
      db = await DatabaseService.openForTesting('${directory.path}/books.db');
      final remote = _Remote();
      final uploader = ReliableUploadService(
        databaseProvider: () async => db,
        client: remote,
        userIdProvider: () => 'user-a',
        isAuthenticated: () => true,
      );
      await uploader.claimAnonymousOperations('user-a');
      await uploader.drain();
      expect(await db.query('pending_upload_operations'), isEmpty);
      expect(await BookService.getBooks(), isEmpty);
      expect(remote.books, isEmpty);
      expect(remote.traces, {'trace'});
      expect(remote.progresses, {'book'});
    },
  );

  test(
    'restoring the same ID preserves dependents instead of REPLACE cascade',
    () async {
      await BookService.removeFromLibrary('book');
      await BookService.insertBook(book);
      expect(await BookService.getBooks(), hasLength(1));
      expect(await db.query('highlights'), hasLength(1));
      expect(await db.query('reading_progress'), hasLength(1));
      final pending = await db.query('pending_upload_operations');
      expect(pending, hasLength(1));
      expect(
        jsonDecode(pending.single['payload_json'] as String)['books'],
        hasLength(1),
      );
    },
  );

  test(
    'only explicit permanent deletion removes known history and queues tombstones',
    () async {
      await BookService.permanentlyDeleteBookData('book');
      await expectLater(BookService.insertBook(book), throwsStateError);
      for (final table in [
        'highlights',
        'notes',
        'reading_progress',
        'bookmarks',
        'user_entries',
      ]) {
        expect(await db.query(table), isEmpty, reason: table);
      }
      expect(await db.query('ai_messages'), hasLength(1));
      final pending = await db.query('pending_upload_operations');
      expect(
        pending
            .map((row) => '${row['entity_type']}:${row['operation']}')
            .toSet(),
        {'book:purge', 'book:replace'},
      );
      final remote = _Remote();
      final uploader = ReliableUploadService(
        databaseProvider: () async => db,
        client: remote,
        userIdProvider: () => 'user-a',
        isAuthenticated: () => true,
      );
      await uploader.claimAnonymousOperations('user-a');
      await uploader.drain();
      expect(remote.traces, isEmpty);
      expect(remote.progresses, isEmpty);
      expect(await db.query('pending_upload_operations'), isEmpty);
    },
  );

  test(
    'version 14 upgrade preserves queue and existing shelf membership',
    () async {
      await db.close();
      db = await databaseFactory.openDatabase('${directory.path}/v14.db');
      await db.execute('CREATE TABLE books (id TEXT PRIMARY KEY)');
      await db.execute("INSERT INTO books VALUES ('old')");
      await db.execute(
        "CREATE TABLE pending_upload_operations (operation_id TEXT PRIMARY KEY, user_id TEXT, entity_type TEXT, entity_id TEXT, generation INTEGER, operation TEXT, payload_json TEXT)",
      );
      await db.execute(
        "INSERT INTO pending_upload_operations VALUES ('pending', 'a', 'trace', 'e', 7, 'create', '{}')",
      );
      await db.setVersion(14);
      await db.close();
      db = await DatabaseService.openForTesting('${directory.path}/v14.db');
      expect((await db.query('books')).single['is_archived'], 0);
      expect(
        (await db.query('pending_upload_operations')).single['operation_id'],
        'pending',
      );
      expect(await db.getVersion(), 17);
      expect(
        (await db.query('pending_upload_operations')).single['client_revision'],
        7,
      );
    },
  );
}
