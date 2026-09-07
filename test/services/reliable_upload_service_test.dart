import 'dart:io';
import 'dart:async';

import 'package:ai_reader/services/reliable_upload_service.dart';
import 'package:ai_reader/services/database_service.dart';
import 'package:ai_reader/services/upload_revision.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Clock {
  DateTime value = DateTime.utc(2026, 8, 28, 8);

  DateTime call() => value;

  void advance(Duration duration) => value = value.add(duration);
}

class _FakeUploadClient implements ReliableUploadClient {
  final Map<String, Map<String, dynamic>> traces = {};
  final Map<String, Map<String, dynamic>> progresses = {};
  List<Map<String, dynamic>> books = [];
  final Set<String> failOnce = {};
  final List<String> calls = [];
  final List<Map<String, dynamic>> versions = [];
  final List<Map<String, dynamic>> progressVersions = [];
  final Map<String, Map<String, dynamic>> progressStates = {};
  Future<void> Function(String)? beforeMutation;
  final Set<String> loseAcknowledgement = {};

  void _maybeFail(String key) {
    calls.add(key);
    if (failOnce.remove(key)) throw StateError('offline');
  }

  @override
  Future<Map<String, dynamic>> upsertTrace(
    String clientEntryId,
    Map<String, dynamic> payload,
  ) async {
    versions.add({
      'id': clientEntryId,
      'operation': 'upsert',
      'client_revision': payload['client_revision'],
      'writer_id': payload['writer_id'],
    });
    _maybeFail('trace:$clientEntryId');
    await beforeMutation?.call('trace:$clientEntryId');
    traces[clientEntryId] = Map<String, dynamic>.from(payload);
    if (loseAcknowledgement.remove(clientEntryId)) throw StateError('timeout');
    return {'id': 'remote-$clientEntryId'};
  }

  @override
  Future<void> deleteTrace(
    String clientEntryId,
    Map<String, dynamic> version,
  ) async {
    versions.add({'id': clientEntryId, 'operation': 'delete', ...version});
    _maybeFail('delete-trace:$clientEntryId');
    await beforeMutation?.call('delete-trace:$clientEntryId');
    traces.remove(clientEntryId);
  }

  @override
  Future<void> upsertReadingProgress(Map<String, dynamic> payload) async {
    final bookId = payload['book_id']!.toString();
    progressVersions.add({'id': bookId, 'operation': 'upsert', ...payload});
    _maybeFail('progress:$bookId');
    await beforeMutation?.call('progress:$bookId');
    if (!_acceptProgress(bookId, payload, 'upsert', payload)) return;
    progresses[bookId] = Map<String, dynamic>.from(payload);
    if (loseAcknowledgement.remove('progress:$bookId')) {
      throw StateError('timeout');
    }
  }

  @override
  Future<void> permanentlyDeleteBookData(String bookId) async {
    _maybeFail('purge:$bookId');
    traces.removeWhere((key, trace) => trace['book_id'] == bookId);
    progresses.remove(bookId);
    books.removeWhere((book) => book['book_id'] == bookId);
  }

  @override
  Future<void> deleteReadingProgress(
    String bookId,
    Map<String, dynamic> version,
  ) async {
    progressVersions.add({'id': bookId, 'operation': 'delete', ...version});
    _maybeFail('delete-progress:$bookId');
    await beforeMutation?.call('delete-progress:$bookId');
    if (!_acceptProgress(bookId, version, 'delete', {})) return;
    progresses.remove(bookId);
  }

  bool _acceptProgress(
    String book,
    Map<String, dynamic> version,
    String operation,
    Map<String, dynamic> payload,
  ) {
    final revision = version['client_revision'] as int;
    final hash = uploadStateHash(operation, payload);
    final current = progressStates[book];
    if (current != null) {
      if (current['writer_id'] != version['writer_id'] ||
          revision < (current['client_revision'] as int)) {
        throw StateError('stale or foreign writer');
      }
      if (revision == current['client_revision']) {
        if (hash != current['hash']) throw StateError('revision reused');
        return false;
      }
    }
    progressStates[book] = {
      'client_revision': revision,
      'writer_id': version['writer_id'],
      'hash': hash,
      'deleted': operation == 'delete',
    };
    return true;
  }

  @override
  Future<void> replaceLibraryBooks(List<Map<String, dynamic>> next) async {
    _maybeFail('books');
    books = next.map(Map<String, dynamic>.from).toList(growable: false);
  }
}

