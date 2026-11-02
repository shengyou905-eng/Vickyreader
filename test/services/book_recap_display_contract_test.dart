import 'dart:async';
import 'dart:convert';

import 'package:ai_reader/services/auth_session_scope.dart';
import 'package:ai_reader/services/book_recap_client_api.dart';
import 'package:ai_reader/services/book_recap_client_contract.dart';
import 'package:ai_reader/services/book_recap_display_contract.dart';
import 'package:ai_reader/services/book_recap_display_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _id = '11111111-1111-4111-8111-111111111111';
const _entry = '22222222-2222-4222-8222-222222222222';
const _follow = '33333333-3333-4333-8333-333333333333';
const _other = '44444444-4444-4444-8444-444444444444';
final _digest = 'a' * 64;
final _evidenceId = 'e-${'b' * 64}';
final _checked = DateTime.utc(2026, 10, 28, 8);

Map<String, dynamic> _catalog() => {
  'id': _evidenceId,
  'entry_id': _entry,
  'follow_up_id': null,
  'kind': 'book_excerpt',
  'provenance': 'reader_context',
};
Map<String, dynamic> _scope() => {
  'id': _id,
  'book_id': 'synthetic-book',
  'revision': '2',
  'state': 'ready',
  'is_saved': false,
  'source_fingerprint': _digest,
  'coverage': {
    'basis': 'reading_traces',
    'fullBook': false,
    'sourceCompleteness': 'server_selected_records',
    'availableEntries': 1,
    'includedEntries': 1,
    'includedFollowUps': 1,
    'quarantinedEntries': 0,
    'selectionApplied': true,
  },
  'sources': [
    {
      'entry_id': _entry,
      'follow_up_ids': [_follow],
    },
  ],
  'evidence_summary': {'transmitted': 1, 'excluded_unverified': 0},
  'scope_basis': 'selected_cloud_records_only',
  'local_pending_verified': false,
  'evidence_catalog': [_catalog()],
  'requires_local_confirmation': true,
};
Map<String, dynamic> _metadata() => _scope()
  ..remove('evidence_catalog')
  ..remove('requires_local_confirmation');
RecapHeader _header() => RecapHeader.fromScope(_metadata());
Map<String, dynamic> _result() => {
  'schemaVersion': 1,
  'snapshotFingerprint': _digest,
  'knowledge': [
    {
      'id': 'k1',
      'title': 'Synthetic concept',
      'summary': 'Synthetic explanation',
      'basis': 'source_supported',
      'evidenceRefs': [_evidenceId],
      'quotes': [],
      'kind': 'concept',
    },
  ],
  'relations': [],
  'myThinking': [],
  'openQuestions': [],
  'nextQuestions': [],
};
Map<String, dynamic> _grant({int age = 2000}) => {
  'protocol_version': 1,
  'policy_version': 'synthetic-v1',
  'recap_id': _id,
  'book_id': 'synthetic-book',
  'revision': '2',
  'source_fingerprint': _digest,
  'checked_at': _checked.toIso8601String(),
  'expires_at': _checked.add(Duration(milliseconds: age)).toIso8601String(),
  'max_age_ms': age,
  'local_pending_verified': false,
  'requires_online_on_open': true,
};
Map<String, dynamic> _historyItem({
  String state = 'ready',
  bool saved = false,
}) => {
  'id': _id,
  'book_id': 'synthetic-book',
  'revision': '2',
  'state': state,
  'is_saved': saved,
  'created_at': '2026-10-28T07:59:59.123456Z',
  'updated_at': _checked.toIso8601String(),
  'expires_at': null,
  'availability': state == 'ready'
      ? 'requires_online_verification'
      : 'unavailable',
};
Map<String, dynamic> _page({String? cursor, bool saved = false}) => {
  'items': [_historyItem(saved: saved)],
  'next_cursor': cursor,
  'contains_private_body': false,
  'snapshot_consistent': false,
};
Map<String, dynamic> _evidence() => {
  'evidence': [
    {
      ..._catalog(),
      'text': 'Synthetic authorized fragment',
      'location': {
        'status': 'fragment_only',
        'exact': false,
        'chapter_index': '1',
        'chapter_title': 'Synthetic chapter',
      },
    },
  ],
  'display': _grant(),
};
Matcher _reject([String? code]) => throwsA(
  isA<RecapClientException>().having(
    (e) => e.code,
    'safe error code',
    code == null ? isA<String>() : equals(code),
  ),
);

