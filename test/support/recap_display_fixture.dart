import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_reader/services/auth_session_scope.dart';
import 'package:ai_reader/services/database_service.dart';
import 'package:ai_reader/services/book_recap_client_api.dart';
import 'package:ai_reader/services/book_recap_client_contract.dart';
import 'package:ai_reader/services/book_recap_local_guard.dart';
import 'package:ai_reader/services/reading_source_changes.dart';
import 'package:ai_reader/providers/book_recap_controller.dart';
import '../services/book_recap_client_test.dart' as base;

/// Synthetic HTTP state, not a substitute for the separate real PG contract tests.
class RecapDisplayFixture {
  late Database db;
  late Directory directory;
  late AuthSessionScope session;
  final online = ValueNotifier(true);
  late BookRecapClientApi api;
  late BookRecapLocalGuard guard;
  Map<String, dynamic> current = base.response();
  final requests = <http.Request>[];
  final turns = <Map<String, dynamic>>[];
  final seen = <String>{};
  String policy = 'isolated-v1';
  int windowMs = 20000;
  Duration elapsed = Duration.zero;
  bool deleted = false, malformed = false, failNext = false;
  bool emptyResult = false, paginated = false;
  Completer<void>? hold;
  String? heldAction;
  void Function(Map<String, dynamic>)? alterGrant;
  static final evidenceId = 'e-${'b' * 64}';
  final controllers = <BookRecapController>[];