Future<void> _createSchema(Database db) async {
  await db.execute('''
    CREATE TABLE pending_upload_operations (
      operation_id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL DEFAULT '',
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      operation TEXT NOT NULL,
      payload_json TEXT NOT NULL DEFAULT '{}',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      retry_count INTEGER NOT NULL DEFAULT 0,
      last_error_at TEXT,
      next_retry_at TEXT NOT NULL,
      generation INTEGER NOT NULL DEFAULT 1,
      UNIQUE(user_id, entity_type, entity_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE user_entries (
      id TEXT PRIMARY KEY,
      bmob_id TEXT DEFAULT ''
    )
  ''');
}

void main() {
  sqfliteFfiInit();

  late Directory tempDirectory;
  late String databasePath;
  late Database db;
  late _Clock clock;
  late _FakeUploadClient client;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('zhidu-upload-test-');
    databasePath = '${tempDirectory.path}${Platform.pathSeparator}queue.db';
    db = await databaseFactoryFfi.openDatabase(databasePath);
    await _createSchema(db);
    await DatabaseService.createUploadRevisionSchema(db);
    clock = _Clock();
    client = _FakeUploadClient();
  });

  tearDown(() async {
    await db.close();
    await tempDirectory.delete(recursive: true);
  });

  ReliableUploadService service() => ReliableUploadService(
    databaseProvider: () async => db,
    client: client,
    clock: clock.call,
    userIdProvider: () => 'user-a',
    isAuthenticated: () => true,
  );

  test(
    'progress retry survives restart, coalesces latest revision and allows a newer lower value',
    () async {
      Future<void> enqueue(double value) => service().enqueueReadingProgress(
        db,
        userId: 'user-a',
        bookId: 'position',
        operation: 'upsert',
        payload: {'book_id': 'position', 'progress': value},
      );
      await enqueue(0.2);
      client.failOnce.add('progress:position');
      await service().drain();
      expect(
        (await db.query('pending_upload_operations')).single['client_revision'],
        1,
      );
      await db.close();
      db = await databaseFactoryFfi.openDatabase(databasePath);
      clock.advance(const Duration(seconds: 6));
      await service().drain();
      expect(client.progressVersions.map((v) => v['client_revision']), [1, 1]);
      expect(
        client.progressVersions.map((v) => v['writer_id']).toSet(),
        hasLength(1),
      );
      await enqueue(0.5);
      await enqueue(0.8);
      await enqueue(0.8);
      expect(
        (await db.query('pending_upload_operations')).single['client_revision'],
        3,
      );
      await service().drain();
      expect(client.progresses['position']?['progress'], 0.8);
      final old = {...client.progressVersions.first}
        ..remove('id')
        ..remove('operation');
      await expectLater(client.upsertReadingProgress(old), throwsStateError);
      await enqueue(0.2);
      client.loseAcknowledgement.add('progress:position');
      await service().drain();
      expect(
        (await db.query('pending_upload_operations')).single['client_revision'],
        4,
      );
      clock.advance(const Duration(seconds: 6));
      await service().drain();
      expect(client.progresses['position']?['progress'], 0.2);
      expect(await db.query('pending_upload_operations'), isEmpty);
      expect(client.progressStates['position']?['client_revision'], 4);
    },
  );

  test(
    'progress delete retries and recreate persist beyond queue removal',
    () async {
      await service().enqueueReadingProgress(
        db,
        userId: 'user-a',
        bookId: 'position',
        operation: 'upsert',
        payload: {'book_id': 'position', 'progress': 0.8},
      );
      await service().drain();
      final old = {...client.progressVersions.single}
        ..remove('id')
        ..remove('operation');
      await service().enqueueReadingProgress(
        db,
        userId: 'user-a',
        bookId: 'position',
        operation: 'delete',
      );
      client.failOnce.add('delete-progress:position');
      await service().drain();
      await db.close();
      db = await databaseFactoryFfi.openDatabase(databasePath);
      clock.advance(const Duration(seconds: 6));
      await service().drain();
      final deletedVersion = {
        'writer_id': client.progressVersions.last['writer_id'],
        'client_revision': 2,
      };
      await client.deleteReadingProgress('position', deletedVersion);
      await expectLater(client.upsertReadingProgress(old), throwsStateError);
      expect(client.progresses, isEmpty);
      await service().enqueueReadingProgress(
        db,
        userId: 'user-a',
        bookId: 'position',
        operation: 'upsert',
        payload: {'book_id': 'position', 'progress': 0.1},
      );
      await service().drain();
      await expectLater(
        client.deleteReadingProgress('position', deletedVersion),
        throwsStateError,
      );
      expect(client.progresses['position']?['progress'], 0.1);
      expect(client.progressStates['position']?['client_revision'], 3);
    },
  );

  test(
    'in-flight progress cannot acknowledge a later coalesced state',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      await service().enqueueReadingProgress(
        db,
        userId: 'user-a',
        bookId: 'position',
        operation: 'upsert',
        payload: {'book_id': 'position', 'progress': 0.2},
      );
      client.beforeMutation = (key) async {
        if (key == 'progress:position') {
          started.complete();
          await release.future;
        }
      };
      final first = service().drain();
      await started.future;
      await service().enqueueReadingProgress(
        db,
        userId: 'user-a',
        bookId: 'position',
        operation: 'upsert',
        payload: {'book_id': 'position', 'progress': 0.8},
      );
      release.complete();
      await first;
      expect(
        (await db.query('pending_upload_operations')).single['client_revision'],
        2,
      );
      client.beforeMutation = null;
      await service().drain();
      expect(client.progresses['position']?['progress'], 0.8);
      expect(await db.query('pending_upload_operations'), isEmpty);
    },
  );

  test(
    'SQLite16 progress migration retains pending identity, retry schedule and writer',
    () async {
      final writer = (await db.query('upload_writer')).single['writer_id'];
      final now = clock.call().toIso8601String();
      await db.insert('pending_upload_operations', {
        'operation_id': 'v16-progress',
        'user_id': 'user-a',
        'entity_type': 'reading_progress',
        'entity_id': 'position',
        'operation': 'upsert',
        'payload_json': '{"book_id":"position","progress":0.4}',
        'created_at': now,
        'updated_at': now,
        'next_retry_at': now,
        'retry_count': 3,
        'generation': 7,
        'client_revision': 0,
      });
      await db.execute('PRAGMA user_version = 16');
      await db.close();
      databaseFactory = databaseFactoryFfi;
      db = await DatabaseService.openForTesting(databasePath);
      expect(await db.getVersion(), 17);
      final seeded = (await db.query('pending_upload_operations')).single;
      expect(seeded['client_revision'], 7);
      expect(seeded['operation_id'], 'v16-progress');
      expect(seeded['retry_count'], 3);
      await DatabaseService.createProgressRevisionSchema(db);
      expect((await db.query('upload_writer')).single['writer_id'], writer);
      await service().enqueueReadingProgress(
        db,
        userId: 'user-a',
        bookId: 'position',
        operation: 'upsert',
        payload: {'book_id': 'position', 'progress': 0.4},
      );
      expect((await db.query('pending_upload_operations')).single, seeded);
      await service().drain();
      expect(client.progressVersions.single['client_revision'], 7);
    },
  );

  test('failed create survives restart and retry is idempotent', () async {
    await db.insert('user_entries', {'id': 'entry-1', 'bmob_id': ''});
    final first = service();
    await first.enqueueTrace(
      db,
      userId: 'user-a',
      entityId: 'entry-1',
      operation: 'create',
      payload: {'source': 'thought', 'user_input': 'latest'},
    );
    client.failOnce.add('trace:entry-1');
    await first.drain();
    expect(await db.query('pending_upload_operations'), hasLength(1));

    await db.close();
    db = await databaseFactoryFfi.openDatabase(databasePath);
    clock.advance(const Duration(seconds: 6));
    final afterRestart = service();
    await afterRestart.drain();

    expect(await db.query('pending_upload_operations'), isEmpty);
    expect(client.traces, hasLength(1));
    expect(client.traces['entry-1']?['user_input'], 'latest');
    final local = await db.query(
      'user_entries',
      where: 'id = ?',
      whereArgs: ['entry-1'],
    );
    expect(local.single['bmob_id'], 'remote-entry-1');
  });

  test(
    'anonymous permanent purge subsumes older bodyless trace deletes before login',
    () async {
      final uploader = service();
      await uploader.enqueueTrace(
        db,
        userId: '',
        entityId: 'already-local-deleted',
        operation: 'create',
        payload: {'source': 'thought', 'book_id': 'gone'},
      );
      await uploader.enqueueTrace(
        db,
        userId: '',
        entityId: 'already-local-deleted',
        operation: 'delete',
      );
      await uploader.enqueuePermanentBookDeletion(
        db,
        userId: '',
        bookId: 'gone',
        localTraceIds: [],
      );
      final pending = await db.query('pending_upload_operations');
      expect(pending, hasLength(1));
      expect(pending.single['operation'], 'purge');
      await uploader.claimAnonymousOperations('user-a');
      await uploader.drain();
      expect(client.calls, ['purge:gone']);
      expect(await db.query('pending_upload_operations'), isEmpty);
    },
  );

  test(
    'SQLite 15 migration retains a queued operation revision and payload fingerprint',
    () async {
      await db.close();
      final oldPath = '${tempDirectory.path}${Platform.pathSeparator}v15.db';
      db = await databaseFactoryFfi.openDatabase(oldPath);
      await _createSchema(db);
      await db.insert('pending_upload_operations', {
        'operation_id': 'existing-operation',
        'user_id': 'user-a',
        'entity_type': 'trace',
        'entity_id': 'upgrade',
        'operation': 'create',
        'payload_json': '{"source":"thought"}',
        'created_at': '2020-01-01',
        'updated_at': '2020-01-01',
        'next_retry_at': '2020-01-01',
        'generation': 7,
      });
      await db.setVersion(15);
      await db.close();
      databaseFactory = databaseFactoryFfi;
      db = await DatabaseService.openForTesting(oldPath);
      await service().enqueueTrace(
        db,
        userId: 'user-a',
        entityId: 'upgrade',
        operation: 'create',
        payload: {'source': 'thought'},
      );
      final pending = (await db.query('pending_upload_operations')).single;
      expect(pending['operation_id'], 'existing-operation');
      expect(pending['client_revision'], 7);
      expect(pending['generation'], 7);
      await service().drain();
      expect(client.versions.single['client_revision'], 7);
      expect(await db.getVersion(), 17);
    },
  );

  test('create and updates coalesce to the latest payload', () async {
    final uploader = service();
    await uploader.enqueueTrace(
      db,
      userId: 'user-a',
      entityId: 'entry-2',
      operation: 'create',
      payload: {'user_input': 'first'},
    );
    await uploader.enqueueTrace(
      db,
      userId: 'user-a',
      entityId: 'entry-2',
      operation: 'update',
      payload: {'user_input': 'newest'},
    );
    expect(await db.query('pending_upload_operations'), hasLength(1));
    await uploader.drain();
    expect(client.traces['entry-2']?['user_input'], 'newest');
  });

  test('create update delete cannot recreate a deleted trace', () async {
    final uploader = service();
    await uploader.enqueueTrace(
      db,
      userId: 'user-a',
      entityId: 'entry-3',
      operation: 'create',
      payload: {'user_input': 'first'},
    );
    await uploader.enqueueTrace(
      db,
      userId: 'user-a',
      entityId: 'entry-3',
      operation: 'update',
      payload: {'user_input': 'second'},
    );
    await uploader.enqueueTrace(
      db,
      userId: 'user-a',
      entityId: 'entry-3',
      operation: 'delete',
    );
    await uploader.drain();
    expect(client.traces.containsKey('entry-3'), isFalse);
    expect(client.calls, ['delete-trace:entry-3']);
  });

  test(
    'failed delete stays pending and eventually removes the trace',
    () async {
      client.traces['entry-delete'] = {'user_input': 'remove me'};
      final uploader = service();
      await uploader.enqueueTrace(
        db,
        userId: 'user-a',
        entityId: 'entry-delete',
        operation: 'delete',
      );
      client.failOnce.add('delete-trace:entry-delete');
      await uploader.drain();
      expect(client.traces, contains('entry-delete'));
      expect(await db.query('pending_upload_operations'), hasLength(1));

      clock.advance(const Duration(seconds: 6));
      await uploader.drain();
      expect(client.traces, isNot(contains('entry-delete')));
      expect(await db.query('pending_upload_operations'), isEmpty);
    },
  );

  test('reading progress retry is safe and keeps the latest value', () async {
    final uploader = service();
    await uploader.enqueueReadingProgress(
      db,
      userId: 'user-a',
      bookId: 'book-progress',
      operation: 'upsert',
      payload: {'book_id': 'book-progress', 'progress': 0.2},
    );
    client.failOnce.add('progress:book-progress');
    await uploader.drain();

    await uploader.enqueueReadingProgress(
      db,
      userId: 'user-a',
      bookId: 'book-progress',
      operation: 'upsert',
      payload: {'book_id': 'book-progress', 'progress': 0.7},
    );
    await uploader.drain();
    expect(client.progresses['book-progress']?['progress'], 0.7);
    expect(await db.query('pending_upload_operations'), isEmpty);
  });

  test(
    'repeated library snapshot replaces instead of duplicating books',
    () async {
      final uploader = service();
      final books = [
        {'book_id': 'book-1', 'title': 'Book'},
      ];
      await uploader.enqueueLibrarySnapshot(db, userId: 'user-a', books: books);
      client.failOnce.add('books');
      await uploader.drain();

      clock.advance(const Duration(seconds: 6));
      await uploader.drain();
      await uploader.enqueueLibrarySnapshot(db, userId: 'user-a', books: books);
      await uploader.drain();
      expect(client.books, hasLength(1));
      expect(client.books.single['book_id'], 'book-1');
    },
  );

  test('one failure does not block progress and library uploads', () async {
    final uploader = service();
    await uploader.enqueueTrace(
      db,
      userId: 'user-a',
      entityId: 'entry-fails',
      operation: 'create',
      payload: {'source': 'highlight'},
    );
    await uploader.enqueueReadingProgress(
      db,
      userId: 'user-a',
      bookId: 'book-1',
      operation: 'upsert',
      payload: {'book_id': 'book-1', 'progress': 0.4},
    );
    await uploader.enqueueLibrarySnapshot(
      db,
      userId: 'user-a',
      books: [
        {'book_id': 'book-1', 'title': 'Book'},
      ],
    );
    client.failOnce.add('trace:entry-fails');
    await uploader.drain();

    expect(client.progresses['book-1']?['progress'], 0.4);
    expect(client.books.single['book_id'], 'book-1');
    expect(await db.query('pending_upload_operations'), hasLength(1));
  });

  test('operations are isolated to the authenticated user', () async {
    final uploader = service();
    await uploader.enqueueTrace(
      db,
      userId: 'user-b',
      entityId: 'private-b',
      operation: 'create',
      payload: {'source': 'thought'},
    );
    await uploader.drain();
    expect(client.calls, isEmpty);
    expect(await db.query('pending_upload_operations'), hasLength(1));
  });

  test('lost acknowledgement retries without a duplicate', () async {
    final uploader = service();
    await uploader.enqueueTrace(
      db,
      userId: 'user-a',
      entityId: 'lost',
      operation: 'create',
      payload: {'source': 'thought'},
    );
    client.loseAcknowledgement.add('lost');
    await uploader.drain();
    expect(client.traces, hasLength(1));
    expect(await db.query('pending_upload_operations'), hasLength(1));
    clock.advance(const Duration(seconds: 6));
    await uploader.drain();
    expect(client.traces, hasLength(1));
    expect(await db.query('pending_upload_operations'), isEmpty);
  });

  test('in-flight delete cannot acknowledge a newly queued recreate', () async {
    final uploader = service();
    client.traces['race'] = {'source': 'thought', 'user_input': 'old'};
    await uploader.enqueueTrace(
      db,
      userId: 'user-a',
      entityId: 'race',
      operation: 'delete',
    );
    final entered = Completer<void>();
    final resume = Completer<void>();
    client.beforeMutation = (key) async {
      if (key == 'delete-trace:race') {
        entered.complete();
        await resume.future;
      }
    };
    final running = uploader.drain();
    await entered.future;
    await uploader.enqueueTrace(
      db,
      userId: 'user-a',
      entityId: 'race',
      operation: 'create',
      payload: {'source': 'thought', 'user_input': 'new'},
    );
    resume.complete();
    await running;
    expect(await db.query('pending_upload_operations'), hasLength(1));
    await uploader.drain();
    expect(client.traces['race']?['user_input'], 'new');
    expect(await db.query('pending_upload_operations'), isEmpty);
  });

  test(
    'account switch during a batch leaves remaining owner operations queued',
    () async {
      var owner = 'user-a';
      final uploader = ReliableUploadService(
        databaseProvider: () async => db,
        client: client,
        clock: clock.call,
        userIdProvider: () => owner,
        isAuthenticated: () => true,
      );
      for (final id in ['first', 'second']) {
        await uploader.enqueueTrace(
          db,
          userId: 'user-a',
          entityId: id,
          operation: 'create',
          payload: {'source': 'thought'},
        );
        clock.advance(const Duration(seconds: 1));
      }
      client.beforeMutation = (_) async {
        owner = 'user-b';
      };
      await uploader.drain();
      expect(client.calls, ['trace:first']);
      expect(await db.query('pending_upload_operations'), hasLength(1));
    },
  );

  test(
    'revision survives acknowledgement, process restart, delete retries and recreate',
    () async {
      var uploader = service();
      await uploader.enqueueTrace(
        db,
        userId: 'user-a',
        entityId: 'durable',
        operation: 'create',
        payload: {'source': 'thought', 'user_input': 'one'},
      );
      await uploader.drain();
      final writer = client.versions.single['writer_id'];
      expect(client.versions.single['client_revision'], 1);
      expect(await db.query('pending_upload_operations'), isEmpty);
      await db.close();
      db = await databaseFactoryFfi.openDatabase(databasePath);
      uploader = service();
      await uploader.enqueueTrace(
        db,
        userId: 'user-a',
        entityId: 'durable',
        operation: 'delete',
      );
      client.failOnce.add('delete-trace:durable');
      await uploader.drain();
      await db.close();
      db = await databaseFactoryFfi.openDatabase(databasePath);
      uploader = service();
      clock.advance(const Duration(seconds: 6));
      client.failOnce.add('delete-trace:durable');
      await uploader.drain();
      clock.advance(const Duration(seconds: 11));
      await uploader.drain();
      await uploader.enqueueTrace(
        db,
        userId: 'user-a',
        entityId: 'durable',
        operation: 'create',
        payload: {'source': 'thought', 'user_input': 'three'},
      );
      await uploader.drain();
      expect(client.versions.map((row) => row['client_revision']).toList(), [
        1,
        2,
        2,
        2,
        3,
      ]);
      expect(
        client.versions.every((row) => row['writer_id'] == writer),
        isTrue,
      );
      expect(
        (await db.query('upload_entity_revisions')).single['last_revision'],
        3,
      );
      expect(client.traces['durable']?['user_input'], 'three');
    },
  );

  test(
    'coalescing advances revision but identical restart snapshot never invents one',
    () async {
      final uploader = service();
      await uploader.enqueueTrace(
        db,
        userId: 'user-a',
        entityId: 'coalesce',
        operation: 'create',
        payload: {'source': 'thought', 'user_input': 'one'},
      );
      final latest = {'source': 'thought', 'user_input': 'two'};
      await uploader.enqueueTrace(
        db,
        userId: 'user-a',
        entityId: 'coalesce',
        operation: 'update',
        payload: latest,
      );
      expect(
        (await db.query('pending_upload_operations')).single['client_revision'],
        2,
      );
      await uploader.enqueueTrace(
        db,
        userId: 'user-a',
        entityId: 'coalesce',
        operation: 'create',
        payload: latest,
      );
      expect(
        (await db.query('pending_upload_operations')).single['client_revision'],
        2,
      );
      await uploader.drain();
      await db.close();
      db = await databaseFactoryFfi.openDatabase(databasePath);
      await service().enqueueTrace(
        db,
        userId: 'user-a',
        entityId: 'coalesce',
        operation: 'create',
        payload: latest,
      );
      expect(
        (await db.query('pending_upload_operations')).single['client_revision'],
        2,
      );
      await service().drain();
      expect(client.versions.map((row) => row['client_revision']).toList(), [
        2,
        2,
      ]);
    },
  );

  test(
    'permanent deletion is one durable book operation, including cloud-only traces',
    () async {
      var uploader = service();
      client.traces['cloud-only'] = {'source': 'thought', 'book_id': 'gone'};
      client.traces['keep'] = {'source': 'thought', 'book_id': 'other'};
      await uploader.enqueuePermanentBookDeletion(
        db,
        userId: 'user-a',
        bookId: 'gone',
        localTraceIds: [],
      );
      client.failOnce.add('purge:gone');
      await uploader.drain();
      expect(await db.query('pending_upload_operations'), hasLength(1));
      await db.close();
      db = await databaseFactoryFfi.openDatabase(databasePath);
      uploader = service();
      clock.advance(const Duration(seconds: 6));
      await uploader.drain();
      expect(client.traces.keys, ['keep']);
      expect(await db.query('pending_upload_operations'), isEmpty);
      await expectLater(
        uploader.enqueueTrace(
          db,
          userId: 'user-a',
          entityId: 'old-local',
          operation: 'create',
          payload: {'source': 'thought', 'book_id': 'gone'},
        ),
        throwsStateError,
      );
      await expectLater(
        uploader.enqueueReadingProgress(
          db,
          userId: 'user-a',
          bookId: 'gone',
          operation: 'upsert',
          payload: {'book_id': 'gone'},
        ),
        throwsStateError,
      );
      expect(await db.query('pending_upload_operations'), isEmpty);
    },
  );
}
