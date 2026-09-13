import 'dart:convert';
import 'dart:io';

import 'package:ai_reader/services/local_sync_diagnostics.dart';
import 'package:ai_reader/services/upload_revision.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _ObservedFactory implements DatabaseFactory {
  _ObservedFactory({this.onOpen, this.afterQuery});
  final Future<void> Function(Database)? onOpen;
  final Future<void> Function(String)? afterQuery;

  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    expect(options?.readOnly, true);
    expect(options?.singleInstance, false);
    expect(options?.version, isNull);
    expect(options?.onCreate, isNull);
    expect(options?.onUpgrade, isNull);
    final db = await databaseFactoryFfi.openDatabase(path, options: options);
    await onOpen?.call(db);
    return _ObservedDatabase(db, afterQuery);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ObservedDatabase implements Database {
  _ObservedDatabase(this.db, this.afterQuery);
  final Database db;
  final Future<void> Function(String)? afterQuery;
  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) => db.rawQuery(sql, arguments);
  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final rows = await db.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    await afterQuery?.call(table);
    return rows;
  }

  @override
  Future<void> close() => db.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late String path;
  late Database writer;

  setUp(() async {
    // Synthetic fixtures only, in an isolated temporary database.
    directory = await Directory.systemTemp.createTemp(
      'zhidu_diagnostics_test_',
    );
    path = '${directory.path}/fixture.db';
    writer = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await writer.rawQuery('PRAGMA journal_mode = WAL');
    await writer.rawQuery('PRAGMA wal_autocheckpoint = 0');
    await writer.execute('PRAGMA user_version = 17');
    await writer.execute(
      'CREATE TABLE highlights (id TEXT, user_id TEXT, bookId TEXT, selectedText TEXT, createdAt TEXT, updated_at TEXT)',
    );
    await writer.execute(
      'CREATE TABLE notes (id TEXT, user_id TEXT, bookId TEXT, content TEXT)',
    );
    await writer.execute(
      'CREATE TABLE user_entries (id TEXT, user_id TEXT, source TEXT, book_id TEXT, metadata_json TEXT, bmob_id TEXT, original_text TEXT)',
    );
    await writer.execute(
      'CREATE TABLE pending_upload_operations (operation_id TEXT, user_id TEXT, entity_type TEXT, entity_id TEXT, operation TEXT, payload_json TEXT, client_revision INTEGER, generation INTEGER, retry_count INTEGER, last_error_at TEXT, next_retry_at TEXT)',
    );
    await writer.execute(
      'CREATE TABLE upload_entity_revisions (user_id TEXT, entity_type TEXT, entity_id TEXT, last_revision INTEGER, state_hash TEXT, book_id TEXT)',
    );
    await writer.execute(
      'CREATE TABLE locally_deleted_books (user_id TEXT, book_id TEXT)',
    );
    await writer.execute('CREATE TABLE private_credentials (jwt TEXT)');
    await writer.insert('private_credentials', {'jwt': 'DO_NOT_EXPORT_JWT'});
    await writer.insert('highlights', {
      'id': 'h1',
      'user_id': 'private-user',
      'bookId': 'b1',
      'selectedText': 'DO_NOT_EXPORT_TEXT',
      'createdAt': '2026-09-11',
      'updated_at': '2026-09-11',
    });
    await writer.insert('notes', {
      'id': 'n1',
      'user_id': 'private-user',
      'bookId': 'b1',
      'content': 'DO_NOT_EXPORT_NOTE',
    });
    await writer.insert('user_entries', {
      'id': 't1',
      'user_id': 'private-user',
      'source': 'highlight',
      'book_id': 'b1',
      'metadata_json': jsonEncode({
        'source_record_id': 'h1',
        'jwt': 'DO_NOT_EXPORT_METADATA_SECRET',
      }),
      'bmob_id': 'remote-1',
      'original_text': 'DO_NOT_EXPORT_TEXT',
    });
    await writer.insert('pending_upload_operations', {
      'operation_id': 'op1',
      'user_id': 'private-user',
      'entity_type': 'trace',
      'entity_id': 't1',
      'operation': 'upsert',
      'payload_json': jsonEncode({
        'book_id': 'b1',
        'metadata_json': {'source_record_id': 'h1'},
        'password': 'DO_NOT_EXPORT_PASSWORD',
        'user_input': 'DO_NOT_EXPORT_NOTE',
      }),
      'client_revision': 7,
      'generation': 9,
      'retry_count': 2,
      'last_error_at': '2026-09-11',
      'next_retry_at': '2026-09-12',
    });
    await writer.insert('upload_entity_revisions', {
      'user_id': 'private-user',
      'entity_type': 'trace',
      'entity_id': 't1',
      'last_revision': 7,
      'state_hash': 'test-state',
      'book_id': 'b1',
    });
  });
  tearDown(() async {
    await writer.close();
    await directory.delete(recursive: true);
  });

  Future<Map<String, Object?>> inspect() => LocalSyncDiagnostics.inspect(
    path: path,
    currentUserId: 'private-user',
    factory: databaseFactoryFfi,
  );
  List<dynamic> rows(Map report, String table) =>
      (report['records'] as Map)[table] as List;

  test(
    'WAL snapshot includes committed evidence, redacts secrets, leaves DB and WAL byte-identical',
    () async {
      final dbBefore = await File(path).readAsBytes();
      final walBefore = await File('$path-wal').readAsBytes();
      expect(walBefore, isNotEmpty);
      final report = await inspect();
      expect((report['database'] as Map)['user_version'], 17);
      expect((report['database'] as Map)['journal_mode'], 'wal');
      final trace = rows(report, 'user_entries').single as Map;
      expect(trace['client_revision'], 7);
      expect(trace['pending_generation'], 9);
      expect(trace['remote_id'], 'remote-1');
      expect(trace['server_revision'], isNull);
      expect((rows(report, 'highlights').single as Map)['linked_trace_ids'], [
        't1',
      ]);
      expect(
        (rows(report, 'notes').single as Map)['linked_trace_ids'],
        isEmpty,
      );
      expect(
        (rows(report, 'pending_upload_operations').single
            as Map)['retry_count'],
        2,
      );
      final json = jsonEncode(report);
      expect(json, isNot(contains('DO_NOT_EXPORT')));
      expect(json, isNot(contains('private-user')));
      expect(json, isNot(contains('private_credentials')));
      expect(await File(path).readAsBytes(), dbBefore);
      expect(await File('$path-wal').readAsBytes(), walBefore);
      expect(
        (await writer.query('pending_upload_operations')).single['generation'],
        9,
      );
    },
  );

  test(
    'does not include uncommitted changes or consume pending operations',
    () async {
      await writer.execute('BEGIN IMMEDIATE');
      try {
        await writer.insert('highlights', {
          'id': 'not-committed',
          'user_id': 'private-user',
        });
        final report = await inspect();
        expect(rows(report, 'highlights').length, 1);
        expect(rows(report, 'pending_upload_operations').length, 1);
      } finally {
        await writer.execute('ROLLBACK');
      }
    },
  );

  test(
    'older schema remains unchanged and missing tables are explicit',
    () async {
      await writer.execute('PRAGMA user_version = 14');
      await writer.execute('DROP TABLE upload_entity_revisions');
      final report = await inspect();
      expect((report['database'] as Map)['user_version'], 14);
      expect(
        ((report['schema'] as Map)['upload_entity_revisions']
            as Map)['present'],
        false,
      );
      expect(
        (rows(report, 'user_entries').single as Map)['client_revision'],
        isNull,
      );
      expect(
        (await writer.rawQuery('PRAGMA user_version')).single.values.first,
        14,
      );
      expect(
        await writer.rawQuery(
          "SELECT name FROM sqlite_master WHERE name = 'upload_entity_revisions'",
        ),
        isEmpty,
      );
    },
  );

  test(
    'preserves tombstone evidence and separates other/anonymous owners',
    () async {
      await writer.insert('upload_entity_revisions', {
        'user_id': 'other-user',
        'entity_type': 'trace',
        'entity_id': 'deleted-t',
        'last_revision': 8,
        'state_hash': uploadStateHash('delete', {}),
        'book_id': 'b1',
      });
      await writer.insert('notes', {
        'id': 'anonymous-note',
        'user_id': '',
        'bookId': 'b1',
      });
      await writer.insert('locally_deleted_books', {
        'user_id': 'private-user',
        'book_id': 'b2',
      });
      final report = await inspect();
      final tombstone = rows(report, 'upload_entity_revisions').last as Map;
      expect(tombstone['known_delete_tombstone'], true);
      expect(tombstone['last_revision'], 8);
      expect(tombstone['owner_relation'], 'other');
      expect(
        (rows(report, 'notes').last as Map)['owner_relation'],
        'anonymous',
      );
      expect(
        (rows(report, 'locally_deleted_books').single as Map)['book_id'],
        'b2',
      );
    },
  );

  test(
    'malformed payload is reported without leaking it or repairing it',
    () async {
      await writer.update('pending_upload_operations', {
        'payload_json': 'DO_NOT_EXPORT_BROKEN_SECRET',
      });
      final report = await inspect();
      expect(
        (rows(report, 'pending_upload_operations').single
            as Map)['payload_json_parse_status'],
        'invalid',
      );
      expect(jsonEncode(report), isNot(contains('DO_NOT_EXPORT')));
      expect(
        (await writer.query(
          'pending_upload_operations',
        )).single['payload_json'],
        'DO_NOT_EXPORT_BROKEN_SECRET',
      );
    },
  );

  test('missing database is never created', () async {
    final missing = '${directory.path}/missing.db';
    await expectLater(
      LocalSyncDiagnostics.inspect(
        path: missing,
        currentUserId: null,
        factory: databaseFactoryFfi,
      ),
      throwsStateError,
    );
    expect(await File(missing).exists(), false);
  });

  test(
    'actual inspector connection is read-only and rejects a write',
    () async {
      await LocalSyncDiagnostics.inspect(
        path: path,
        currentUserId: null,
        factory: _ObservedFactory(
          onOpen: (db) async {
            expect(identical(db, writer), false);
            await expectLater(
              db.rawUpdate('DELETE FROM highlights'),
              throwsA(isA<DatabaseException>()),
            );
          },
        ),
      );
      expect(await writer.query('highlights'), hasLength(1));
    },
  );

  test(
    'one pinned snapshot across tables despite concurrent committed writes',
    () async {
      final report = await LocalSyncDiagnostics.inspect(
        path: path,
        currentUserId: null,
        factory: _ObservedFactory(
          afterQuery: (table) async {
            if (table == 'highlights') {
              await writer.insert('notes', {
                'id': 'committed-during-export',
                'user_id': 'private-user',
              });
            }
          },
        ),
      );
      expect(rows(report, 'notes'), hasLength(1));
      expect(await writer.query('notes'), hasLength(2));
      expect(rows(await inspect(), 'notes'), hasLength(2));
    },
  );

  test(
    'app metadata comes from native bundle, not pubspec hardcoding',
    () async {
      const channel = MethodChannel('zhidu/local_sync_diagnostics');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getAppInfo');
        return {'version': '2.3.4', 'build_number': '321'};
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final info = await LocalSyncDiagnostics.appInfo();
      expect(info['version'], '2.3.4');
      expect(info['build_number'], '321');
      expect(info['api_base_url'], 'https://api.youxugarden.com');
      expect(info['backend_environment'], isNull);
    },
  );
}
