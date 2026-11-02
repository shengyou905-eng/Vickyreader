import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_reader/services/auth_session_scope.dart';
import 'package:ai_reader/services/book_recap_client_contract.dart';
import 'package:ai_reader/services/book_recap_material_catalog.dart';
import 'package:ai_reader/services/database_service.dart';
import 'package:ai_reader/services/upload_revision.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const owner = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
const remote = '33333333-3333-4333-8333-333333333333';
const remote2 = '44444444-4444-4444-8444-444444444444';
const followId = '55555555-5555-4555-8555-555555555555';

Matcher code(String expected) => throwsA(
  isA<RecapClientException>().having((e) => e.code, 'code', expected),
);

/// Only tests use this facade to interleave a mutation/session transition at
/// an exact async boundary. Every query still runs against isolated SQLite.
class _QueryHook implements Database {
  final Database db;
  final Future<void> Function(String table) afterQuery;
  _QueryHook(this.db, this.afterQuery);

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
    final result = await db.query(
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
    await afterQuery(table);
    return result;
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction) action, {
    bool? exclusive,
  }) => db.transaction(action, exclusive: exclusive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database db;
  late Directory dir;
  late AuthSessionScope session;
  late BookRecapMaterialCatalog catalog;

  Future<void> entry({
    String id = 'local-a',
    String? user = owner,
    String book = 'book-a',
    String title = 'Same title',
    String? remoteId = remote,
    String source = 'highlight',
    String original = 'Synthetic passage',
    String userText = 'Synthetic thought',
    Object metadata = const {},
  }) async {
    await db.insert('user_entries', {
      'id': id,
      'user_id': user,
      'book_id': book,
      'book_title': title,
      'bmob_id': remoteId,
      'source': source,
      'original_text': original,
      'user_input': userText,
      'metadata_json': metadata is String ? metadata : jsonEncode(metadata),
      'created_at': '2026-01-01T00:00:00Z',
    });
  }

  Future<void> follow({
    String id = 'local-follow',
    String? user = owner,
    String parent = 'local-a',
    String? remoteId = followId,
    int synced = 1,
    String question = 'Synthetic question',
    String answer = 'Synthetic answer',
  }) async {
    await db.insert('user_entry_follow_ups', {
      'id': id,
      'user_id': user,
      'entry_id': parent,
      'remote_id': remoteId,
      'remote_synced': synced,
      'question': question,
      'answer': answer,
      'created_at': '2026-01-01T00:00:00Z',
    });
  }

  Future<void> pending({
    String id = 'local-a',
    String operation = 'upsert',
  }) async {
    await db.insert('pending_upload_operations', {
      'operation_id': 'op-$id',
      'user_id': owner,
      'entity_type': 'trace',
      'entity_id': id,
      'operation': operation,
      'payload_json': '{}',
      'created_at': '2026-01-01',
      'updated_at': '2026-01-01',
      'next_retry_at': '2026-01-01',
    });
  }

  List<Map<String, dynamic>> sources({
    String id = remote,
    List<String> follows = const [],
  }) => [
    {'entry_id': id, 'follow_up_ids': follows},
  ];

  setUp(() async {
    AuthSessionScope.beginTransition();
    AuthSessionScope.publish(owner, 'synthetic-token');
    session = AuthSessionScope.capture();
    dir = await Directory.systemTemp.createTemp('recap-catalog-synthetic-');
    db = await DatabaseService.openForTesting('${dir.path}/catalog.db');
    catalog = BookRecapMaterialCatalog(() async => db);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('empty catalog does not manufacture books or materials', () async {
    expect(await catalog.books(session), isEmpty);
    expect(await catalog.materials(session, 'book-a'), isEmpty);
  });

  test(
    'books use stable IDs, owner and eligible traces, never title identity',
    () async {
      await entry();
      await entry(id: 'local-b', book: 'book-b', remoteId: remote2);
      await entry(id: 'foreign', user: other, book: 'foreign');
      await entry(id: 'unknown', user: '', book: 'unknown');
      await entry(id: 'null-owner', user: null, book: 'null-owner');
      await entry(id: 'no-book', book: '');
      await entry(id: 'bad-book', book: ' padded ');
      await entry(
        id: 'private',
        book: 'private',
        metadata: {'free_note_id': 'secret'},
      );
      await entry(id: 'deleted', book: 'deleted');
      await db.insert('locally_deleted_books', {
        'user_id': owner,
        'book_id': 'deleted',
      });
      final books = await catalog.books(session);
      expect(books.map((b) => b.id), ['book-a', 'book-b']);
      expect(books.map((b) => b.title), ['Same title', 'Same title']);
      expect(() => books.clear(), throwsUnsupportedError);
      expect(
        (await catalog.materials(session, 'book-a')).map((m) => m.localId),
        ['local-a'],
      );
    },
  );

  test(
    'complete long original and user text survive; duplicates keep separate IDs',
    () async {
      final long = 'Long original text. ' * 1500;
      await entry(original: long);
      await entry(
        id: 'local-b',
        remoteId: remote2,
        original: long,
        source: 'thought',
      );
      final items = await catalog.materials(session, 'book-a');
      expect(items.map((m) => m.localId), ['local-a', 'local-b']);
      expect(items.map((m) => m.remoteId), [remote, remote2]);
      expect(items.map((m) => m.kind), ['highlight', 'thought']);
      expect(items.every((m) => m.preview == long), isTrue);
      expect(items.every((m) => m.userText == 'Synthetic thought'), isTrue);
      expect(items.every((m) => m.unavailableReason == null), isTrue);
      expect(() => items.clear(), throwsUnsupportedError);
    },
  );

  test(
    'private nested provenance, unsupported source and malformed metadata excluded',
    () async {
      await entry();
      final metadata = [
        {'free_note_id': 'x'},
        {'freeNoteId': 'x'},
        {'free_note': false},
        {'free_notes': []},
        {'authorized_free_note': true},
        {'origin': 'free_note'},
        {
          'nested': [
            {'free_note_id': 'x'},
          ],
        },
        '{broken',
        '[{}]',
      ];
      for (var i = 0; i < metadata.length; i++) {
        await entry(id: 'private-$i', metadata: metadata[i]);
      }
      await entry(id: 'unsupported', source: 'free_note');
      expect(
        (await catalog.materials(session, 'book-a')).map((m) => m.localId),
        ['local-a'],
      );
      await expectLater(
        catalog.restoreSelection(session, 'book-a', sources()),
        code('LOCAL_RESTORE_UNAVAILABLE'),
      );
    },
  );

  test(
    'missing remote identity and pending upsert are labelled, never selectable',
    () async {
      await entry(remoteId: null);
      await entry(id: 'local-b', remoteId: remote2);
      await pending(id: 'local-b');
      final items = await catalog.materials(session, 'book-a');
      expect(items.first.remoteId, isNull);
      expect(items.every((m) => m.unavailableReason != null), isTrue);
      expect(
        items.last.unavailableReason,
        const RecapClientException('LOCAL_PENDING').message,
      );
    },
  );

  test(
    'pending deletion and committed tombstone use existing guard labels',
    () async {
      await entry();
      await entry(id: 'local-b', remoteId: remote2);
      await pending(operation: 'delete');
      await db.insert('upload_entity_revisions', {
        'user_id': owner,
        'entity_type': 'trace',
        'entity_id': remote2,
        'last_revision': 1,
        'state_hash': uploadStateHash('delete', const {}),
      });
      final items = await catalog.materials(session, 'book-a');
      expect(
        items.every(
          (m) =>
              m.unavailableReason ==
              const RecapClientException('LOCAL_DELETED').message,
        ),
        isTrue,
      );
    },
  );

  test(
    'deleted book cannot be selected even when requested directly',
    () async {
      await entry();
      await db.insert('locally_deleted_books', {
        'user_id': owner,
        'book_id': 'book-a',
      });
      expect(await catalog.books(session), isEmpty);
      expect(
        (await catalog.materials(session, 'book-a')).single.unavailableReason,
        isNotNull,
      );
      await expectLater(
        catalog.restoreSelection(session, 'book-a', sources()),
        code('LOCAL_DELETED'),
      );
    },
  );

  test(
    'follow-ups read local/remote parent aliases, dedup remote IDs, filter other owners',
    () async {
      await entry();
      await follow();
      await follow(id: 'remote-alias', parent: remote);
      await follow(
        id: 'other',
        user: other,
        question: 'PRIVATE OTHER QUESTION',
      );
      final item = (await catalog.materials(session, 'book-a')).single;
      expect(item.unavailableReason, isNull);
      expect(item.followUps, hasLength(1));
      expect(item.followUps.single.remoteId, followId);
      expect(item.followUps.single.question, 'Synthetic question');
      expect(() => item.followUps.clear(), throwsUnsupportedError);
    },
  );

  test(
    'unknown-owner follow-up is hidden and guard blocks parent identity',
    () async {
      await entry();
      await follow(user: '', question: 'PRIVATE UNKNOWN QUESTION');
      await follow(
        id: 'null-follow',
        user: null,
        question: 'PRIVATE NULL QUESTION',
      );
      final item = (await catalog.materials(session, 'book-a')).single;
      expect(item.followUps, isEmpty);
      expect(
        item.unavailableReason,
        const RecapClientException('LOCAL_IDENTITY_MISSING').message,
      );
    },
  );

  test(
    'unsynced follow-up without remote ID is visible but parent is unavailable',
    () async {
      await entry();
      await follow(remoteId: '', synced: 0);
      final item = (await catalog.materials(session, 'book-a')).single;
      expect(item.followUps.single.remoteId, isNull);
      expect(
        item.unavailableReason,
        const RecapClientException('LOCAL_PENDING').message,
      );
    },
  );

  test('conflicting follow-up aliases disable parent through guard', () async {
    await entry();
    await follow();
    await follow(id: 'conflicting', parent: remote, answer: 'Changed answer');
    expect(
      (await catalog.materials(session, 'book-a')).single.unavailableReason,
      const RecapClientException('LOCAL_CHANGED').message,
    );
  });

  test(
    'restore exactly maps remote IDs and keeps explicit none/selected scope',
    () async {
      await entry();
      await entry(id: 'local-b', remoteId: remote2);
      await follow();
      final selected = await catalog.restoreSelection(session, 'book-a', [
        ...sources(id: remote2),
        ...sources(follows: [followId]),
      ]);
      expect(selected.map((s) => s.localEntryId), ['local-b', 'local-a']);
      expect(selected.first.followScope, RecapFollowScope.none);
      expect(selected.last.followScope, RecapFollowScope.selected);
      expect(selected.last.followUpIds, [followId]);
      expect(() => selected.clear(), throwsUnsupportedError);
    },
  );

  test(
    'missing local records fail explicitly without fallback, download or body writes',
    () async {
      await entry(id: remote, remoteId: '');
      await entry(id: 'other-book', book: 'book-b');
      await entry(id: 'other-owner', user: other);
      try {
        await catalog.restoreSelection(session, 'book-a', sources());
        fail('Expected restricted restore');
      } on RecapMaterialCatalogException catch (error) {
        expect(error.code, 'LOCAL_RESTORE_UNAVAILABLE');
        expect(error.message, contains('\u4e0d\u4f1a\u81ea\u52a8\u4e0b\u8f7d'));
      }
      expect(await db.query('user_entries'), hasLength(3));
    },
  );

  test(
    'restore rejects ambiguous aliases even if one is in another book',
    () async {
      await entry();
      await entry(id: 'alias', book: 'book-b');
      await expectLater(
        catalog.restoreSelection(session, 'book-a', sources()),
        code('LOCAL_RESTORE_UNAVAILABLE'),
      );
    },
  );

  test(
    'restore does not silently drop absent or pending follow-up identities',
    () async {
      await entry();
      await expectLater(
        catalog.restoreSelection(
          session,
          'book-a',
          sources(follows: [followId]),
        ),
        code('LOCAL_RESTORE_UNAVAILABLE'),
      );
      await follow(synced: 0);
      await expectLater(
        catalog.restoreSelection(
          session,
          'book-a',
          sources(follows: [followId]),
        ),
        code('LOCAL_PENDING'),
      );
    },
  );

  test(
    'restore rejects malformed, duplicate, omitted and oversized source scopes',
    () async {
      await entry();
      for (final input in <List<Map<String, dynamic>>>[
        [],
        [
          {'entry_id': remote},
        ],
        [
          {'entry_id': 'local-a', 'follow_up_ids': []},
        ],
        [...sources(), ...sources()],
        sources(follows: [followId, followId]),
        [
          {'entry_id': remote, 'follow_up_ids': [], 'extra': true},
        ],
      ]) {
        await expectLater(
          catalog.restoreSelection(session, 'book-a', input),
          throwsA(isA<RecapClientException>()),
        );
      }
      await expectLater(
        catalog.restoreSelection(
          session,
          'book-a',
          List.generate(81, (_) => sources().single),
        ),
        code('RECAP_SCOPE_TOO_LARGE'),
      );
      await expectLater(
        catalog.restoreSelection(
          session,
          'book-a',
          sources(follows: List.filled(321, followId)),
        ),
        code('RECAP_SCOPE_TOO_LARGE'),
      );
    },
  );

  test(
    'restore snapshots mutable caller input before awaiting database',
    () async {
      await entry();
      final gate = Completer<Database>();
      final held = BookRecapMaterialCatalog(() => gate.future);
      final input = sources(follows: <String>[]);
      final task = held.restoreSelection(session, 'book-a', input);
      input.single['entry_id'] = remote2;
      (input.single['follow_up_ids'] as List).add(followId);
      gate.complete(db);
      final selection = await task;
      expect(selection.single.localEntryId, 'local-a');
      expect(selection.single.followUpIds, isEmpty);
    },
  );

  test('all catalog methods leave SQLite unchanged', () async {
    await entry();
    await follow();
    final changes = await db.rawQuery('SELECT total_changes() AS n');
    expect(await catalog.books(session), hasLength(1));
    expect(
      (await catalog.materials(session, 'book-a')).single.unavailableReason,
      isNull,
    );
    expect(
      await catalog.restoreSelection(
        session,
        'book-a',
        sources(follows: [followId]),
      ),
      hasLength(1),
    );
    expect(await db.rawQuery('SELECT total_changes() AS n'), changes);
  });

  test(
    'no second cache: later calls reflect changed text and deleted local row',
    () async {
      await entry();
      expect(
        (await catalog.materials(session, 'book-a')).single.preview,
        'Synthetic passage',
      );
      await db.update('user_entries', {'original_text': 'Fresh original'});
      expect(
        (await catalog.materials(session, 'book-a')).single.preview,
        'Fresh original',
      );
      await db.delete('user_entries');
      expect(await catalog.books(session), isEmpty);
      expect(await catalog.materials(session, 'book-a'), isEmpty);
      await expectLater(
        catalog.restoreSelection(session, 'book-a', sources()),
        code('LOCAL_RESTORE_UNAVAILABLE'),
      );
    },
  );

  test(
    'guard failure gives safe label, not SQL or exception details',
    () async {
      await entry();
      var reads = 0;
      final brokenGuard = BookRecapMaterialCatalog(() async {
        if (++reads > 1) throw StateError('SQL secret private path token');
        return db;
      });
      final item = (await brokenGuard.materials(session, 'book-a')).single;
      expect(
        item.unavailableReason,
        const RecapMaterialCatalogException(
          'LOCAL_CATALOG_UNAVAILABLE',
        ).message,
      );
      expect(item.unavailableReason, isNot(contains('secret')));
      final brokenCatalog = BookRecapMaterialCatalog(
        () async => throw StateError('PRIVATE'),
      );
      await expectLater(
        brokenCatalog.books(session),
        code('LOCAL_CATALOG_UNAVAILABLE'),
      );
    },
  );

  test(
    'local edit between projection and guard cannot be labelled selectable',
    () async {
      await entry();
      final hook = _QueryHook(db, (table) async {
        if (table == 'user_entry_follow_ups') {
          await db.update('user_entries', {'user_input': 'Concurrent edit'});
        }
      });
      final items = await BookRecapMaterialCatalog(
        () async => hook,
      ).materials(session, 'book-a');
      expect(
        items.single.unavailableReason,
        const RecapClientException('LOCAL_CHANGED').message,
      );
    },
  );

  for (final operation in ['books', 'materials', 'restore']) {
    test('$operation refuses A-B-A during database acquisition', () async {
      await entry();
      final gate = Completer<Database>();
      final held = BookRecapMaterialCatalog(() => gate.future);
      final Future<Object> task = switch (operation) {
        'books' => held.books(session),
        'materials' => held.materials(session, 'book-a'),
        _ => held.restoreSelection(session, 'book-a', sources()),
      };
      final assertion = expectLater(task, throwsA(isA<StaleAuthSession>()));
      AuthSessionScope.publish(other, 'other-token');
      AuthSessionScope.publish(owner, 'synthetic-token');
      gate.complete(db);
      await assertion;
    });

    test('$operation validates session after final database read', () async {
      await entry();
      final hook = _QueryHook(db, (_) async {
        AuthSessionScope.publish(other, 'other-token');
      });
      final held = BookRecapMaterialCatalog(() async => hook);
      final Future<Object> task = switch (operation) {
        'books' => held.books(session),
        'materials' => held.materials(session, 'book-a'),
        _ => held.restoreSelection(session, 'book-a', sources()),
      };
      await expectLater(task, throwsA(isA<StaleAuthSession>()));
    });
  }

  test('signed-out or stale scope cannot acquire the database', () async {
    var reads = 0;
    final held = BookRecapMaterialCatalog(() async {
      reads++;
      return db;
    });
    AuthSessionScope.publish(null, null);
    await expectLater(held.books(session), throwsA(isA<StaleAuthSession>()));
    await expectLater(
      held.books(AuthSessionScope.capture()),
      code('RECAP_AUTH_REQUIRED'),
    );
    expect(reads, 0);
  });

  test(
    'book count overflow refuses entire result instead of truncating',
    () async {
      for (var i = 0; i <= BookRecapMaterialCatalog.maxBooks; i++) {
        await entry(id: 'entry-$i', book: 'book-$i');
      }
      await expectLater(catalog.books(session), code('RECAP_SCOPE_TOO_LARGE'));
    },
  );

  test(
    'material count overflow refuses entire result instead of truncating',
    () async {
      for (var i = 0; i <= BookRecapMaterialCatalog.maxMaterials; i++) {
        await entry(id: 'entry-$i');
      }
      await expectLater(
        catalog.materials(session, 'book-a'),
        code('RECAP_SCOPE_TOO_LARGE'),
      );
    },
  );

  test('follow-up count overflow refuses entire result', () async {
    await entry();
    final batch = db.batch();
    for (var i = 0; i <= BookRecapMaterialCatalog.maxFollowUpRows; i++) {
      batch.insert('user_entry_follow_ups', {
        'id': 'follow-$i',
        'user_id': owner,
        'entry_id': 'local-a',
        'remote_id': followId,
        'remote_synced': 1,
        'question': 'Q',
        'answer': 'A',
        'created_at': '2026-01-01',
      });
    }
    await batch.commit(noResult: true);
    await expectLater(
      catalog.materials(session, 'book-a'),
      code('RECAP_SCOPE_TOO_LARGE'),
    );
  });

  test(
    'body byte budget refuses rather than truncating long original',
    () async {
      await entry(
        original: 'x' * (BookRecapMaterialCatalog.maxPayloadBytes + 1),
      );
      await expectLater(
        catalog.materials(session, 'book-a'),
        code('RECAP_SCOPE_TOO_LARGE'),
      );
    },
  );

  test('invalid book IDs are rejected', () async {
    for (final id in ['', ' padded ', 'x' * 201]) {
      await expectLater(
        catalog.materials(session, id),
        code('INVALID_SELECTION'),
      );
      await expectLater(
        catalog.restoreSelection(session, id, sources()),
        code('INVALID_SELECTION'),
      );
    }
  });

  test(
    'private or malformed restore target fails without exposing prose',
    () async {
      await entry(
        metadata: {
          'nested': {'free_note_id': 'PRIVATE'},
        },
      );
      await expectLater(
        catalog.restoreSelection(session, 'book-a', sources()),
        code('LOCAL_RESTORE_UNAVAILABLE'),
      );
      await db.update('user_entries', {'metadata_json': '{broken'});
      await expectLater(
        catalog.restoreSelection(session, 'book-a', sources()),
        code('LOCAL_RESTORE_UNAVAILABLE'),
      );
    },
  );

  test(
    'restore detects remote identity replacement after exact local mapping',
    () async {
      await entry();
      final hook = _QueryHook(db, (_) async {
        await db.update('user_entries', {'bmob_id': remote2});
      });
      final held = BookRecapMaterialCatalog(() async => hook);
      await expectLater(
        held.restoreSelection(session, 'book-a', sources()),
        code('RECAP_SCOPE_CHANGED'),
      );
    },
  );

  test(
    'session transition inside guard is never swallowed into a choice label',
    () async {
      await entry();
      var reads = 0;
      final held = BookRecapMaterialCatalog(() async {
        if (++reads == 3) AuthSessionScope.publish(other, 'other-token');
        return db;
      });
      await expectLater(
        held.materials(session, 'book-a'),
        throwsA(isA<StaleAuthSession>()),
      );
    },
  );

  test(
    'book scan has a hard bound even when only one distinct book exists',
    () async {
      final batch = db.batch();
      for (var i = 0; i <= BookRecapMaterialCatalog.maxBookScanEntries; i++) {
        batch.insert('user_entries', {
          'id': 'entry-$i',
          'user_id': owner,
          'book_id': 'book-a',
          'source': 'highlight',
          'created_at': '2026-01-01',
        });
      }
      await batch.commit(noResult: true);
      await expectLater(catalog.books(session), code('RECAP_SCOPE_TOO_LARGE'));
    },
  );

  test(
    'aggregate body budget rejects even if each individual proof fits',
    () async {
      final text = 'x' * (BookRecapMaterialCatalog.maxPayloadBytes ~/ 2);
      await entry(original: text);
      await entry(id: 'local-b', remoteId: remote2, original: text);
      await expectLater(
        catalog.materials(session, 'book-a'),
        code('RECAP_SCOPE_TOO_LARGE'),
      );
    },
  );

  test('book title byte budget is also bounded', () async {
    await entry(title: 'x' * BookRecapMaterialCatalog.maxPayloadBytes);
    await expectLater(catalog.books(session), code('RECAP_SCOPE_TOO_LARGE'));
  });

  test(
    'total follow-up row budget rejects across individually valid materials',
    () async {
      final batch = db.batch();
      for (var i = 0; i < 5; i++) {
        await entry(
          id: 'local-$i',
          remoteId: '33333333-3333-4333-8333-${i.toString().padLeft(12, '0')}',
        );
        for (var j = 0; j < 513; j++) {
          batch.insert('user_entry_follow_ups', {
            'id': 'f-$i-$j',
            'user_id': owner,
            'entry_id': 'local-$i',
            'remote_id': followId,
            'remote_synced': 1,
            'question': 'Q',
            'answer': 'A',
            'created_at': '2026-01-01',
          });
        }
      }
      await batch.commit(noResult: true);
      await expectLater(
        catalog.materials(session, 'book-a'),
        code('RECAP_SCOPE_TOO_LARGE'),
      );
    },
  );

  test(
    'restore total follow-up budget is checked before database acquisition',
    () async {
      var reads = 0;
      final held = BookRecapMaterialCatalog(() async {
        reads++;
        return db;
      });
      final ids = List.generate(
        161,
        (i) => '55555555-5555-4555-8555-${i.toString().padLeft(12, '0')}',
      );
      await expectLater(
        held.restoreSelection(session, 'book-a', [
          ...sources(follows: ids),
          ...sources(id: remote2, follows: ids),
        ]),
        code('RECAP_SCOPE_TOO_LARGE'),
      );
      expect(reads, 0);
    },
  );
}
