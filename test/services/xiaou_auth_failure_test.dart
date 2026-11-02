import 'dart:convert';
import 'dart:io';

import 'package:ai_reader/services/api_request_exception.dart';
import 'package:ai_reader/services/bmob_api.dart';
import 'package:ai_reader/services/book_service.dart';
import 'package:ai_reader/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _RealHttpOverrides extends HttpOverrides {}

// Redirect every request to a synthetic loopback server, never the configured API.
class _LoopbackClient implements HttpClient {
  final HttpClient client;
  final int port;

  _LoopbackClient(this.client, this.port);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => client.openUrl(
    method,
    url.replace(scheme: 'http', host: '127.0.0.1', port: port),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late HttpServer server;
  late HttpClient client;
  late Directory dir;
  late Database db;
  var status = 401;
  final paths = <String>[];
  const owner = 'synthetic-auth-failure-user';

  Future<T> withServer<T>(Future<T> Function() action) =>
      HttpOverrides.runZoned(
        action,
        createHttpClient: (_) => _LoopbackClient(client, server.port),
      );

  setUpAll(() async {
    client = HttpOverrides.runWithHttpOverrides(
      () => HttpClient(),
      _RealHttpOverrides(),
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      paths.add(request.uri.path);
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        status == 200
            ? '{"entries":[],"insight":{}}'
            : '{"error":"synthetic-response-must-not-be-retained"}',
      );
      await request.response.close();
    });
    dir = await Directory.systemTemp.createTemp('xiaou-auth-test-');
    db = await DatabaseService.openForTesting('${dir.path}/test.db');
    await db.insert('user_entries', {
      'id': 'synthetic-entry',
      'user_id': owner,
      'source': 'thought',
      'book_id': 'synthetic-book',
      'book_title': 'Synthetic book',
      'user_input': 'Synthetic retained note',
      'created_at': '2026-09-01T00:00:00Z',
    });
    await db.insert('pending_upload_operations', {
      'operation_id': 'synthetic-op',
      'user_id': owner,
      'entity_type': 'trace',
      'entity_id': 'synthetic-entry',
      'operation': 'create',
      'client_revision': 3,
      'generation': 5,
      'retry_count': 7,
      'created_at': '2026-09-01',
      'updated_at': '2026-09-01',
      'next_retry_at': '2026-10-01',
    });
  });
  setUp(() async {
    status = 401;
    paths.clear();
    SharedPreferences.setMockInitialValues({
      'auth_user_id': owner,
      'auth_token': 'synthetic-test-token',
    });
    await BmobApi.instance.init();
  });
  tearDownAll(() async {
    client.close(force: true);
    await server.close(force: true);
    await db.close();
    await dir.delete(recursive: true);
  });

  test(
    'both home endpoints expose status without response body or logout',
    () async {
      for (final code in [401, 403, 500]) {
        status = code;
        for (final request in <Future<Object> Function()>[
          () => BmobApi.instance.listUserEntries(),
          () => BmobApi.instance.getXiaouHomeInsight(),
        ]) {
          await expectLater(
            withServer(request),
            throwsA(
              isA<ApiRequestException>()
                  .having((e) => e.statusCode, 'status', code)
                  .having(
                    (e) => e.toString(),
                    'safe description',
                    'ApiRequestException(status=$code)',
                  ),
            ),
          );
        }
      }
      expect(paths.toSet(), {'/api/entries', '/api/insights/home'});
      expect(BmobApi.instance.userId, owner);
      expect(BmobApi.instance.isLoggedIn, true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), 'synthetic-test-token');
    },
  );

  test(
    '401 propagates through BookService and preserves local trace and queue',
    () async {
      final before = jsonEncode(await db.query('pending_upload_operations'));
      final entriesBefore = jsonEncode(await db.query('user_entries'));
      final changesBefore = await db.rawQuery('SELECT total_changes() AS n');
      final local = await BookService.restoreCachedMingtaiOverview();
      expect(local!.items.single['user_note'], 'Synthetic retained note');
      for (final request in <Future<Object> Function()>[
        () => BookService.getMingtaiOverview(
          forceRefresh: true,
          fallbackToCacheOnError: false,
        ),
        () => BookService.getXiaouHomeInsight(
          forceRefresh: true,
          fallbackToCacheOnError: false,
        ),
      ]) {
        await expectLater(
          withServer(request),
          throwsA(
            isA<ApiRequestException>().having(
              (e) => e.statusCode,
              'status',
              401,
            ),
          ),
        );
      }
      final retained = await BookService.restoreCachedMingtaiOverview();
      expect(retained!.items.single['user_note'], 'Synthetic retained note');
      expect(retained.items.single['pending_sync'], true);
      expect(jsonEncode(await db.query('pending_upload_operations')), before);
      expect(jsonEncode(await db.query('user_entries')), entriesBefore);
      expect(await db.rawQuery('SELECT total_changes() AS n'), changesBefore);
      expect(BmobApi.instance.userId, owner);
      expect(BmobApi.instance.isLoggedIn, true);
    },
  );

  test('successful reads keep their existing response contract', () async {
    status = 200;
    expect(await withServer(() => BmobApi.instance.listUserEntries()), isEmpty);
    expect(
      await withServer(() => BmobApi.instance.getXiaouHomeInsight()),
      isEmpty,
    );
  });
}
