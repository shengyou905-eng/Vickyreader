import 'dart:convert';
import 'dart:io';
import 'package:ai_reader/models/highlight.dart';
import 'package:ai_reader/models/user_entry.dart';
import 'package:ai_reader/services/auth_service.dart';
import 'package:ai_reader/services/book_service.dart';
import 'package:ai_reader/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory dir;
  late Database db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'auth_user_id': 'synthetic-owner'});
    await AuthService.init();
    dir = await Directory.systemTemp.createTemp('p0a-atomic-');
    db = await DatabaseService.openForTesting('${dir.path}/test.db');
    await db.insert('books', {
      'id': 'book',
      'title': 'Synthetic',
      'author': '',
      'filePath': '',
      'addedAt': '2026-01-01',
      'lastOpenedAt': '2026-01-01',
    });
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  UserEntry trace(String source, String id) => UserEntry(
    id: id,
    userId: 'synthetic-owner',
    source: source,
    bookId: 'book',
    chapterIndex: '3',
    originalText: 'Synthetic passage',
    userInput: 'Synthetic thought',
    metadataJson: jsonEncode({'source_record_id': 'source-$id'}),
    createdAt: DateTime(2026),
  );
  Highlight highlight(String id) => Highlight(
    id: 'source-$id',
    userId: 'synthetic-owner',
    bookId: 'book',
    chapterIndex: '3',
    selectedText: 'Synthetic passage',
    contextBefore: '',
    contextAfter: '',
    startOffset: 0,
    endOffset: 17,
    createdAt: DateTime(2026),
  );
  Future<String> write(String source, String id) => source == 'highlight'
      ? BookService.insertHighlightTrace(highlight(id), trace(source, id))
      : BookService.insertThoughtTrace('source-$id', trace(source, id));

  for (final source in ['highlight', 'thought']) {
    final table = source == 'highlight' ? 'highlights' : 'notes';
    test(
      '$source commits business + trace + pending with existing upload envelope',
      () async {
        await write(source, 'a');
        expect(await db.query(table), hasLength(1));
        expect(await db.query('user_entries'), hasLength(1));
        final queue = (await db.query('pending_upload_operations')).single;
        expect(queue['entity_type'], 'trace');
        expect(queue['entity_id'], 'a');
        expect(queue['user_id'], 'synthetic-owner');
        expect(queue['client_revision'], 1);
        expect(queue['generation'], 1);
        expect(queue['retry_count'], 0);
        await write(source, 'b');
        expect(await db.query(table), hasLength(2));
        expect(await db.query('user_entries'), hasLength(2));
      },
    );

    for (final failureTable in [
      table,
      'user_entries',
      'pending_upload_operations',
    ]) {
      test(
        '$source failure in $failureTable rolls back all three tables',
        () async {
          await db.execute(
            "CREATE TRIGGER fail_insert BEFORE INSERT ON $failureTable BEGIN SELECT RAISE(ABORT, 'synthetic fault'); END",
          );
          await expectLater(
            write(source, 'failed'),
            throwsA(isA<DatabaseException>()),
          );
          expect(await db.query(table), isEmpty);
          expect(await db.query('user_entries'), isEmpty);
          expect(await db.query('pending_upload_operations'), isEmpty);
        },
      );
    }

    test(
      '$source duplicate local ID cannot replace original data or increment revision',
      () async {
        await write(source, 'same');
        final before = jsonEncode(await db.query('pending_upload_operations'));
        await expectLater(
          write(source, 'same'),
          throwsA(isA<DatabaseException>()),
        );
        expect(await db.query(table), hasLength(1));
        expect(jsonEncode(await db.query('pending_upload_operations')), before);
      },
    );
  }
}