  Future<void> init() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AuthSessionScope.beginTransition();
    AuthSessionScope.publish(base.owner, 'synthetic-token');
    session = AuthSessionScope.capture();
    directory = await Directory.systemTemp.createTemp('zhidu-recap-b24b2-');
    db = await DatabaseService.openForTesting('${directory.path}/synthetic.db');
    await db.insert('user_entries', {
      'id': 'local-a',
      'user_id': base.owner,
      'book_id': 'book-a',
      'book_title': '条件与证据',
      'bmob_id': base.remote,
      'source': 'ai_question',
      'original_text': '只有通过检验，结论才可能成立。这不表示检验能够保证结论。',
      'user_input': '必要条件能保证结果吗？',
      'ai_explanation': '不能把必要条件当成充分条件。',
      'metadata_json': jsonEncode({
        'origin': 'reader',
        'reading_ai_context': {
          'scope': 'selection',
          'selectedText': '只有通过检验，结论才可能成立。',
        },
      }),
      'created_at': '2026-01-01T00:00:00Z',
    });
    guard = BookRecapLocalGuard(() async => db);
    api = BookRecapClientApi(
      baseUri: Uri.parse('http://127.0.0.1/recaps'),
      enabled: true,
      loopbackTest: true,
      tokenProvider: (_) => 'synthetic-token',
      clientFactory: () => MockClient(respond),
    );
    resetResult();
  }

  void resetResult() {
    current['evidence_summary'] = {'transmitted': 1, 'excluded_unverified': 0};
    if (current['result'] == null) return;
    current['result'] = {
      ...base.result(),
      'knowledge': [
        {
          'id': 'k1',
          'kind': 'concept',
          'title': '必要不等于充分',
          'summary': '检验是必要条件，不能据此断言结论必然成立。',
          'basis': 'source_supported',
          'evidenceRefs': [evidenceId],
          'quotes': [],
        },
      ],
      'myThinking': [
        {
          'id': 'm1',
          'title': '你的问题',
          'summary': '你曾询问必要条件是否足以保证结果。',
          'basis': 'user_explicit',
          'evidenceRefs': [evidenceId],
          'quotes': [],
        },
      ],
      'nextQuestions': [
        {
          'id': 'n1',
          'title': '还需要什么证据？',
          'summary': '什么额外条件才能支持更强的结论？',
          'basis': 'ai_inference',
          'evidenceRefs': [evidenceId],
          'quotes': [],
        },
      ],
    };
    if (emptyResult) {
      for (final key in [
        'knowledge',
        'relations',
        'myThinking',
        'openQuestions',
        'nextQuestions',
      ]) {
        current['result'][key] = [];
      }
    }
  }

  Map<String, dynamic> grant() {
    final now = DateTime.now().toUtc();
    final g = <String, dynamic>{
      'protocol_version': 1,
      'policy_version': policy,
      'recap_id': current['id'],
      'book_id': current['book_id'],
      'revision': current['revision'],
      'source_fingerprint': base.fingerprint,
      'checked_at': now.toIso8601String(),
      'expires_at': now.add(Duration(milliseconds: windowMs)).toIso8601String(),
      'max_age_ms': windowMs,
      'local_pending_verified': false,
      'requires_online_on_open': true,
    };
    alterGrant?.call(g);
    return g;
  }

  Map<String, dynamic> get catalog => {
    'id': evidenceId,
    'entry_id': base.remote,
    'follow_up_id': null,
    'kind': 'book_excerpt',
    'provenance': 'reader_context',
  };
  Map<String, dynamic> get scope => {...current}..remove('result');
  http.Response ok(Object value) => http.Response(
    jsonEncode(value),
    200,
    headers: {'content-type': 'application/json'},
  );
  Future<http.Response> respond(http.Request req) async {
    requests.add(req);
    final action = req.url.path.split('/').last;
    if (action == heldAction) await hold?.future;
    if (failNext) {
      failNext = false;
      throw http.ClientException('Synthetic disconnect');
    }
    if (malformed) return ok({'unexpected': true});
    final body = req.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(req.body) as Map<String, dynamic>;
    if (action == 'history') {
      return ok({
        'items': deleted
            ? []
            : [
                {
                  'id': current['id'],
                  'book_id': 'book-a',
                  'revision': current['revision'],
                  'state': current['state'],
                  'is_saved': current['is_saved'],
                  'created_at': '2026-01-01T00:00:00.000000Z',
                  'updated_at': '2026-01-01T00:00:00.000Z',
                  'expires_at': null,
                  'availability': 'requires_online_verification',
                },
              ],
        'next_cursor': paginated && body['cursor'] == null
            ? 'synthetic-next-page'
            : null,
        'contains_private_body': false,
        'snapshot_consistent': false,
      });
    }
    if (req.method == 'DELETE') {
      deleted = true;
      return http.Response('', 204);
    }
    if (action == 'cancel') {
      current = base.response(id: current['id'], state: 'cancelled');
      return http.Response('', 204);
    }
    if (deleted) {
      return http.Response(
        jsonEncode({'error_code': 'RECAP_UNAVAILABLE'}),
        410,
      );
    }
    if (action == 'scope') {
      return ok({
        ...scope,
        'evidence_catalog': [catalog],
        'requires_local_confirmation': true,
      });
    }
    if (action == 'view') return ok({'recap': current, 'display': grant()});
    if (action == 'validate') return ok({'display': grant()});
    if (action == 'evidence') {
      return ok({
        'evidence': [
          {
            ...catalog,
            'text': '只有通过检验，结论才可能成立。',
            'location': {
              'status': 'fragment_only',
              'exact': false,
              'chapter_index': '1',
              'chapter_title': '条件',
            },
          },
        ],
        'display': grant(),
      });
    }
    if (action == 'prepare') {
      current = base.response(
        id: body['recap_id'],
        state: 'prepared',
        revision: '1',
      );
      return ok(current);
    }
    if (action == 'generate') {
      final replay = !seen.add(body['request_id']);
      current = base.response(id: current['id']);
      resetResult();
      return ok({'status': 'succeeded', 'replay': replay});
    }
    if (action == 'save') {
      current = {
        ...current,
        'is_saved': true,
        'revision': (int.parse(current['revision']) + 1).toString(),
      };
      return ok(current);
    }
    if (action == 'feedback') return ok({'id': base.feedbackId});
    if (action == 'follow-ups') {
      if (req.method == 'POST') {
        final replay = !seen.add(body['request_id']);
        if (!replay) {
          turns.add({
            'turn': turns.length + 1,
            'question': body['question'],
            'answer': {
              'schemaVersion': 1,
              'snapshotFingerprint': base.fingerprint,
              'parts': [
                {
                  'text': '目前证据只说明必要性，并未保证结果。',
                  'basis': 'source_supported',
                  'evidenceRefs': [evidenceId],
                  'quotes': [],
                },
              ],
            },
          });
          current = {
            ...current,
            'revision': (int.parse(current['revision']) + 1).toString(),
          };
        }
        return ok({'status': 'succeeded', 'replay': replay});
      }
      return ok({
        'revision': current['revision'],
        'source_fingerprint': base.fingerprint,
        'coverage': base.coverage(),
        'local_pending_verified': false,
        'turns': turns,
      });
    }
    return ok(current);
  }

  BookRecapController controller({
    Set<String> policies = const {'isolated-v1'},
  }) {
    final c = BookRecapController(
      api: api,
      localGuard: guard,
      bookId: 'book-a',
      localChanges: ReadingSourceChanges.changes,
      displayLifetime: const Duration(seconds: 20),
      approvedDisplayPolicies: policies,
      monotonic: () => elapsed,
    );
    controllers.add(c);
    return c;
  }

  List<RecapLocalSelection> get selection => [RecapLocalSelection('local-a')];
  Future<BookRecapController> open() async {
    final c = controller();
    await c.open(current['id'], selection);
    return c;
  }

  Future<void> dispose() async {
    if (hold != null && !hold!.isCompleted) hold!.complete();
    for (final c in controllers) {
      c.dispose();
    }
    await db.close();
    online.dispose();
    final path = directory.absolute.path;
    if (!path.startsWith(Directory.systemTemp.absolute.path) ||
        !directory.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('zhidu-recap-b24b2-')) {
      throw StateError('Unsafe synthetic path');
    }
    await directory.delete(recursive: true);
  }
}
