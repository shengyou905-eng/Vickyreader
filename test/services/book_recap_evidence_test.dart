import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_reader/services/auth_session_scope.dart';
import 'package:ai_reader/services/book_recap_evidence.dart';
import 'package:ai_reader/services/database_service.dart';
import 'package:ai_reader/services/upload_revision.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final root = Directory.current.path.endsWith('reliable_upload_tests')
      ? '../..'
      : '.';
  final fixture =
      jsonDecode(
            File(
              '$root/tool/book_recap_eval/fixture.v1.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final owner = fixture['owner'] as String;
  final book = fixture['bookId'] as String;
  final excerpt = fixture['excerpt'] as String;
  late Directory dir;
  late Database db;
  late AuthSessionScope session;

  setUp(() async {
    AuthSessionScope.beginTransition();
    AuthSessionScope.publish(owner, 'synthetic-token');
    session = AuthSessionScope.capture();
    dir = await Directory.systemTemp.createTemp('zhidu-recap-synthetic-');
    db = await DatabaseService.openForTesting('${dir.path}/test.db');
    await db.rawQuery('PRAGMA journal_mode=WAL');
    await db.insert('books', {
      'id': book,
      'user_id': owner,
      'title': fixture['bookTitle'],
      'author': '',
      'filePath': 'not-read.epub',
      'addedAt': fixture['createdAt'],
      'lastOpenedAt': fixture['createdAt'],
    });
  });
  tearDown(() async {
    await db.close();
    final target = dir.absolute.path;
    if (!target.startsWith(Directory.systemTemp.absolute.path) ||
        !dir.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('zhidu-recap-synthetic-')) {
      throw StateError('Unexpected synthetic test directory');
    }
    await dir.delete(recursive: true);
  });
  Future<void> entry(
    String id, {
    String? user,
    String? bookId,
    String source = 'ai_explanation',
    Map<String, dynamic>? metadata,
    String? original,
  }) async {
    await db.insert('user_entries', {
      'id': id,
      'user_id': user ?? owner,
      'book_id': bookId ?? book,
      'book_title': fixture['bookTitle'],
      'chapter_index': fixture['chapterIndex'],
      'chapter_title': 'Synthetic chapter',
      'source': source,
      'original_text': original ?? excerpt,
      'user_input': source == 'ai_question' ? fixture['question'] : '',
      'ai_explanation': fixture['answer'],
      'metadata_json': jsonEncode(
        metadata ??
            {
              'reading_ai_context': {
                'scope': 'selection',
                'selectedText': excerpt,
              },
            },
      ),
      'created_at': fixture['createdAt'],
    });
  }

  Future<void> follow(
    String id,
    String parent, {
    String? user,
    String remote = '',
  }) async {
    await db.insert('user_entry_follow_ups', {
      'id': id,
      'entry_id': parent,
      'user_id': user ?? owner,
      'question': fixture['followUpQuestion'],
      'answer': fixture['followUpAnswer'],
      'created_at': fixture['createdAt'],
      'remote_id': remote,
    });
  }

  Future<Map<String, dynamic>> read({
    List<Map<String, dynamic>> remote = const [],
    RecapDocument? document,
    Set<String>? selected,
  }) async => (await BookRecapEvidence.read(
    db,
    session: session,
    bookId: book,
    remoteRows: remote,
    remoteOrigin: session.origin,
    document: document,
    selectedEntryIds: selected,
  )).toJson();
  List<Map<String, dynamic>> evidence(Map<String, dynamic> value) =>
      (value['evidence'] as List).cast<Map<String, dynamic>>();
  RecapDocument document(String text) => RecapDocument(
    userId: owner,
    bookId: book,
    version: 'edition-2',
    chapters: {fixture['chapterIndex'] as String: text},
  );

  test(
    'stable book ID, explicit ownership, independent readings and follow-ups',
    () async {
      await entry('a', source: 'ai_question');
      await entry('b');
      await entry('other-edition', bookId: 'same-title-different-id');
      await entry('foreign', user: 'B');
      await entry('unknown', user: '');
      await follow('f1', 'a');
      await follow('f2', 'a');
      await follow('wrong', 'a', user: 'B');
      await follow('legacy', 'a', user: '');
      final value = await read();
      expect(value['coverage']['includedEntries'], 2);
      expect(value['coverage']['includedFollowUps'], 2);
      expect(
        evidence(value).where((e) => e['kind'] == 'book_excerpt'),
        hasLength(2),
      );
      expect(
        evidence(value).where((e) => e['followUpId'] != null),
        hasLength(4),
      );
      expect(value['coverage']['fullBook'], false);
      expect(await db.query('user_entries'), hasLength(5));
    },
  );

  test(
    'snapshot is SELECT-only: DB/WAL and pending metadata are unchanged',
    () async {
      await entry('a');
      await follow('f', 'a');
      await db.insert('pending_upload_operations', {
        'operation_id': 'op',
        'user_id': owner,
        'entity_type': 'trace',
        'entity_id': 'a',
        'operation': 'update',
        'client_revision': 3,
        'generation': 5,
        'retry_count': 7,
        'created_at': fixture['createdAt'],
        'updated_at': fixture['createdAt'],
        'next_retry_at': fixture['createdAt'],
      });
      final changes = await db.rawQuery('SELECT total_changes() AS n');
      final pending = await db.query('pending_upload_operations');
      final files = [
        File('${dir.path}/test.db'),
        File('${dir.path}/test.db-wal'),
      ];
      final before = [for (final f in files) f.readAsBytesSync()];
      final value = await read();
      expect(
        evidence(value)
            .where((e) => e['followUpId'] == null)
            .every((e) => e['pendingUpload'] == true),
        true,
      );
      expect(await db.rawQuery('SELECT total_changes() AS n'), changes);
      expect(await db.query('pending_upload_operations'), pending);
      for (var i = 0; i < files.length; i++) {
        expect(files[i].readAsBytesSync(), before[i]);
      }
    },
  );

  test(
    'local edits replace old remote metadata; unknown owner cache is excluded',
    () async {
      await entry('a', metadata: {});
      final value = await read(
        remote: [
          {
            'id': 'remote-a',
            'client_entry_id': 'a',
            'user_id': owner,
            'book_id': book,
            'source': 'ai_explanation',
            'original_text': 'OLD',
            'metadata_json': {
              'reading_ai_context': {'selectedText': 'OLD'},
            },
          },
          {
            'id': 'unknown',
            'book_id': book,
            'source': 'highlight',
            'original_text': 'SECRET',
          },
        ],
      );
      expect(jsonEncode(value), isNot(contains('OLD')));
      expect(jsonEncode(value), isNot(contains('SECRET')));
      expect(
        evidence(value).where((e) => e['kind'] == 'book_excerpt'),
        isEmpty,
      );
    },
  );

  test('pending deletion excludes trace and its follow-ups', () async {
    await entry('a');
    await follow('f', 'a');
    await db.insert('pending_upload_operations', {
      'operation_id': 'delete',
      'user_id': owner,
      'entity_type': 'trace',
      'entity_id': 'a',
      'operation': 'delete',
      'created_at': fixture['createdAt'],
      'updated_at': fixture['createdAt'],
      'next_retry_at': fixture['createdAt'],
    });
    expect(evidence(await read()), isEmpty);
  });

  test(
    'permanent book deletion fails closed; archived book can still be read',
    () async {
      await entry('a');
      await db.update('books', {'is_archived': 1});
      expect(evidence(await read()), isNotEmpty);
      await db.insert('locally_deleted_books', {
        'user_id': owner,
        'book_id': book,
      });
      await expectLater(read(), throwsStateError);
    },
  );

  test(
    'no free notes, authorized notes, public traces or AI prompts as book facts',
    () async {
      await db.insert('free_notes', {
        'id': 'private',
        'user_id': owner,
        'content': 'PRIVATE SECRET',
        'xiaou_authorized': 1,
        'created_at': fixture['createdAt'],
        'updated_at': fixture['createdAt'],
      });
      await entry('excluded', metadata: {'origin': 'free_note'});
      await entry('ask', source: 'thought', metadata: {'origin': 'xiaou_asks'});
      await entry('old', metadata: {});
      final value = await read();
      expect(value['coverage']['quarantinedEntries'], 1);
      expect(jsonEncode(value), isNot(contains('PRIVATE SECRET')));
      expect(
        evidence(value).where((e) => e['kind'] == 'book_excerpt'),
        isEmpty,
      );
      expect(evidence(value).any((e) => e['kind'] == 'ai_prompt'), true);
      expect(
        evidence(value).any((e) => e['kind'] == 'unverified_excerpt'),
        true,
      );
    },
  );

  test(
    'business selection confirms highlight without treating attention as agreement',
    () async {
      await db.insert('highlights', {
        'id': 'h',
        'user_id': owner,
        'bookId': book,
        'chapterIndex': '7',
        'selectedText': excerpt,
        'startOffset': 0,
        'endOffset': excerpt.length,
        'createdAt': fixture['createdAt'],
      });
      await entry(
        'a',
        source: 'highlight',
        metadata: {'source_record_id': 'h'},
      );
      final rows = evidence(await read());
      expect(rows.where((e) => e['kind'] == 'highlight'), hasLength(1));
      expect(rows.where((e) => e['kind'] == 'book_excerpt'), hasLength(1));
      expect(rows.where((e) => e['kind'] == 'user_note'), isEmpty);
    },
  );

  test(
    'reimport does not trust legacy offsets and duplicate text never fabricates a jump',
    () async {
      await entry(
        'a',
        metadata: {
          'reading_ai_context': {'selectedText': excerpt},
          'startOffset': 0,
          'endOffset': excerpt.length,
        },
      );
      final duplicate = evidence(
        await read(document: document('$excerpt $excerpt')),
      ).firstWhere((e) => e['kind'] == 'book_excerpt');
      expect(duplicate['anchor']['status'], 'ambiguous');
      expect(duplicate['anchor']['start'], null);
      final changed = evidence(
        await read(document: document('Different edition.')),
      );
      expect(changed.where((e) => e['kind'] == 'book_excerpt'), isEmpty);
      expect(changed.any((e) => e['anchor']?['status'] == 'changed'), true);
      final exact = evidence(
        await read(document: document('Prefix. $excerpt')),
      );
      expect(
        exact.firstWhere((e) => e['kind'] == 'book_excerpt')['anchor']['start'],
        8,
      );
    },
  );

  test(
    'missing book file keeps recorded fragment; legacy text can be checked against owned document',
    () async {
      await entry('a');
      expect(
        evidence(
          await read(),
        ).firstWhere((e) => e['kind'] == 'book_excerpt')['anchor']['status'],
        'fragment_only',
      );
      await db.update('user_entries', {'metadata_json': '{}'});
      expect(
        evidence(
          await read(document: document(excerpt)),
        ).firstWhere((e) => e['kind'] == 'book_excerpt')['provenance'],
        'current_document',
      );
    },
  );

  test(
    'edits and new follow-ups change fingerprints; explicit subset reports coverage',
    () async {
      await entry('a');
      await entry('b');
      final original = await read();
      expect((await read())['fingerprint'], original['fingerprint']);
      await follow('f', 'a');
      expect((await read())['fingerprint'], isNot(original['fingerprint']));
      final before = await read();
      await db.update(
        'user_entries',
        {'user_input': 'A new thought'},
        where: 'id = ?',
        whereArgs: ['a'],
      );
      expect((await read())['fingerprint'], isNot(before['fingerprint']));
      final subset = await read(selected: {'a'});
      expect(subset['coverage']['availableEntries'], 2);
      expect(subset['coverage']['includedEntries'], 1);
      await expectLater(read(selected: {'foreign'}), throwsStateError);
    },
  );

  test('A to B to A invalidates exported snapshot and queued reads', () async {
    await entry('a');
    final snapshot = await BookRecapEvidence.read(
      db,
      session: session,
      bookId: book,
    );
    AuthSessionScope.beginTransition();
    AuthSessionScope.publish('B', 'b');
    AuthSessionScope.beginTransition();
    AuthSessionScope.publish(owner, 'a-new');
    expect(snapshot.toJson, throwsA(isA<StaleAuthSession>()));
    await expectLater(read(), throwsA(isA<StaleAuthSession>()));
  });

  test(
    'retained tombstone still hides a remote trace after queue removal',
    () async {
      await entry('a');
      await follow('f', 'a');
      await db.insert('upload_entity_revisions', {
        'user_id': owner,
        'entity_type': 'trace',
        'entity_id': 'a',
        'last_revision': 5,
        'state_hash': uploadStateHash('delete', const {}),
        'book_id': book,
      });
      final value = await read(
        remote: [
          {
            'id': 'remote-a',
            'client_entry_id': 'a',
            'user_id': owner,
            'book_id': book,
            'source': 'ai_explanation',
            'original_text': excerpt,
          },
        ],
      );
      expect(evidence(value), isEmpty);
    },
  );

  test(
    'a read queued before account switching cannot finish under the new session',
    () async {
      await entry('a');
      final started = Completer<void>();
      final release = Completer<void>();
      final blocker = db.transaction((txn) async {
        started.complete();
        await release.future;
      });
      await started.future;
      final waiting = read();
      final rejected = expectLater(waiting, throwsA(isA<StaleAuthSession>()));
      AuthSessionScope.beginTransition();
      AuthSessionScope.publish('B', 'b');
      AuthSessionScope.beginTransition();
      AuthSessionScope.publish(owner, 'a-again');
      release.complete();
      await blocker;
      await rejected;
    },
  );

  test(
    'remote aliases retain follow-up identity and conflicting aliases fail closed',
    () async {
      await entry('a');
      await follow('f-local', 'a', remote: 'f-remote');
      await follow('f-copy', 'remote-a', remote: 'f-remote');
      final remote = {
        'id': 'remote-a',
        'client_entry_id': 'a',
        'user_id': owner,
        'book_id': book,
        'source': 'ai_explanation',
      };
      expect(
        (await read(remote: [remote]))['coverage']['includedFollowUps'],
        1,
      );
      await expectLater(
        read(
          remote: [
            remote,
            {...remote, 'id': 'conflicting'},
          ],
        ),
        throwsStateError,
      );
      await expectLater(
        BookRecapEvidence.read(
          db,
          session: session,
          bookId: book,
          remoteRows: [remote],
          remoteOrigin: 'https://wrong.invalid',
        ),
        throwsStateError,
      );
    },
  );

  test(
    'actual Dart snapshot passes the Node contract with the shared synthetic fixture',
    () async {
      await entry('a', source: 'ai_question');
      await follow('f', 'a');
      final value = await read(document: document(excerpt));
      final module = File(
        '$root/backend/src/services/bookRecapContract.js',
      ).absolute.path;
      final process = await Process.run('node', [
        '-e',
        'const c=require(process.argv[1]);const s=JSON.parse(process.argv[2]);'
            'c.validateSnapshot(s,s.scope);process.stdout.write("valid");',
        module,
        jsonEncode(value),
      ]);
      expect(process.exitCode, 0, reason: process.stderr.toString());
      expect(process.stdout, 'valid');
    },
  );

  test(
    'more than 500 traces are counted, never silently clipped to the legacy API limit',
    () async {
      final batch = db.batch();
      for (var i = 0; i < 501; i++) {
        batch.insert('user_entries', {
          'id': 'bulk-$i',
          'user_id': owner,
          'book_id': book,
          'source': 'thought',
          'user_input': 'Synthetic thought $i',
          'created_at': fixture['createdAt'],
        });
      }
      await batch.commit(noResult: true);
      await follow('last-batch-follow', 'bulk-99');
      final all = await read();
      expect(all['coverage']['availableEntries'], 501);
      expect(evidence(all), hasLength(503));
      expect(all['coverage']['includedFollowUps'], 1);
      final selected = await read(selected: {'bulk-1'});
      expect(selected['coverage']['availableEntries'], 501);
      expect(selected['coverage']['includedEntries'], 1);
      expect(selected['coverage']['selectionApplied'], true);
      expect(selected['coverage']['includedFollowUps'], 0);
    },
  );
}
