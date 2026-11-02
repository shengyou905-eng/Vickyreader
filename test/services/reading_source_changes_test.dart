import 'dart:async';
import 'dart:io';

import 'package:ai_reader/models/user_entry.dart';
import 'package:ai_reader/services/auth_session_scope.dart';
import 'package:ai_reader/services/bmob_api.dart';
import 'package:ai_reader/services/book_service.dart';
import 'package:ai_reader/services/database_service.dart';
import 'package:ai_reader/services/reading_source_changes.dart';
import 'package:ai_reader/services/reliable_upload_service.dart';
import 'package:ai_reader/services/sync_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
// sqflite's factory setter requires its internal marker interface even for a
// test double; no methods from the real implementation are executed here.
// ignore: implementation_imports, depend_on_referenced_packages
import 'package:sqflite_common/src/factory.dart' show SqfliteDatabaseFactory;

typedef _Rows = List<Map<String, Object?>>;

// Scripted executors only: no SQLite engine, files, sockets, or model calls.
class _Executor implements DatabaseExecutor {
  _Executor(this.db, this.writes);
  final _Database db;
  final List<String> writes;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final method = invocation.memberName;
    final args = invocation.positionalArguments;
    if (method == #query || method == #rawQuery) {
      return Future<_Rows>.value(db.read(args.first as String, invocation));
    }
    if ([#insert, #update, #delete, #rawInsert, #execute].contains(method)) {
      final target = args.first as String;
      if (target == db.failWrite) {
        if (method == #execute) return Future<void>.error(StateError('write'));
        return Future<int>.error(StateError('write'));
      }
      writes.add('$method:$target');
      if (method == #execute) return Future<void>.value();
      return Future<int>.value(1);
    }
    return super.noSuchMethod(invocation);
  }
}

class _Transaction extends _Executor implements Transaction {
  _Transaction(super.db, super.writes);
}

class _Database implements Database {
  final committedWrites = <String>[];
  final events = <String>[];
  _Rows Function(String, Invocation) read = (_, _) => [];
  Completer<void>? commitGate;
  String? failWrite;
  bool failCommit = false;
  bool insideTransaction = false;

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) async {
    final staged = <String>[];
    insideTransaction = true;
    try {
      final result = await action(_Transaction(this, staged));
      events.add('body-finished');
      await commitGate?.future;
      if (failCommit) throw StateError('commit');
      committedWrites.addAll(staged);
      events.add('committed');
      return result;
    } finally {
      insideTransaction = false;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      _Executor(this, committedWrites).noSuchMethod(invocation);
}

class _Factory implements SqfliteDatabaseFactory {
  _Factory(this.db);
  final _Database db;
  bool failOpen = false;

  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    if (failOpen) throw StateError('open/migration commit');
    return db;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UploadClient implements ReliableUploadClient {
  bool fail = false;
  @override
  Future<Map<String, dynamic>?> upsertTrace(
    String clientEntryId,
    Map<String, dynamic> payload,
  ) async {
    if (fail) throw StateError('synthetic offline');
    return {'id': 'remote'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Database db;
  late _Factory factory;
  VoidCallback listener = () {};
  var notifications = 0;

  final entry = UserEntry(
    id: 'entry',
    userId: 'owner',
    source: 'highlight',
    bookId: 'book',
    metadataJson: '{"source_record_id":"highlight"}',
    createdAt: DateTime.utc(2026),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({'auth_user_id': 'owner'});
    await BmobApi.instance.init(); // No token: singleton drain cannot use HTTP.
    db = _Database();
    db.read = (table, _) => table == 'user_entries' ? [entry.toMap()] : [];
    factory = _Factory(db);
    databaseFactory = null;
    databaseFactory = factory;
    await DatabaseService.openForTesting('not-a-real-database');
    notifications = 0;
    listener = () {
      expect(db.insideTransaction, isFalse);
      notifications++;
      db.events.add('notify');
    };
    ReadingSourceChanges.changes.addListener(listener);
  });

  tearDown(() {
    ReadingSourceChanges.changes.removeListener(listener);
    ReliableUploadService.instance.stop();
  });

  test(
    'commit notification is synchronous before business future completes',
    () async {
      db.commitGate = Completer<void>();
      final bodyFinished = Completer<void>();
      var returned = false;
      var visible = true;
      void withdraw() {
        expect(returned, isFalse);
        expect(db.committedWrites, ['Symbol("insert"):user_entries']);
        visible = false;
      }

      ReadingSourceChanges.changes.addListener(withdraw);
      addTearDown(() => ReadingSourceChanges.changes.removeListener(withdraw));
      final result = db
          .readingSourceTransaction((txn) async {
            await txn.insert('user_entries', entry.toMap());
            bodyFinished.complete();
            return 42;
          })
          .then((value) {
            returned = true;
            expect(visible, isFalse);
            return value;
          });
      await bodyFinished.future;
      expect(notifications, 0);
      expect(visible, isTrue);
      db.commitGate!.complete();
      expect(await result, 42);
      expect(db.events, ['body-finished', 'committed', 'notify']);
      expect(notifications, 1);
    },
  );

  for (final commitFailure in [false, true]) {
    test(
      'failed ${commitFailure ? 'commit' : 'body'} never notifies',
      () async {
        db.failCommit = commitFailure;
        await expectLater(
          db.readingSourceTransaction((txn) async {
            await txn.insert('user_entries', entry.toMap());
            if (!commitFailure) throw StateError('body');
          }),
          throwsStateError,
        );
        expect(notifications, 0);
        expect(db.committedWrites, isEmpty);
      },
    );
  }

  test('removed listener is not called', () async {
    ReadingSourceChanges.changes.removeListener(listener);
    await db.readingSourceTransaction((_) async {});
    expect(notifications, 0);
  });

  final writes = <String, Future<Object?> Function()>{
    'entry create': () => BookService.insertUserEntry(entry),
    'highlight edit': () =>
        BookService.updateHighlightNote('highlight', 'edit'),
    'highlight delete': () => BookService.deleteHighlight('highlight'),
    'entry delete': () => BookService.deleteUserEntry('entry'),
    'importance edit': () =>
        BookService.setMingtaiItemImportance('entry', isImportant: true),
    'follow-up create': () => BookService.insertUserEntryFollowUp(
      entryId: 'entry',
      question: 'q',
      answer: 'a',
    ),
    'permanent book delete': () =>
        BookService.permanentlyDeleteBookData('book'),
    'anonymous queue claim': () =>
        ReliableUploadService.instance.claimAnonymousOperations('owner'),
  };
  for (final write in writes.entries) {
    test('${write.key} publishes after commit before returning', () async {
      var returned = false;
      void withdraw() => expect(returned, isFalse);
      ReadingSourceChanges.changes.addListener(withdraw);
      addTearDown(() => ReadingSourceChanges.changes.removeListener(withdraw));
      await write.value();
      returned = true;
      expect(notifications, 1);
      expect(db.committedWrites, isNotEmpty);
    });
    test('${write.key} failed commit publishes nothing', () async {
      db.failCommit = true;
      await expectLater(write.value(), throwsStateError);
      expect(notifications, 0);
      expect(db.committedWrites, isEmpty);
    });
  }

  test(
    'listener account switch after commit cannot hide a committed mutation',
    () async {
      void switchAccount() => AuthSessionScope.publish('other', null);
      ReadingSourceChanges.changes.addListener(switchAccount);
      addTearDown(
        () => ReadingSourceChanges.changes.removeListener(switchAccount),
      );
      await expectLater(
        BookService.insertUserEntry(entry),
        throwsA(isA<StaleAuthSession>()),
      );
      expect(notifications, 1);
      expect(db.committedWrites, contains('Symbol("insert"):user_entries'));
    },
  );

  test(
    'enqueue with caller transaction does not publish before outer commit',
    () async {
      db.failCommit = true;
      db.read = (_, _) => [];
      await expectLater(
        db.readingSourceTransaction((txn) async {
          await ReliableUploadService.instance.enqueueTrace(
            txn,
            userId: 'owner',
            entityId: 'entry',
            operation: 'create',
            payload: {'book_id': 'book'},
          );
          expect(notifications, 0);
        }),
        throwsStateError,
      );
      expect(db.committedWrites, isEmpty);
      expect(notifications, 0);
    },
  );

  for (final table in [
    'user_entries',
    'user_entry_follow_ups',
    'pending_upload_operations',
    'upload_entity_revisions',
    'locally_deleted_books',
  ]) {
    test('$table statement failure rolls back without notification', () async {
      db.failWrite = table;
      final write = table == 'user_entry_follow_ups'
          ? writes['follow-up create']!
          : table == 'locally_deleted_books'
          ? writes['permanent book delete']!
          : writes['entry create']!;
      await expectLater(write(), throwsStateError);
      expect(notifications, 0);
      expect(db.committedWrites, isEmpty);
    });
  }

  for (final mode in ['ack', 'retry', 'partial', 'all-failed']) {
    test('drain $mode reports each committed standalone write', () async {
      db.read = (table, call) {
        if (table == 'upload_writer') {
          return [
            {'writer_id': 'writer'},
          ];
        }
        if (table == 'pending_upload_operations') {
          if (call.namedArguments[#columns] != null) {
            return [
              {'generation': 1},
            ];
          }
          return [
            {
              'operation_id': 'op',
              'user_id': 'owner',
              'entity_type': 'trace',
              'entity_id': 'entry',
              'operation': 'create',
              'payload_json': '{}',
              'created_at': '2026-01-01',
              'generation': 1,
              'client_revision': 1,
            },
          ];
        }
        return [];
      };
      final client = _UploadClient()
        ..fail = mode == 'retry' || mode == 'all-failed';
      if (mode == 'partial' || mode == 'all-failed') {
        db.failWrite = 'pending_upload_operations';
      }
      final service = ReliableUploadService(
        databaseProvider: () async => db,
        client: client,
        userIdProvider: () => 'owner',
        isAuthenticated: () => true,
      );
      if (mode == 'partial' || mode == 'all-failed') {
        await expectLater(service.drain(), throwsStateError);
      } else {
        await service.drain();
      }
      expect(
        notifications,
        mode == 'ack'
            ? 2
            : mode == 'all-failed'
            ? 0
            : 1,
      );
    });
  }

  test('database open notifies only after successful open', () async {
    await DatabaseService.openForTesting('fake-open');
    expect(notifications, 1);
    factory.failOpen = true;
    await expectLater(
      DatabaseService.openForTesting('fake-failed-open'),
      throwsStateError,
    );
    expect(notifications, 1);
  });

  test(
    'anonymous sync entry commit notifies even if a later write fails',
    () async {
      db.failWrite = 'free_notes';
      await expectLater(
        SyncService.instance.mergeAnonymousData('owner'),
        throwsStateError,
      );
      expect(notifications, 1);
      expect(db.committedWrites, contains('Symbol("update"):user_entries'));
    },
  );

  test('source audit keeps all targeted BookService transactions connected', () {
    var root = Directory.current;
    while (!File('${root.path}/lib/services/book_service.dart').existsSync()) {
      final parent = root.parent;
      if (parent.path == root.path) fail('repository root unavailable');
      root = parent;
    }
    final source = File(
      '${root.path}/lib/services/book_service.dart',
    ).readAsStringSync();
    // The only unobserved transactions write excluded ai_messages or unversioned
    // reading_progress. This is a wiring alarm, not a SQLite behavioral test.
    expect('await db.transaction('.allMatches(source), hasLength(2));
    expect(
      'await db.readingSourceTransaction('.allMatches(source),
      hasLength(18),
    );
    final sync = File(
      '${root.path}/lib/services/sync_service.dart',
    ).readAsStringSync();
    expect(
      "if (table == 'user_entries') ReadingSourceChanges.committed();"
          .allMatches(sync),
      hasLength(4),
    );
  });
}