Duration _remaining(
  RecapDisplayGrant grant, {
  RecapHeader? header,
  Set<String> policies = const {'synthetic-v1'},
  DateTime? now,
  Duration elapsed = const Duration(milliseconds: 300),
  Duration limit = const Duration(seconds: 10),
  DateTime? started,
}) => grant.remaining(
  header: header ?? _header(),
  approvedPolicies: policies,
  now: now ?? _checked.add(const Duration(milliseconds: 100)),
  elapsed: elapsed,
  clientLimit: limit,
  requestStartedAt: started,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('display grant', () {
    test(
      'deducts full RTT and final local verification from server budget',
      () {
        expect(
          _remaining(RecapDisplayGrant.parse(_grant())),
          const Duration(milliseconds: 1700),
        );
      },
    );
    test('local policy is also measured from request dispatch', () {
      expect(
        _remaining(
          RecapDisplayGrant.parse(_grant()),
          limit: const Duration(milliseconds: 400),
        ),
        const Duration(milliseconds: 100),
      );
    });
    test('wall deadline can only shorten the monotonic budget', () {
      expect(
        _remaining(
          RecapDisplayGrant.parse(_grant()),
          now: _checked.add(const Duration(milliseconds: 700)),
        ),
        const Duration(milliseconds: 1300),
      );
    });
    test('expired and exhausted local limits return zero', () {
      expect(
        _remaining(
          RecapDisplayGrant.parse(_grant()),
          now: _checked.add(const Duration(seconds: 2)),
          elapsed: const Duration(seconds: 2),
        ),
        Duration.zero,
      );
      expect(
        _remaining(
          RecapDisplayGrant.parse(_grant()),
          limit: const Duration(milliseconds: 200),
        ),
        Duration.zero,
      );
    });
    test('policy approval is explicit and defaults to no permission', () {
      expect(
        () => _remaining(RecapDisplayGrant.parse(_grant()), policies: {}),
        _reject('RECAP_DISPLAY_POLICY_REQUIRED'),
      );
      expect(
        () => _remaining(
          RecapDisplayGrant.parse(_grant()),
          policies: {'another-v1'},
        ),
        _reject('RECAP_DISPLAY_POLICY_REQUIRED'),
      );
    });
    for (final entry in <String, Object>{
      'id': _other,
      'book_id': 'another-book',
      'revision': '3',
      'source_fingerprint': 'c' * 64,
    }.entries) {
      test('binds header ${entry.key}', () {
        final header = RecapHeader.fromScope(
          _metadata()..[entry.key] = entry.value,
        );
        expect(
          () => _remaining(RecapDisplayGrant.parse(_grant()), header: header),
          _reject('RECAP_REVISION_CONFLICT'),
        );
      });
    }
    test('all grant keys required and unknown keys rejected', () {
      for (final key in _grant().keys) {
        expect(() => RecapDisplayGrant.parse(_grant()..remove(key)), _reject());
      }
      expect(
        () => RecapDisplayGrant.parse(_grant()..['result'] = 'private'),
        _reject(),
      );
    });
    for (final entry in <String, Object?>{
      'protocol_version': 1.0,
      'policy_version': 'bad policy',
      'recap_id': 'local-id',
      'revision': 2,
      'source_fingerprint': 'A' * 64,
      'max_age_ms': 2000.0,
      'local_pending_verified': true,
      'requires_online_on_open': false,
      'book_id': '',
    }.entries) {
      test('rejects invalid grant ${entry.key}', () {
        expect(
          () => RecapDisplayGrant.parse(_grant()..[entry.key] = entry.value),
          _reject(),
        );
      });
    }
    test('window is positive, coherent, bounded by 120 seconds', () {
      expect(RecapDisplayGrant.parse(_grant(age: 120000)).maxAgeMs, 120000);
      for (final age in [0, -1, 120001]) {
        expect(() => RecapDisplayGrant.parse(_grant(age: age)), _reject());
      }
      expect(
        () => RecapDisplayGrant.parse(_grant()..['max_age_ms'] = 1999),
        _reject(),
      );
    });
    test('rejects invalid calendar dates and non-UTC timestamps', () {
      for (final stamp in [
        '2026-02-30T08:00:00Z',
        '2026-10-28T24:00:00Z',
        '2026-10-28T08:00:60Z',
        '2026-10-28T08:00:00+00:00',
        '2026-10-28',
        'bad',
      ]) {
        expect(
          () => RecapDisplayGrant.parse(_grant()..['checked_at'] = stamp),
          _reject(),
        );
      }
    });
    test('future server time, negative elapsed, zero policy fail closed', () {
      expect(
        () => _remaining(
          RecapDisplayGrant.parse(_grant()),
          now: _checked.subtract(const Duration(milliseconds: 1)),
        ),
        _reject('RECAP_DISPLAY_CLOCK_INVALID'),
      );
      expect(
        () => _remaining(
          RecapDisplayGrant.parse(_grant()),
          elapsed: const Duration(microseconds: -1),
        ),
        _reject(),
      );
      expect(
        () =>
            _remaining(RecapDisplayGrant.parse(_grant()), limit: Duration.zero),
        _reject(),
      );
    });
    test('large first-observation clock skew fails closed', () {
      expect(
        () => _remaining(
          RecapDisplayGrant.parse(_grant(age: 10000)),
          now: _checked.add(const Duration(seconds: 5)),
        ),
        _reject('RECAP_DISPLAY_CLOCK_INVALID'),
      );
    });
    test(
      'request wall baseline rejects first-call rollback after checkedAt',
      () {
        expect(
          () => _remaining(
            RecapDisplayGrant.parse(_grant(age: 10000)),
            now: _checked.add(const Duration(seconds: 1)),
            elapsed: const Duration(seconds: 5),
            started: _checked,
          ),
          _reject('RECAP_DISPLAY_CLOCK_INVALID'),
        );
      },
    );
    test(
      'observed wall rollback or monotonic rollback permanently rejects grant',
      () {
        final grant = RecapDisplayGrant.parse(_grant());
        _remaining(grant);
        expect(
          () => _remaining(
            grant,
            now: _checked,
            elapsed: const Duration(milliseconds: 400),
          ),
          _reject('RECAP_DISPLAY_CLOCK_INVALID'),
        );
        expect(() => _remaining(grant), _reject('RECAP_DISPLAY_CLOCK_INVALID'));
        final second = RecapDisplayGrant.parse(_grant());
        _remaining(second);
        expect(
          () => _remaining(second, elapsed: const Duration(milliseconds: 200)),
          _reject(),
        );
      },
    );
  });

  group('body-free scope and history', () {
    test(
      'scope recovers ready metadata without result and detaches inputs',
      () {
        final input = _scope();
        final scope = RecapRecoveredScope.parse(input);
        expect(scope.header.state, RecapServerState.ready);
        expect(scope.requiresLocalConfirmation, isTrue);
        expect(scope.evidenceCatalog.single.id, _evidenceId);
        (input['sources'] as List).clear();
        scope.header.sources.clear();
        expect(scope.header.sources, hasLength(1));
        expect(() => scope.evidenceCatalog.clear(), throwsUnsupportedError);
      },
    );
    test('old ready parser still requires real result', () {
      expect(() => RecapHeader.parse(_metadata()), _reject());
      expect(
        () => RecapHeader.parse(_metadata()..['result'] = null),
        _reject(),
      );
      expect(
        RecapHeader.parse(_metadata()..['result'] = _result()).state,
        RecapServerState.ready,
      );
    });
    test('scope rejects result even when null or empty', () {
      for (final body in [null, <String, dynamic>{}, _result()]) {
        expect(
          () => RecapRecoveredScope.parse(_scope()..['result'] = body),
          _reject(),
        );
        expect(
          () => RecapHeader.fromScope(_metadata()..['result'] = body),
          _reject(),
        );
      }
    });
    test('scope preserves strict metadata validation', () {
      for (final entry in <String, Object?>{
        'state': 'prepared',
        'requires_local_confirmation': false,
        'local_pending_verified': true,
        'source_fingerprint': 'wrong',
        'book_id': null,
        'scope_basis': 'full_book',
      }.entries) {
        expect(
          () => RecapRecoveredScope.parse(_scope()..[entry.key] = entry.value),
          _reject(),
        );
      }
      final input = _scope();
      (input['coverage'] as Map)['includedEntries'] = 2;
      expect(() => RecapRecoveredScope.parse(input), _reject());
    });
    test(
      'scope catalog IDs are unique, counted, and within selected sources',
      () {
        final duplicate = _scope()
          ..['evidence_catalog'] = [_catalog(), _catalog()];
        expect(() => RecapRecoveredScope.parse(duplicate), _reject());
        final wrongEntry = _scope()
          ..['evidence_catalog'] = [_catalog()..['entry_id'] = _other];
        expect(() => RecapRecoveredScope.parse(wrongEntry), _reject());
        final wrongFollow = _scope()
          ..['evidence_catalog'] = [_catalog()..['follow_up_id'] = _other];
        expect(() => RecapRecoveredScope.parse(wrongFollow), _reject());
        expect(
          () => RecapRecoveredScope.parse(_scope()..['evidence_catalog'] = []),
          _reject(),
        );
      },
    );
    test(
      'catalog only accepts actual evidence IDs, UUID sources, and enums',
      () {
        for (final entry in <String, Object?>{
          'id': 'e-1',
          'entry_id': 'local-entry',
          'follow_up_id': 'local-follow',
          'kind': 'unverified_excerpt',
          'provenance': 'current_document',
          'text': 'private',
        }.entries) {
          expect(
            () => RecapEvidenceCatalogItem.parse(
              _catalog()..[entry.key] = entry.value,
            ),
            _reject(),
          );
        }
        for (final kind in RecapEvidenceKind.values) {
          expect(
            RecapEvidenceCatalogItem.parse(
              _catalog()..['kind'] = kind.name,
            ).kind,
            kind,
          );
        }
        for (final source in RecapEvidenceProvenance.values) {
          expect(
            RecapEvidenceCatalogItem.parse(
              _catalog()..['provenance'] = source.name,
            ).provenance,
            source,
          );
        }
      },
    );
    test('history accepts all nine states without inventing saved state', () {
      for (final state in RecapHistoryState.values) {
        final item = RecapHistoryItem.parse(_historyItem(state: state.name));
        expect(item.state, state);
        expect(item.createdAt, '2026-10-28T07:59:59.123456Z');
      }
      expect(
        () => RecapHistoryItem.parse(_historyItem(state: 'saved')),
        _reject(),
      );
      final item = RecapHistoryItem.parse(
        _historyItem(state: 'deleted')..['book_id'] = null,
      );
      expect(item.bookId, isNull);
    });
    test('history is strictly body-free with independent saved flag', () {
      final page = RecapHistoryPage.parse(_page(saved: true, cursor: 'opaque'));
      expect(page.items.single.isSaved, isTrue);
      expect(page.nextCursor, 'opaque');
      expect(page.containsPrivateBody, isFalse);
      expect(page.snapshotConsistent, isFalse);
      expect(() => page.items.clear(), throwsUnsupportedError);
      for (final key in [
        'result',
        'title',
        'question',
        'snapshot',
        'user_id',
      ]) {
        expect(
          () => RecapHistoryItem.parse(_historyItem()..[key] = 'private'),
          _reject(),
        );
      }
      expect(
        () => RecapHistoryItem.parse(
          _historyItem()..['availability'] = 'unavailable',
        ),
        _reject(),
      );
    });
    test(
      'history rejects duplicate IDs, oversized pages, false privacy claims',
      () {
        expect(
          () => RecapHistoryPage.parse(
            _page()..['items'] = [_historyItem(), _historyItem()],
          ),
          _reject(),
        );
        expect(
          () => RecapHistoryPage.parse(
            _page()..['items'] = List.generate(51, (_) => _historyItem()),
          ),
          _reject(),
        );
        expect(
          () =>
              RecapHistoryPage.parse(_page()..['contains_private_body'] = true),
          _reject(),
        );
        expect(
          () => RecapHistoryPage.parse(_page()..['snapshot_consistent'] = true),
          _reject(),
        );
        expect(
          () => RecapHistoryPage.parse(_page()..remove('next_cursor')),
          _reject(),
        );
      },
    );
  });

  group('display wrappers', () {
    test(
      'evidence default parser validates real contract without caller options',
      () {
        final dto = RecapEvidenceResponse.parse(_evidence());
        expect(dto.evidence.single.location.exact, isFalse);
        expect(dto.evidence.single.text, 'Synthetic authorized fragment');
        expect(dto.evidence.single.kind, RecapEvidenceKind.book_excerpt);
        expect(() => dto.evidence.clear(), throwsUnsupportedError);
      },
    );
    test('evidence can bind header, requested set and recovered catalog', () {
      final dto = RecapEvidenceResponse.parse(
        _evidence(),
        header: _header(),
        requestedIds: [_evidenceId],
        scope: RecapRecoveredScope.parse(_scope()),
      );
      expect(dto.evidence.single.entryId, _entry);
      expect(
        () => RecapEvidenceResponse.parse(
          _evidence(),
          requestedIds: ['e-${'c' * 64}'],
        ),
        _reject(),
      );
      expect(
        () => RecapEvidenceResponse.parse(
          _evidence(),
          requestedIds: [_evidenceId, _evidenceId],
        ),
        _reject(),
      );
      final input = _evidence();
      (input['evidence'] as List).single['entry_id'] = _other;
      expect(
        () => RecapEvidenceResponse.parse(input, header: _header()),
        _reject(),
      );
      expect(
        () => RecapEvidenceResponse.parse(
          input,
          scope: RecapRecoveredScope.parse(_scope()),
        ),
        _reject(),
      );
    });
    test(
      'evidence rejects duplication, extra body fields and invalid source',
      () {
        final duplicate = _evidence();
        (duplicate['evidence'] as List).add(
          (duplicate['evidence'] as List).single,
        );
        expect(() => RecapEvidenceResponse.parse(duplicate), _reject());
        for (final entry in <String, Object?>{
          'id': 'fake',
          'entry_id': 'local',
          'kind': 'author',
          'provenance': 'business_record',
          'text': '',
          'sourceField': 'private-internal-field',
        }.entries) {
          final input = _evidence();
          (input['evidence'] as List).single[entry.key] = entry.value;
          expect(() => RecapEvidenceResponse.parse(input), _reject());
        }
      },
    );
    test('location cannot be upgraded to exact or gain file paths', () {
      for (final entry in <String, Object?>{
        'status': 'exact',
        'exact': true,
        'start': 0,
        'file_path': '/private',
        'chapter_index': 1,
        'chapter_title': 'x' * 1001,
      }.entries) {
        final input = _evidence();
        (input['evidence'] as List).single['location'][entry.key] = entry.value;
        expect(() => RecapEvidenceResponse.parse(input), _reject());
      }
    });
    test('evidence count and UTF-8 budget are bounded', () {
      final input = _evidence();
      final item = (input['evidence'] as List).single as Map<String, dynamic>;
      input['evidence'] = List.generate(25, (_) => item);
      expect(() => RecapEvidenceResponse.parse(input), _reject());
      final oversized = _evidence();
      (oversized['evidence'] as List).single['text'] = '\u4e2d' * 100000;
      expect(() => RecapEvidenceResponse.parse(oversized), _reject());
    });
    test(
      'view binds nested ready header and grant; result copy is detached',
      () {
        final input = {
          'recap': _metadata()..['result'] = _result(),
          'display': _grant(),
        };
        final dto = RecapViewResponse.parse(input, expectedHeader: _header());
        dto.result.clear();
        expect(dto.result['knowledge'], hasLength(1));
        (input['display'] as Map)['revision'] = '3';
        expect(
          () => RecapViewResponse.parse(input),
          _reject('RECAP_REVISION_CONFLICT'),
        );
      },
    );
    test('validation wrapper accepts no hidden body and can bind header', () {
      expect(
        RecapValidationResponse.parse({
          'display': _grant(),
        }, header: _header()).display.revision,
        '2',
      );
      expect(
        () => RecapValidationResponse.parse({
          'display': _grant(),
          'result': _result(),
        }),
        _reject(),
      );
    });
  });

  group('session-bound repository MockHTTP', () {
    late AuthSessionScope session;
    late BookRecapDisplayRepository repository;
    late Future<http.Response> Function(http.Request) handler;
    final requests = <http.Request>[];
    setUp(() {
      AuthSessionScope.beginTransition();
      AuthSessionScope.publish('synthetic-owner', 'synthetic-token');
      session = AuthSessionScope.capture();
      requests.clear();
      handler = (_) async => http.Response(jsonEncode(_page()), 200);
      repository = BookRecapDisplayRepository(
        session: session,
        api: BookRecapClientApi(
          baseUri: Uri.parse('http://127.0.0.1/synthetic-recaps'),
          enabled: true,
          loopbackTest: true,
          tokenProvider: (_) => 'synthetic-token',
          clientFactory: () => MockClient((request) async {
            requests.add(request);
            return handler(request);
          }),
        ),
      );
    });
    tearDown(() {
      AuthSessionScope.beginTransition();
      AuthSessionScope.publish(null, null);
    });
    test(
      'history sends strict POST pagination and returns typed body-free page',
      () async {
        handler = (_) async => http.Response(
          jsonEncode(_page(saved: true, cursor: 'opaque-next')),
          200,
        );
        final page = await repository.history(
          limit: 10,
          filter: RecapHistoryFilter.saved,
          cursor: 'opaque-before',
        );
        expect(page, isA<RecapHistoryPage>());
        expect(page.nextCursor, 'opaque-next');
        expect(requests.single.method, 'POST');
        expect(requests.single.url.path, '/synthetic-recaps/display/history');
        expect(jsonDecode(requests.single.body), {
          'limit': 10,
          'filter': 'saved',
          'cursor': 'opaque-before',
        });
        expect(requests.single.headers['Cache-Control'], 'no-store');
      },
    );
    test(
      'defaults are request-only and invalid pagination makes no HTTP request',
      () async {
        await repository.history();
        expect(jsonDecode(requests.single.body), {
          'limit': 20,
          'filter': 'all',
        });
        requests.clear();
        for (final limit in [0, 51]) {
          expect(
            () => repository.history(limit: limit),
            _reject('INVALID_REQUEST'),
          );
        }
        expect(
          () => repository.history(cursor: ''),
          _reject('INVALID_REQUEST'),
        );
        expect(
          () => repository.history(cursor: 'x' * 2049),
          _reject('INVALID_REQUEST'),
        );
        expect(requests, isEmpty);
      },
    );
    test('history does not accept a response from another filter', () async {
      await expectLater(
        repository.history(filter: RecapHistoryFilter.saved),
        _reject(),
      );
    });
    test(
      'scope uses empty POST and verifies returned recap identity',
      () async {
        handler = (_) async => http.Response(jsonEncode(_scope()), 200);
        final scope = await repository.scope(_id);
        expect(scope.header.id, _id);
        expect(
          requests.single.url.path,
          '/synthetic-recaps/display/$_id/scope',
        );
        expect(jsonDecode(requests.single.body), isEmpty);
        handler = (_) async =>
            http.Response(jsonEncode(_scope()..['id'] = _other), 200);
        await expectLater(
          repository.scope(_id),
          _reject('RECAP_REVISION_CONFLICT'),
        );
      },
    );
    test(
      'delete uses existing DELETE without local book or source lookups',
      () async {
        handler = (_) async => http.Response('', 204);
        await repository.delete(_id);
        expect(requests.single.method, 'DELETE');
        expect(requests.single.url.path, '/synthetic-recaps/$_id');
        expect(requests.single.body, isEmpty);
      },
    );
    test('invalid recap IDs reject before HTTP', () {
      expect(() => repository.scope('local-id'), _reject('INVALID_ID'));
      expect(() => repository.delete('../history'), _reject('INVALID_ID'));
      expect(requests, isEmpty);
    });
    test('stale session rejects before dispatch', () async {
      AuthSessionScope.publish('other-owner', 'other-token');
      await expectLater(repository.history(), _reject('AUTH_CHANGED'));
      expect(requests, isEmpty);
    });
    for (final action in ['history', 'scope', 'delete']) {
      test('late $action response rejects A-B-A epoch transition', () async {
        final entered = Completer<void>();
        final response = Completer<http.Response>();
        handler = (_) {
          entered.complete();
          return response.future;
        };
        final operation = switch (action) {
          'history' => repository.history(),
          'scope' => repository.scope(_id),
          _ => repository.delete(_id),
        };
        final assertion = expectLater(operation, _reject('AUTH_CHANGED'));
        await entered.future;
        AuthSessionScope.publish('other-owner', 'other-token');
        AuthSessionScope.publish('synthetic-owner', 'synthetic-token');
        response.complete(
          action == 'delete'
              ? http.Response('', 204)
              : http.Response(
                  jsonEncode(action == 'scope' ? _scope() : _page()),
                  200,
                ),
        );
        await assertion;
      });
    }
    test('abort before request, HTTP errors, and no retry', () async {
      final abort = RecapRequestAbort()..cancel();
      await expectLater(repository.history(abort: abort), _reject('CANCELLED'));
      expect(requests, isEmpty);
      handler = (_) async =>
          http.Response(jsonEncode({'error_code': 'RECAP_UNAVAILABLE'}), 410);
      await expectLater(repository.scope(_id), _reject('RECAP_UNAVAILABLE'));
      expect(requests, hasLength(1));
    });
    test('unconfigured API remains fail closed', () async {
      final api = BookRecapClientApi(
        baseUri: Uri.parse('http://127.0.0.1/synthetic'),
        loopbackTest: true,
        tokenProvider: (_) => 'token',
        clientFactory: () => throw StateError('Must not create transport'),
      );
      final disabled = BookRecapDisplayRepository(api: api, session: session);
      await expectLater(disabled.history(), _reject('NOT_CONFIGURED'));
    });
  });
}
