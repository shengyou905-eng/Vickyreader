import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_reader/providers/book_recap_controller.dart';
import 'package:ai_reader/services/auth_session_scope.dart';
import 'package:ai_reader/services/book_recap_client_api.dart';
import 'package:ai_reader/services/book_recap_client_contract.dart';
import 'package:ai_reader/services/book_recap_local_guard.dart';
import 'package:ai_reader/services/database_service.dart';
import 'package:ai_reader/services/upload_revision.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const owner = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
const remote = '33333333-3333-4333-8333-333333333333';
const remote2 = '44444444-4444-4444-8444-444444444444';
const followId = '55555555-5555-4555-8555-555555555555';
const recap = '66666666-6666-4666-8666-666666666666';
const feedbackId = '77777777-7777-4777-8777-777777777777';
final fingerprint = 'a' * 64;

class _LoopbackHttp extends HttpOverrides {}

Map<String, dynamic> coverage({int follows = 0}) => {
  'basis': 'reading_traces',
  'fullBook': false,
  'sourceCompleteness': 'server_selected_records',
  'availableEntries': 1,
  'includedEntries': 1,
  'includedFollowUps': follows,
  'quarantinedEntries': 0,
  'selectionApplied': true,
};
Map<String, dynamic> result() => {
  'schemaVersion': 1,
  'snapshotFingerprint': fingerprint,
  'knowledge': [
    {
      'id': 'k1',
      'kind': 'concept',
      'title': 'Synthetic concept',
      'summary': 'Synthetic explanation',
      'basis': 'source_supported',
      'evidenceRefs': ['e-1'],
      'quotes': [],
    },
  ],
  'relations': [],
  'myThinking': [],
  'openQuestions': [],
  'nextQuestions': [],
};
Map<String, dynamic> response({
  String id = recap,
  String state = 'ready',
  String revision = '2',
  bool saved = false,
  List<String> follows = const [],
}) => {
  'id': id,
  'book_id': 'book-a',
  'revision': revision,
  'state': state,
  'is_saved': saved,
  'source_fingerprint': fingerprint,
  'coverage': coverage(follows: follows.length),
  'sources': [
    {'entry_id': remote, 'follow_up_ids': follows},
  ],
  'evidence_summary': {'transmitted': 2, 'excluded_unverified': 0},
  'result': state == 'ready' ? result() : null,
  'scope_basis': 'selected_cloud_records_only',
  'local_pending_verified': false,
};
Matcher code(String expected) => throwsA(
  isA<RecapClientException>().having((e) => e.code, 'safe code', expected),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database db;
  late Directory dir;
  late BookRecapLocalGuard guard;
  late AuthSessionScope session;
  late ValueNotifier<int> changes;
  final controllers = <BookRecapController>[];
  final requests = <http.Request>[];
  late Future<http.Response> Function(http.Request) handler;
  late Map<String, dynamic> current;

  Future<void> entry({
    String id = 'local-a',
    String user = owner,
    String book = 'book-a',
    String remoteId = remote,
  }) => db
      .insert('user_entries', {
        'id': id,
        'user_id': user,
        'book_id': book,
        'bmob_id': remoteId,
        'source': 'ai_explanation',
        'original_text': 'Synthetic passage',
        'metadata_json': jsonEncode({
          'origin': 'reader',
          'reading_ai_context': {
            'scope': 'selection',
            'selectedText': 'Synthetic passage',
          },
        }),
        'created_at': '2026-01-01T00:00:00Z',
      })
      .then((_) {});
  Future<void> follow({
    String user = owner,
    String parent = 'local-a',
    int synced = 1,
    String remoteId = followId,
    String id = 'local-follow',
  }) => db
      .insert('user_entry_follow_ups', {
        'id': id,
        'user_id': user,
        'entry_id': parent,
        'remote_id': remoteId,
        'remote_synced': synced,
        'question': 'Synthetic question',
        'answer': 'Synthetic answer',
        'created_at': '2026-01-01T00:00:00Z',
      })
      .then((_) {});
  Future<void> pending(String operation) => db
      .insert('pending_upload_operations', {
        'operation_id': 'op-a',
        'user_id': owner,
        'entity_type': 'trace',
        'entity_id': 'local-a',
        'operation': operation,
        'payload_json': '{}',
        'created_at': '2026-01-01',
        'updated_at': '2026-01-01',
        'next_retry_at': '2026-01-01',
      })
      .then((_) {});
  List<RecapLocalSelection> selection([
    RecapFollowScope mode = RecapFollowScope.none,
  ]) => [
    RecapLocalSelection(
      'local-a',
      followScope: mode,
      followUpIds: mode == RecapFollowScope.selected ? [followId] : [],
    ),
  ];
  Future<RecapLocalProof> inspect([List<RecapLocalSelection>? selected]) =>
      guard.inspect(session, 'book-a', selected ?? selection());
  BookRecapClientApi api({
    bool enabled = true,
    Duration? timeout,
    DateTime Function()? grantClock,
  }) => BookRecapClientApi(
    baseUri: Uri.parse('http://127.0.0.1/recaps'),
    enabled: enabled,
    loopbackTest: true,
    timeout: timeout ?? const Duration(seconds: 2),
    tokenProvider: (_) => 'synthetic-token',
    clientFactory: () => MockClient((request) async {
      requests.add(request);
      if (request.url.path.contains('/display/')) {
        final now = (grantClock ?? DateTime.now)().toUtc();
        final grant = {
          'protocol_version': 1,
          'policy_version': 'synthetic-only',
          'recap_id': current['id'],
          'book_id': current['book_id'],
          'revision': current['revision'],
          'source_fingerprint': current['source_fingerprint'],
          'checked_at': now.toIso8601String(),
          'expires_at': now.add(const Duration(seconds: 30)).toIso8601String(),
          'max_age_ms': 30000,
          'local_pending_verified': false,
          'requires_online_on_open': true,
        };
        return http.Response(
          jsonEncode({
            if (request.url.path.endsWith('/view')) 'recap': current,
            'display': grant,
          }),
          200,
        );
      }
      return handler(request);
    }),
  );
  BookRecapController controller({BookRecapClientApi? client}) {
    final c = BookRecapController(
      api: client ?? api(),
      localGuard: guard,
      bookId: 'book-a',
      localChanges: changes,
      displayLifetime: const Duration(seconds: 30),
      approvedDisplayPolicies: const {'synthetic-only'},
    );
    controllers.add(c);
    return c;
  }

  Future<BookRecapController> opened() async {
    final c = controller();
    await c.open(recap, selection());
    return c;
  }

  setUp(() async {
    AuthSessionScope.beginTransition();
    AuthSessionScope.publish(owner, 'synthetic-token');
    session = AuthSessionScope.capture();
    changes = ValueNotifier(0);
    requests.clear();
    dir = await Directory.systemTemp.createTemp(
      'zhidu-recap-client-synthetic-',
    );
    db = await DatabaseService.openForTesting('${dir.path}/test.db');
    guard = BookRecapLocalGuard(() async => db);
    await entry();
    current = response();
    handler = (request) async {
      if (request.method == 'DELETE' || request.url.path.endsWith('/cancel')) {
        return http.Response('', 204);
      }
      if (request.url.path.endsWith('/prepare')) {
        final body = jsonDecode(request.body) as Map;
        current = response(
          id: body['recap_id'],
          state: 'prepared',
          revision: '1',
        );
      } else if (request.url.path.endsWith('/generate')) {
        current = response(id: current['id']);
        return http.Response(
          jsonEncode({'status': 'succeeded', 'replay': false}),
          200,
        );
      } else if (request.url.path.endsWith('/save')) {
        current = response(id: current['id'], saved: true, revision: '3');
      } else if (request.url.path.endsWith('/feedback')) {
        return http.Response(jsonEncode({'id': feedbackId}), 200);
      } else if (request.url.path.endsWith('/follow-ups')) {
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({'status': 'succeeded', 'replay': false}),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'revision': current['revision'],
            'source_fingerprint': fingerprint,
            'coverage': coverage(),
            'local_pending_verified': false,
            'turns': [],
          }),
          200,
        );
      }
      return http.Response(jsonEncode(current), 200);
    };
  });
  tearDown(() async {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
    changes.dispose();
    await db.close();
    // Delete only this test's newly-created synthetic directory.
    if (!dir.absolute.path.startsWith(Directory.systemTemp.absolute.path) ||
        !dir.uri.pathSegments.any(
          (s) => s.startsWith('zhidu-recap-client-synthetic-'),
        )) {
      throw StateError('Unexpected synthetic directory');
    }
    await dir.delete(recursive: true);
  });

  test(
    'read-only guard leaves original rows and upload state unchanged',
    () async {
      final before = await db.rawQuery('SELECT total_changes() AS n');
      final proof = await inspect();
      expect(proof.sources, [
        {'entry_id': remote, 'follow_up_ids': []},
      ]);
      expect(await db.rawQuery('SELECT total_changes() AS n'), before);
      expect(await db.query('pending_upload_operations'), isEmpty);
      expect(await db.query('user_entries'), hasLength(1));
    },
  );
  test('personal pilot ready status restores metadata but no display permit', () async {
    handler = (_) async => http.Response(
      jsonEncode(Map.of(current)..remove('result')), 200);
    final c = await opened();
    expect(c.header!.state, RecapServerState.ready);
    expect(c.content, isNull);
    expect(requests.single.method, 'GET');
  });
  for (final operation in ['upsert', 'delete']) {
    test('pending $operation blocks whole selection without upload', () async {
      await pending(operation);
      final c = controller();
      await expectLater(
        c.prepare(selection()),
        code(operation == 'delete' ? 'LOCAL_DELETED' : 'LOCAL_PENDING'),
      );
      expect(requests, isEmpty);
      expect(await db.query('pending_upload_operations'), hasLength(1));
    });
  }
  test(
    'mixed synced and missing remote IDs cannot silently reduce scope',
    () async {
      await entry(id: 'new', remoteId: '');
      await expectLater(
        inspect([...selection(), RecapLocalSelection('new')]),
        code('LOCAL_IDENTITY_MISSING'),
      );
    },
  );
  test(
    'permanent deletion and revision tombstone reject remote old rows',
    () async {
      await db.insert('upload_entity_revisions', {
        'user_id': owner,
        'entity_type': 'trace',
        'entity_id': remote,
        'last_revision': 5,
        'state_hash': uploadStateHash('delete', {}),
        'book_id': 'book-a',
      });
      await expectLater(inspect(), code('LOCAL_DELETED'));
      await db.delete('upload_entity_revisions');
      await db.insert('locally_deleted_books', {
        'user_id': owner,
        'book_id': 'book-a',
      });
      await expectLater(inspect(), code('LOCAL_DELETED'));
    },
  );
  test(
    'ordinary shelf removal and missing book file do not delete evidence',
    () async {
      expect(await db.query('books'), isEmpty);
      expect((await inspect()).sources, hasLength(1));
    },
  );
  test(
    'A/B same book and same content never imply ownership or identity',
    () async {
      await entry(id: 'b', user: other, remoteId: remote2);
      await expectLater(
        inspect([RecapLocalSelection('b')]),
        code('LOCAL_IDENTITY_MISSING'),
      );
      await entry(id: 'other-book', book: 'book-b', remoteId: followId);
      await expectLater(
        inspect([RecapLocalSelection('other-book')]),
        code('LOCAL_IDENTITY_MISSING'),
      );
      await db.update(
        'user_entries',
        {'user_id': ''},
        where: 'id = ?',
        whereArgs: ['local-a'],
      );
      await expectLater(inspect(), code('LOCAL_IDENTITY_MISSING'));
    },
  );
  test(
    'duplicate remote aliases reject, independent records remain separate',
    () async {
      await entry(id: 'independent', remoteId: remote2);
      expect(
        (await inspect([
          ...selection(),
          RecapLocalSelection('independent'),
        ])).sources,
        hasLength(2),
      );
      await entry(id: 'alias');
      await expectLater(inspect(), code('LOCAL_IDENTITY_MISSING'));
    },
  );
  test(
    'all, none and selected follow-ups retain distinct wire contracts',
    () async {
      await follow();
      expect(
        (await inspect(
          selection(RecapFollowScope.all),
        )).sources.single.containsKey('follow_up_ids'),
        false,
      );
      expect((await inspect()).sources.single['follow_up_ids'], []);
      expect(
        (await inspect(
          selection(RecapFollowScope.selected),
        )).sources.single['follow_up_ids'],
        [followId],
      );
    },
  );
  test(
    'pending or unknown follow-up ownership blocks even empty selection',
    () async {
      await follow(synced: 0, remoteId: '');
      await expectLater(inspect(), code('LOCAL_PENDING'));
      await db.delete('user_entry_follow_ups');
      await follow(user: '');
      await expectLater(inspect(), code('LOCAL_IDENTITY_MISSING'));
    },
  );
  test('follow-up parent mismatch and unknown subset are rejected', () async {
    await follow(parent: 'elsewhere');
    await expectLater(
      inspect(selection(RecapFollowScope.selected)),
      code('LOCAL_IDENTITY_MISSING'),
    );
  });
  test(
    'authorized free note markers are excluded without reading free_notes',
    () async {
      await db.update('user_entries', {
        'metadata_json': jsonEncode({
          'nested': {'authorized_free_note': true},
        }),
      });
      await expectLater(inspect(), code('LOCAL_IDENTITY_MISSING'));
    },
  );
  test(
    'local content and follow-up changes alter proof without timestamp changes',
    () async {
      final original = await inspect();
      await db.update('user_entries', {'user_input': 'Changed locally'});
      final edited = await inspect();
      expect(edited.fingerprint, isNot(original.fingerprint));
      await follow();
      expect((await inspect()).fingerprint, isNot(edited.fingerprint));
    },
  );
  test('default disabled client makes no network request', () async {
    await expectLater(
      controller(client: api(enabled: false)).prepare(selection()),
      code('NOT_CONFIGURED'),
    );
    expect(requests, isEmpty);
  });
  test(
    'prepare confirmation generate save feedback and delete use real adapter shapes',
    () async {
      final c = controller();
      await c.prepare(selection());
      expect(c.phase, RecapClientPhase.confirmation);
      await expectLater(c.generate(), code('CONFIRM_REQUIRED'));
      await c.confirmScope(
        fingerprint: c.header!.sourceFingerprint,
        revision: c.header!.revision,
      );
      await c.generate();
      expect(c.phase, RecapClientPhase.ready);
      expect(c.header!.isSaved, false);
      await c.save();
      expect(c.header!.state, RecapServerState.ready);
      expect(c.header!.isSaved, true);
      await c.feedback('inaccurate', comment: 'Synthetic feedback');
      expect((await c.readForDisplay()).toJson()['result'], isNotNull);
      await c.delete();
      expect(c.phase, RecapClientPhase.invalidated);
      expect(c.header, isNull);
      await expectLater(c.readForDisplay(), code('RECAP_UNAVAILABLE'));
      expect(requests.every((r) => r.url.path.startsWith('/recaps/')), true);
      final prepareBody = jsonDecode(requests.first.body) as Map;
      expect(prepareBody.keys.toSet(), {
        'recap_id',
        'request_id',
        'book_id',
        'selected_sources',
      });
      expect(prepareBody.toString(), isNot(contains('Synthetic passage')));
      expect(prepareBody.containsKey('user_id'), false);
    },
  );
  test(
    'server expansion of explicit empty follow-up scope is rejected',
    () async {
      current = response(follows: [followId]);
      await expectLater(
        controller().open(recap, selection()),
        code('RECAP_SCOPE_CHANGED'),
      );
    },
  );
  test(
    'saved is an attribute and malformed coverage/result/fingerprint fail closed',
    () async {
      expect(RecapHeader.parse(response(saved: true)).isSaved, true);
      for (final corrupt in <void Function(Map<String, dynamic>)>[
        (v) => v['state'] = 'saved',
        (v) => v['local_pending_verified'] = true,
        (v) => v['coverage']['fullBook'] = true,
        (v) => v['coverage']['sourceCompleteness'] = 'local_and_supplied_cache',
        (v) => v['result']['snapshotFingerprint'] = 'b' * 64,
        (v) => v['result']['knowledge'][0]['evidenceRefs'] = [],
        (v) => v['result']['knowledge'][0]['basis'] = 'certain_fact',
        (v) => v['internal_secret'] = 'not-public',
      ]) {
        final v = response();
        corrupt(v);
        expect(
          () => RecapHeader.parse(v),
          throwsA(isA<RecapClientException>()),
        );
      }
    },
  );
  test(
    '14 complete follow-up pairs accepted; ordinary chat DTO is rejected',
    () async {
      final c = await opened();
      final normal = handler;
      handler = (r) async {
        if (r.url.path.endsWith('/follow-ups')) {
          return http.Response(
            jsonEncode({
              'revision': '2',
              'source_fingerprint': fingerprint,
              'coverage': coverage(),
              'local_pending_verified': false,
              'turns': List.generate(
                14,
                (i) => {
                  'turn': i + 1,
                  'question': 'Question $i',
                  'answer': {
                    'schemaVersion': 1,
                    'snapshotFingerprint': fingerprint,
                    'parts': [
                      {
                        'text': 'Uncertain inference',
                        'basis': 'ai_inference',
                        'evidenceRefs': ['e-1'],
                        'quotes': [],
                      },
                    ],
                  },
                },
              ),
            }),
            200,
          );
        }
        return normal(r);
      };
      expect((await c.followUpsForDisplay()).toJson()['turns'], hasLength(14));
      handler = (r) async => r.url.path.endsWith('/follow-ups')
          ? http.Response(
              jsonEncode({
                'messages': [
                  {'role': 'assistant', 'content': 'ordinary chat'},
                ],
              }),
              200,
            )
          : normal(r);
      await expectLater(c.followUpsForDisplay(), code('INVALID_RESPONSE'));
    },
  );
  test('late GET after A to B to A cannot publish header or prose', () async {
    final c = controller();
    final entered = Completer<void>(), release = Completer<void>();
    handler = (_) async {
      entered.complete();
      await release.future;
      return http.Response(jsonEncode(current), 200);
    };
    final request = c.open(recap, selection());
    final assertion = expectLater(
      request,
      throwsA(isA<RecapClientException>()),
    );
    await entered.future;
    AuthSessionScope.publish(other, 'other-token');
    AuthSessionScope.publish(owner, 'synthetic-token');
    release.complete();
    await assertion;
    expect(c.header, isNull);
    expect(c.phase, RecapClientPhase.unavailable);
    expect(c.replayRequestId, isNull);
  });
  test(
    'local edit during GET rejects old cloud body, without local write overwrite',
    () async {
      final c = await opened();
      handler = (_) async {
        await db.update('user_entries', {'user_input': 'Unsynced local edit'});
        return http.Response(jsonEncode(current), 200);
      };
      await expectLater(c.readForDisplay(), code('LOCAL_CHANGED'));
      expect(c.phase, RecapClientPhase.stale);
      expect(
        (await db.query('user_entries')).single['user_input'],
        'Unsynced local edit',
      );
    },
  );
  test(
    'no body disk cache; offline/background/reopen never reuse a successful GET',
    () async {
      final c = await opened();
      await c.readForDisplay();
      final count = requests.length;
      c.setOnline(false);
      await expectLater(c.readForDisplay(), code('OFFLINE'));
      expect(requests.length, count);
      c.setOnline(true);
      c.suspend();
      await c.readForDisplay();
      expect(requests.length, count + 2);
      expect(requests.last.url.path, endsWith('/view'));
      handler = (_) async => throw const SocketException('synthetic');
      await expectLater(c.readForDisplay(), code('NETWORK'));
      expect(c.phase, RecapClientPhase.offline);
    },
  );
  test(
    'local notifications revoke in-flight read even when SQL unchanged',
    () async {
      final c = await opened();
      handler = (_) async {
        changes.value++;
        return http.Response(jsonEncode(current), 200);
      };
      await expectLater(c.readForDisplay(), code('CANCELLED'));
      expect(c.phase, RecapClientPhase.stale);
    },
  );
  for (final pair in [
    ('RECAP_SOURCE_CHANGED', 409, RecapClientPhase.stale),
    ('RECAP_UNAVAILABLE', 410, RecapClientPhase.invalidated),
    ('RECAP_REVISION_CONFLICT', 412, RecapClientPhase.reconfirm),
    ('AI_CONSENT_REQUIRED', 428, RecapClientPhase.unavailable),
  ]) {
    test('server ${pair.$1} withdraws body and gives safe state', () async {
      final c = await opened();
      handler = (_) async => http.Response(
        jsonEncode({'error_code': pair.$1, 'error': 'SQL private secret'}),
        pair.$2,
      );
      await expectLater(c.readForDisplay(), code(pair.$1));
      expect(c.phase, pair.$3);
      expect(c.message, isNot(contains('SQL')));
    });
  }
  test('same identity new token invalidates old controller', () async {
    final c = await opened();
    AuthSessionScope.publish(owner, 'new-token');
    await expectLater(c.readForDisplay(), code('AUTH_CHANGED'));
    expect(c.header, isNull);
  });
  test(
    'save and follow-up cannot race locally; no second mutation request',
    () async {
      final c = await opened();
      final entered = Completer<void>(), release = Completer<void>();
      final normal = handler;
      handler = (r) async {
        if (r.url.path.endsWith('/save')) {
          entered.complete();
          await release.future;
        }
        return normal(r);
      };
      final saving = c.save();
      await entered.future;
      await expectLater(c.followUp('Another question'), code('BUSY'));
      release.complete();
      await saving;
      expect(
        requests.where(
          (r) => r.method == 'POST' && r.url.path.endsWith('/follow-ups'),
        ),
        isEmpty,
      );
    },
  );
  test(
    'lost response explicit replay keeps identical request ID/body and no auto retry',
    () async {
      final c = await opened();
      final normal = handler;
      var calls = 0;
      handler = (r) async {
        if (r.url.path.endsWith('/follow-ups') &&
            r.method == 'POST' &&
            calls++ == 0) {
          throw const SocketException('lost response');
        }
        return normal(r);
      };
      await expectLater(c.followUp('Same original question'), code('NETWORK'));
      expect(calls, 1);
      await expectLater(
        c.followUp('Do not pay again'),
        code('CONFIRM_REQUIRED'),
      );
      await c.replay();
      final posts = requests
          .where(
            (r) => r.method == 'POST' && r.url.path.endsWith('/follow-ups'),
          )
          .toList();
      expect(posts, hasLength(2));
      expect(posts[0].body, posts[1].body);
    },
  );
  test(
    'cancel interrupts wait and late completed response cannot revive view',
    () async {
      final c = await opened();
      final entered = Completer<void>(), release = Completer<void>();
      final normal = handler;
      handler = (r) async {
        if (r.method == 'POST' && r.url.path.endsWith('/follow-ups')) {
          entered.complete();
          await release.future;
        }
        return normal(r);
      };
      final asking = c.followUp('Synthetic held question');
      final assertion = expectLater(asking, code('CANCELLED'));
      await entered.future;
      await c.cancel();
      release.complete();
      await assertion;
      expect(c.phase, RecapClientPhase.cancelled);
      expect(
        requests.where((r) => r.url.path.endsWith('/cancel')),
        hasLength(1),
      );
    },
  );
  test(
    'privacy deletion allowed with pending local deletion and consent absent',
    () async {
      final c = await opened();
      await pending('delete');
      await c.delete();
      expect(c.header, isNull);
      expect(requests.last.method, 'DELETE');
      expect(await db.query('user_entries'), hasLength(1));
    },
  );
  test(
    'offline delete is not acknowledged and old body cannot reopen',
    () async {
      final c = await opened();
      c.setOnline(false);
      await expectLater(c.delete(), code('OFFLINE'));
      c.setOnline(true);
      await expectLater(c.readForDisplay(), code('RECAP_UNAVAILABLE'));
      await expectLater(c.open(recap, selection()), code('CONFIRM_REQUIRED'));
      await c.delete();
      expect(c.header, isNull);
    },
  );
  test(
    'old revision response and different source fingerprint are rejected',
    () async {
      final c = await opened();
      current = response(revision: '1');
      await expectLater(c.refresh(), code('RECAP_REVISION_CONFLICT'));
      current = response();
      current['source_fingerprint'] = 'b' * 64;
      current['result']['snapshotFingerprint'] = 'b' * 64;
      await expectLater(c.refresh(), code('RECAP_SOURCE_CHANGED'));
    },
  );
  test(
    'scope origin mismatch refuses before sending bearer credentials',
    () async {
      final client = BookRecapClientApi(
        baseUri: Uri.parse('https://wrong.invalid/recaps'),
        enabled: true,
        clientFactory: () => MockClient(handler),
        tokenProvider: (_) => 'synthetic-token',
      );
      await expectLater(
        client.send(session, 'GET', recap),
        code('AUTH_CHANGED'),
      );
    },
  );
  test(
    'display content is revoked by local mutation, offline, logout and expiry',
    () async {
      final c = await opened();
      final first = await c.readForDisplay();
      expect(first.toJson()['result'], isNotNull);
      changes.value++;
      expect(first.toJson, code('CONFIRM_REQUIRED'));
      final second = await c.readForDisplay();
      c.setOnline(false);
      expect(second.toJson, code('CONFIRM_REQUIRED'));
      c.setOnline(true);
      final third = await c.readForDisplay();
      AuthSessionScope.publish(null, null);
      expect(third.toJson, code('AUTH_CHANGED'));
    },
  );
  test('explicit display lifetime expires without network polling', () async {
    var now = DateTime.now();
    var elapsed = Duration.zero;
    final c = BookRecapController(
      api: api(grantClock: () => now),
      localGuard: guard,
      bookId: 'book-a',
      localChanges: changes,
      displayLifetime: const Duration(seconds: 2),
      approvedDisplayPolicies: const {'synthetic-only'},
      clock: () => now,
      monotonic: () => elapsed,
    );
    controllers.add(c);
    await c.open(recap, selection());
    final content = await c.readForDisplay();
    final count = requests.length;
    now = now.add(const Duration(seconds: 3));
    elapsed += const Duration(seconds: 3);
    expect(content.toJson, code('CONFIRM_REQUIRED'));
    expect(requests.length, count);
    c.suspend();
    expect(c.phase, RecapClientPhase.reconfirm);
  });
  test(
    'source deletion without notification is caught on every display read',
    () async {
      final c = await opened();
      await c.readForDisplay();
      await db.delete('user_entries', where: 'id = ?', whereArgs: ['local-a']);
      final count = requests.length;
      await expectLater(c.readForDisplay(), code('LOCAL_IDENTITY_MISSING'));
      expect(requests.length, count);
    },
  );
  test(
    'wrong book response, wrong recap and partial follow-up fail closed',
    () async {
      final c = await opened();
      current['book_id'] = 'same-title-other-book';
      await expectLater(c.refresh(), code('RECAP_SCOPE_CHANGED'));
      current = response(id: remote2);
      await expectLater(c.refresh(), code('RECAP_SCOPE_CHANGED'));
      current = response();
      final normal = handler;
      handler = (r) async => r.url.path.endsWith('/follow-ups')
          ? http.Response(
              jsonEncode({
                'revision': '2',
                'source_fingerprint': fingerprint,
                'coverage': coverage(),
                'local_pending_verified': false,
                'turns': [
                  {'turn': 1, 'question': 'Incomplete'},
                ],
              }),
              200,
            )
          : normal(r);
      await expectLater(c.followUpsForDisplay(), code('INVALID_RESPONSE'));
    },
  );
  test(
    'invalid JSON and oversized HTTP bodies are not successful results',
    () async {
      final c = await opened();
      handler = (_) async => http.Response('{"result":', 200);
      await expectLater(c.readForDisplay(), code('INVALID_RESPONSE'));
      handler = (_) async => http.Response('x' * (768 * 1024 + 1), 200);
      await expectLater(c.readForDisplay(), code('INVALID_RESPONSE'));
    },
  );
  test(
    'expired replay is refused without changing request ID or auto sending',
    () async {
      var now = DateTime.utc(2026);
      final c = BookRecapController(
        api: api(),
        localGuard: guard,
        bookId: 'book-a',
        localChanges: changes,
        displayLifetime: const Duration(seconds: 2),
        replayLifetime: const Duration(seconds: 2),
        clock: () => now,
      );
      controllers.add(c);
      await c.open(recap, selection());
      await c.followUp('Synthetic question');
      final count = requests.length;
      now = now.add(const Duration(seconds: 3));
      await expectLater(c.replay(), code('CONFIRM_REQUIRED'));
      expect(requests.length, count);
    },
  );
  test(
    'Dart request bodies validate with actual Node Zod contract without DB',
    () async {
      final c = controller();
      await c.prepare(selection());
      await c.confirmScope(
        fingerprint: c.header!.sourceFingerprint,
        revision: c.header!.revision,
      );
      await c.generate();
      await c.save();
      await c.followUp('Synthetic question');
      await c.cancel();
      await c.feedback('low_value');
      await c.delete();
      final root = Directory.current.path.endsWith('reliable_upload_tests')
          ? '../..'
          : '.';
      final payload = {
        'requests': requests
            .where((r) => r.method != 'GET')
            .map(
              (r) => {
                'method': r.method,
                'path': r.url.path,
                'body': jsonDecode(r.body),
              },
            )
            .toList(),
        'response': response(saved: true),
      };
      final check = await Process.run('node', [
        '-e',
        r'''
const dto = require('./backend/src/services/bookRecapHttpContract');
const value = JSON.parse(process.argv[1]);
for (const req of value.requests) {
  const action = req.path.split('/').pop();
  const schema = req.method === 'DELETE' || action === 'cancel' ? dto.empty :
    action === 'follow-ups' ? dto.followUp : dto[action];
  if (!schema) throw Error('Unsupported contract');
  schema.parse(req.body);
}
dto.response.parse(value.response);
process.stdout.write(String(value.requests.length));
''',
        jsonEncode(payload),
      ], workingDirectory: root);
      expect(check.exitCode, 0, reason: check.stderr.toString());
      expect(int.parse(check.stdout.toString()), 7);
    },
  );
  test(
    'all follow-ups cannot silently omit locally acknowledged identities',
    () async {
      await follow();
      final proof = await inspect(selection(RecapFollowScope.all));
      expect(
        () => proof.checkResolved([
          {'entry_id': remote, 'follow_up_ids': []},
        ]),
        code('RECAP_SCOPE_CHANGED'),
      );
      proof.checkResolved([
        {
          'entry_id': remote,
          'follow_up_ids': [followId, remote2],
        },
      ]);
      expect(proof.sources.single.containsKey('follow_up_ids'), false);
    },
  );
  test(
    'real loopback HTTP success, no redirect following, timeout and abort',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var count = 0, mode = 'ok';
        final held = <HttpResponse>[];
        server.listen((r) async {
          count++;
          expect(r.headers.value('authorization'), 'Bearer synthetic-token');
          if (mode == 'hold') {
            held.add(r.response);
            return;
          }
          if (mode == 'redirect') {
            r.response.statusCode = 302;
            r.response.headers.set('location', '/not-allowed');
            r.response.write('{}');
          } else {
            r.response.write(jsonEncode(current));
          }
          await r.response.close();
        });
        final client = BookRecapClientApi(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}/recaps'),
          enabled: true,
          loopbackTest: true,
          timeout: const Duration(milliseconds: 200),
          clientFactory: http.Client.new,
          tokenProvider: (_) => 'synthetic-token',
        );
        try {
          expect((await client.send(session, 'GET', recap))['id'], recap);
          mode = 'redirect';
          await expectLater(
            client.send(session, 'GET', recap),
            code('NETWORK'),
          );
          expect(count, 2);
          mode = 'hold';
          await expectLater(
            client.send(session, 'GET', recap),
            code('TIMEOUT'),
          );
          expect(count, 3);
          final abort = RecapRequestAbort();
          final task = client.send(session, 'GET', recap, abort: abort);
          final assertion = expectLater(task, code('CANCELLED'));
          while (count < 4) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          abort.cancel();
          await assertion;
          expect(count, 4);
        } finally {
          for (final response in held) {
            unawaited(response.close().catchError((_) {}));
          }
          await server.close(force: true);
        }
      }, _LoopbackHttp());
    },
  );
}
