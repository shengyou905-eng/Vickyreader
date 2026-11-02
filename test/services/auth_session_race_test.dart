import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ai_reader/services/auth_service.dart';
import 'package:ai_reader/services/apple_auth_service.dart';
import 'package:ai_reader/services/auth_session_scope.dart';
import 'package:ai_reader/services/book_service.dart';
import 'package:ai_reader/services/xiaou_conversation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttp extends HttpOverrides {}

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
  late HttpServer server;
  late HttpClient client;
  final received = <String, Completer<void>>{};
  final release = <String, Completer<void>>{};
  final seenOwners = <String>[];
  String? failLogin;

  Future<T> withServer<T>(Future<T> Function() run) => HttpOverrides.runZoned(
    run,
    createHttpClient: (_) => _LoopbackClient(client, server.port),
  );
  Future<void> seed(String? owner) async {
    final prefs = await SharedPreferences.getInstance();
    if (owner == null) {
      await prefs.remove('auth_user_id');
      await prefs.remove('auth_token');
    } else {
      await prefs.setString('auth_user_id', owner);
      await prefs.setString('auth_token', 'synthetic-$owner');
    }
    await AuthService.init();
  }

  void gate(String name) {
    received[name] = Completer<void>();
    release[name] = Completer<void>();
  }

  Future<void> notify(String name) async {
    final signal = received[name];
    if (signal != null && !signal.isCompleted) signal.complete();
    await release[name]?.future;
  }

  setUpAll(() async {
    client = HttpOverrides.runWithHttpOverrides(
      () => HttpClient(),
      _RealHttp(),
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final data = body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;
      final path = request.uri.path;
      request.response.headers.contentType = ContentType.json;
      if (path == '/api/auth/login') {
        final owner = data['email'].toString();
        await notify(owner);
        if (failLogin == owner) {
          request.response.statusCode = 401;
          request.response.write('{"error":"synthetic login rejected"}');
        } else {
          request.response.write(
            jsonEncode({
              'token': 'synthetic-$owner',
              'user': {'id': owner, 'email': owner, 'has_password': true},
            }),
          );
        }
      } else if (path == '/api/auth/logout') {
        await notify('logout');
        request.response.write('{}');
      } else if (path == '/api/insights/home') {
        seenOwners.add(request.headers.value('authorization') ?? '');
        await notify('insight');
        request.response.write(
          '{"insight":{"weekly_summary":"old A response"}}',
        );
      } else if (path == '/api/xiaou/conversations') {
        seenOwners.add(request.headers.value('authorization') ?? '');
        await notify('history');
        request.response.write(
          '{"conversations":[{"id":"A-thread","title":"A private history"}]}',
        );
      } else {
        request.response.statusCode = 404;
        request.response.write('{}');
      }
      await request.response.close();
    });
  });
  setUp(() async {
    received.clear();
    release.clear();
    seenOwners.clear();
    failLogin = null;
    SharedPreferences.setMockInitialValues({});
    await seed('original');
  });
  tearDown(() {
    for (final signal in release.values) {
      if (!signal.isCompleted) signal.complete();
    }
  });
  tearDownAll(() async {
    client.close(force: true);
    await server.close(force: true);
  });

  test(
    'concurrent logins commit only the newest attempt, including persisted session',
    () => withServer(() async {
      gate('A');
      gate('B');
      final oldScope = AuthSessionScope.capture();
      final loginA = AuthService.signIn('A', 'synthetic-password');
      await received['A']!.future;
      expect(oldScope.isCurrent, isFalse);
      final loginB = AuthService.signIn('B', 'synthetic-password');
      await received['B']!.future;
      release['B']!.complete();
      expect((await loginB)?['error'], isNull);
      release['A']!.complete();
      expect((await loginA)?['error'], isNotNull);
      expect(AuthService.userId, 'B');
      await AuthService.init();
      expect(AuthService.userId, 'B');
      expect(
        (await SharedPreferences.getInstance()).getString('auth_user_id'),
        'B',
      );
    }),
  );

  test(
    'failed newest login cannot revive a superseded successful response',
    () => withServer(() async {
      gate('A');
      gate('B');
      failLogin = 'B';
      final a = AuthService.signIn('A', 'synthetic-password');
      await received['A']!.future;
      final b = AuthService.signIn('B', 'synthetic-password');
      await received['B']!.future;
      release['A']!.complete();
      expect((await a)?['error'], isNotNull);
      release['B']!.complete();
      expect((await b)?['error'], isNotNull);
      await AuthService.init();
      expect(AuthService.userId, 'original');
    }),
  );

  test(
    'logout hides local identity before network completion and does not clear a later login',
    () => withServer(() async {
      gate('logout');
      final old = AuthSessionScope.capture();
      final loggingOut = AuthService.signOut();
      expect(old.isCurrent, isFalse);
      expect(AuthService.userId, isNull);
      await received['logout']!.future;
      await AuthService.signIn('B', 'synthetic-password');
      release['logout']!.complete();
      await loggingOut;
      await AuthService.init();
      expect(AuthService.userId, 'B');
    }),
  );

  test(
    'restart reads one committed identity even if legacy keys are partially written',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', 'synthetic-A');
      await prefs.setString('auth_user_id', 'A');
      await prefs.setString(
        'auth_session_v2',
        jsonEncode({
          'version': 2,
          'token': 'synthetic-B',
          'user_id': 'B',
          'email': 'B',
        }),
      );
      await AuthService.init();
      expect(AuthService.userId, 'B');
      expect(AuthService.token, 'synthetic-B');
    },
  );

  test(
    'restart honors durable logout marker instead of stale legacy credentials',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'auth_session_v2',
        jsonEncode({'version': 2, 'token': null, 'user_id': null}),
      );
      await AuthService.init();
      expect(AuthService.userId, isNull);
      expect(AuthService.isLoggedIn, isFalse);
    },
  );

  test(
    'malformed committed session fails closed without falling back to another identity',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_session_v2', '{invalid');
      await AuthService.init();
      expect(AuthService.userId, isNull);
      expect(AuthService.token, isNull);
    },
  );

  test(
    'immediate logout and login keep the newest committed identity',
    () => withServer(() async {
      final loggingOut = AuthService.signOut();
      final signingIn = AuthService.signIn('B', 'synthetic-password');
      await loggingOut;
      await signingIn;
      await AuthService.init();
      expect(AuthService.userId, 'B');
    }),
  );

  test(
    'late cloud conversation response is rejected after A to B to A',
    () => withServer(() async {
      await seed('A');
      gate('history');
      final loading = XiaouConversationService.list();
      final check = expectLater(loading, throwsA(isA<StaleAuthSession>()));
      await received['history']!.future;
      await seed('B');
      await seed('A');
      release['history']!.complete();
      await check;
      expect(seenOwners, ['Bearer synthetic-A']);
    }),
  );

  test(
    'late native Apple credential cannot start a login after the account changed',
    () async {
      final requested = Completer<void>();
      final credential = Completer<AppleCredentialPayload?>();
      var completions = 0;
      final signingIn = AppleAuthService.authorize(
        bind: false,
        availabilityCheck: () async => true,
        preparationLoader: () async => {'state': 'synthetic-state'},
        credentialRequest: ({required nonce, required state}) {
          requested.complete();
          return credential.future;
        },
        completion: ({required bind, required credential}) async {
          completions++;
        },
      );
      final rejected = expectLater(signingIn, throwsA(isA<StaleAuthSession>()));
      await requested.future;
      await seed('B');
      credential.complete(
        const AppleCredentialPayload(
          authorizationCode: 'synthetic-code',
          identityToken: 'synthetic-identity',
          state: 'synthetic-state',
        ),
      );
      await rejected;
      expect(completions, 0);
      expect(AuthService.userId, 'B');
    },
  );

  test(
    'late home response cannot fill memory or disk cache for the returning account',
    () => withServer(() async {
      await seed('A');
      gate('insight');
      final loading = BookService.getXiaouHomeInsight(forceRefresh: true);
      final check = expectLater(loading, throwsA(isA<StaleAuthSession>()));
      await received['insight']!.future;
      await seed('B');
      await seed('A');
      release['insight']!.complete();
      await check;
      expect(BookService.cachedXiaouHomeInsight(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((key) => key.startsWith('xiaou_home_cache_')),
        isEmpty,
      );
    }),
  );
}
