import 'dart:convert';
import 'dart:io';

import 'package:ai_reader/services/book_service.dart';
import 'package:ai_reader/services/database_service.dart';
import 'package:ai_reader/services/upload_revision.dart';
import 'package:ai_reader/services/xiaou_trace_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _OfflineClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      throw const SocketException('Synthetic offline test');
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory dir;
  late Database db;
  var serial = 0;
  late String owner;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('xiaou-read-test-');
    db = await DatabaseService.openForTesting('${dir.path}/test.db');
    owner = 'synthetic-user-${serial++}';
    SharedPreferences.setMockInitialValues({'auth_user_id': owner});
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<void> local(String id, {String? user, String source = 'highlight'}) =>
      db
          .insert('user_entries', {
            'id': id,
            'user_id': user ?? owner,
            'source': source,
            'book_id': 'synthetic-book',
            'book_title': 'Synthetic book',
            'original_text': 'Synthetic excerpt',
            'user_input': 'Newest local note',
            'auto_tags': 'reading',
            'metadata_json': jsonEncode({'source_record_id': 'source-$id'}),
            'created_at': '2026-09-01T00:00:00Z',
          })
          .then((_) {});
  Future<void> pending(String id, {String operation = 'create'}) => db
      .insert('pending_upload_operations', {
        'operation_id': 'op-$id',
        'user_id': owner,
        'entity_type': 'trace',
        'entity_id': id,
        'operation': operation,
        'client_revision': 3,
        'generation': 5,
        'retry_count': 7,
        'created_at': '2026-09-01',
        'updated_at': '2026-09-01',
        'next_retry_at': '2026-10-01',
      }, conflictAlgorithm: ConflictAlgorithm.replace)
      .then((_) {});
  Map<String, dynamic> remote(String id, {String? user}) => {
    'id': 'remote-$id',
    'client_entry_id': id,
    'user_id': user ?? owner,
    'book_id': 'synthetic-book',
    'source': 'highlight',
    'original_text': 'Old remote excerpt',
    'user_input': 'Old note',
    'created_at': '2026-09-01T00:00:00Z',
    'follow_up_count': 2,
  };
  Future<List<Map<String, dynamic>>> read([
    List<Map<String, dynamic>> rows = const [],
  ]) => XiaouTraceSnapshot.read(db, userId: owner, remoteRows: rows);

  test(
    'offline subtypes appear without a remote ID and reads do not write',
    () async {
      for (final source in [
        'highlight',
        'thought',
        'ai_explanation',
        'ai_question',
      ]) {
        await local(source, source: source);
        await pending(source);
      }
      final before = jsonEncode(await db.query('pending_upload_operations'));
      final changes = await db.rawQuery('SELECT total_changes() AS n');
      final rows = await read();
      expect(rows, hasLength(4));
      expect(
        rows.every((r) => r['id'] == '' && r['_pending_sync'] == true),
        true,
      );
      expect(jsonEncode(await db.query('pending_upload_operations')), before);
      expect(await db.rawQuery('SELECT total_changes() AS n'), changes);
    },
  );
  test(
    'remote identity and metadata identity deduplicate with stable local ID',
    () async {
      await local('a');
      await pending('a');
      final before = (await read()).single;
      final incoming = remote('a')..remove('client_entry_id');
      incoming['metadata_json'] = {'local_id': 'a'};
      final row = (await read([incoming])).single;
      expect(row['_view_id'], before['_view_id']);
      expect(row['id'], 'remote-a');
      expect(row['user_input'], 'Newest local note');
      expect(row['follow_up_count'], 2);
      expect(row['_pending_sync'], true);
    },
  );
  test(
    'ACK clears badge without stale disk cache rolling back local content',
    () async {
      await local('a');
      await pending('a');
      await read([remote('a')]);
      await db.delete('pending_upload_operations');
      final row = (await read([remote('a')])).single;
      expect(row['_pending_sync'], false);
      expect(row['user_input'], 'Newest local note');
    },
  );
  test('pending delete suppresses cached remote entry', () async {
    await pending('a', operation: 'delete');
    expect(await read([remote('a')]), isEmpty);
  });
  test(
    'retained tombstone suppresses old remote row after queue ACK',
    () async {
      await db.insert('upload_entity_revisions', {
        'user_id': owner,
        'entity_type': 'trace',
        'entity_id': 'a',
        'last_revision': 4,
        'state_hash': uploadStateHash('delete', {}),
      });
      expect(await read([remote('a')]), isEmpty);
      await db.update('upload_entity_revisions', {
        'last_revision': 5,
        'state_hash': uploadStateHash('create', {'new': true}),
      });
      await local('a');
      await pending('a');
      expect(await read([remote('a')]), hasLength(1));
    },
  );
  test(
    'archive keeps history; permanent book marker hides all book history',
    () async {
      // There is deliberately no books row, as after removeFromLibrary.
      await local('a');
      expect(await read([remote('a'), remote('other-device')]), hasLength(2));
      await db.insert('locally_deleted_books', {
        'user_id': owner,
        'book_id': 'synthetic-book',
      });
      expect(await read([remote('a'), remote('other-device')]), isEmpty);
    },
  );
  test('other accounts and unclaimed anonymous rows never leak', () async {
    await local('a');
    await local('b', user: 'other-account');
    await local('anonymous', user: '');
    expect(await read([remote('b', user: 'other-account')]), hasLength(1));
  });
  test('malformed optional metadata does not hide the trace', () async {
    await local('a');
    await db.update('user_entries', {'metadata_json': '{broken'});
    expect((await read()).single['_view_id'], 'a');
  });
  test(
    'BookService restores fresh local rows even with an existing memory cache',
    () async {
      await local('a');
      await pending('a');
      var overview = await BookService.restoreCachedMingtaiOverview();
      expect(overview!.items.single['id'], 'entry:a');
      expect(overview.items.single['remote_entry_id'], '');
      expect(overview.items.single['pending_sync'], true);
      await local('b', source: 'thought');
      overview = await BookService.restoreCachedMingtaiOverview();
      expect(overview!.items, hasLength(2));
      expect((await BookService.getMingtaiOverview()).items, hasLength(2));
    },
  );
  test(
    'authenticated offline fetch falls back to local + disk without consuming queue',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_user_id': owner,
        'auth_token': 'synthetic-invalid-test-token',
        'xiaou_overview_cache_v4_$owner': jsonEncode([remote('a')]),
      });
      await local('a');
      await pending('a');
      final before = await db.query('pending_upload_operations');
      final overview = await HttpOverrides.runZoned(
        () => BookService.getMingtaiOverview(forceRefresh: true),
        createHttpClient: (_) => _OfflineClient(),
      );
      expect(overview.items.single['user_note'], 'Newest local note');
      expect(overview.items.single['pending_sync'], true);
      expect(await db.query('pending_upload_operations'), before);
    },
  );
}
