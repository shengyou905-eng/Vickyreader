import 'dart:io';
import 'package:ai_reader/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory dir;
  Future<Database> legacy(String name) => openDatabase(
    '${dir.path}/$name',
    version: 17,
    onCreate: (db, _) async {
      await db.execute(
        'CREATE TABLE ai_messages (id TEXT PRIMARY KEY, bookId TEXT, role TEXT, content TEXT, timestamp TEXT)',
      );
      await db.execute(
        'CREATE TABLE user_entry_follow_ups (id TEXT PRIMARY KEY, entry_id TEXT, question TEXT, answer TEXT, created_at TEXT, remote_id TEXT, remote_synced INTEGER)',
      );
      await db.execute(
        'CREATE TABLE highlights (id TEXT PRIMARY KEY, content TEXT)',
      );
      await db.insert('ai_messages', {
        'id': 'old-message',
        'bookId': 'same-book',
        'role': 'assistant',
        'content': 'preserve original history',
        'timestamp': '2025-01-01',
      });
      await db.insert('user_entry_follow_ups', {
        'id': 'old-followup',
        'entry_id': 'unresolved',
        'question': 'question',
        'answer': 'preserve answer',
        'created_at': '2025-01-01',
        'remote_synced': 0,
      });
      await db.insert('highlights', {
        'id': 'original-highlight',
        'content': 'original passage',
      });
    },
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('zhidu-migration-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test(
    'actual 17 to 18 upgrade preserves every legacy field and never assigns ownership; replay is idempotent',
    () async {
      var db = await legacy('legacy.db');
      final message = await db.query('ai_messages');
      final followup = await db.query('user_entry_follow_ups');
      final business = await db.query('highlights');
      await db.close();
      db = await DatabaseService.openForTesting('${dir.path}/legacy.db');
      expect(await db.getVersion(), 18);
      final messagesAfter = await db.query('ai_messages');
      final followupsAfter = await db.query('user_entry_follow_ups');
      expect(
        messagesAfter,
        message.map((row) => {...row, 'user_id': null}).toList(),
      );
      expect(
        followupsAfter,
        followup.map((row) => {...row, 'user_id': null}).toList(),
      );
      expect(await db.query('highlights'), business);
      await db.transaction((txn) async {
        await DatabaseService.createAiOwnershipSchema(txn);
        await DatabaseService.createAiOwnershipSchema(txn);
      });
      expect(await db.query('ai_messages'), messagesAfter);
      expect(await db.query('user_entry_follow_ups'), followupsAfter);
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name IN ('idx_ai_messages_owner_book_time', 'idx_follow_ups_owner_entry_time')",
      );
      expect(indexes, hasLength(2));
      await db.close();
    },
  );

  test('failed upgrade rolls schema, version and data back together', () async {
    var db = await legacy('failure.db');
    await db.execute(
      'CREATE TABLE idx_follow_ups_owner_entry_time (id INTEGER)',
    );
    final oldRows = await db.query('ai_messages');
    await db.close();
    await expectLater(
      DatabaseService.openForTesting('${dir.path}/failure.db'),
      throwsA(isA<DatabaseException>()),
    );
    db = await openDatabase('${dir.path}/failure.db');
    expect(await db.getVersion(), 17);
    expect(
      (await db.rawQuery(
        'PRAGMA table_info(ai_messages)',
      )).any((row) => row['name'] == 'user_id'),
      isFalse,
    );
    expect(
      (await db.rawQuery(
        'PRAGMA table_info(user_entry_follow_ups)',
      )).any((row) => row['name'] == 'user_id'),
      isFalse,
    );
    expect(await db.query('ai_messages'), oldRows);
    expect(await db.query('highlights'), hasLength(1));
    await db.close();
  });
}
