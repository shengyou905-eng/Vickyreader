import 'dart:async';
import 'dart:convert';

import 'package:ai_reader/screens/xiaou/book_recap_screen.dart';
import 'package:ai_reader/screens/xiaou/recap_pilot_entry.dart';
import 'package:ai_reader/services/auth_service.dart';
import 'package:ai_reader/services/auth_session_scope.dart';
import 'package:ai_reader/services/book_recap_client_contract.dart';
import 'package:ai_reader/services/privacy_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zhidu/recap_network_path');
  const owner = '11111111-1111-4111-8111-111111111111';
  final requests = <http.Request>[];
  late Future<http.Response> Function(http.Request) respond;
  http.Response capability([bool enabled = true]) => http.Response(
    jsonEncode({'enabled': enabled, 'policy_version': recapDisplayPolicy}),
    200,
  );
  Future<void> path(bool online) async {
    final done = Completer<void>();
    binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeSuccessEnvelope(online),
      (_) => done.complete(),
    );
    await done.future;
  }

  Future<void> host(
    WidgetTester tester, {
    bool active = true,
    int refresh = 0,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RecapPilotEntry(isActive: active, refreshSignal: refresh),
      ),
    ),
  );
  Future<void> run(Future<void> Function() body) => http.runWithClient(
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
        // End the native stream so the next test owns its own async zone.
        final done = Completer<void>();
        binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          null,
          (_) => done.complete(),
        );
        await done.future;
      }
    },
    () => MockClient((r) {
      requests.add(r);
      return respond(r);
    }),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'auth_user_id': owner,
      'auth_token': 'synthetic-only-token',
    });
    await AuthService.init();
    requests.clear();
    respond = (_) async => capability();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => null,
    );
  });
  tearDown(() async {
    await path(false);
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'capability uses authenticated HTTPS and rechecks before opening',
    (t) => run(() async {
      await host(t);
      await path(true);
      await t.pumpAndSettle();
      expect(find.byType(BookRecapEntry), findsOneWidget);
      expect(requests.single.url.scheme, 'https');
      expect(requests.single.url.path, '/api/recaps/capability');
      expect(
        requests.single.headers['authorization'],
        'Bearer synthetic-only-token',
      );
      expect(requests.single.followRedirects, isFalse);
      final entry = t.widget<BookRecapEntry>(find.byType(BookRecapEntry));
      expect(await entry.checkAccess!(), isTrue);
      expect(requests.length, 2);
      await t.pumpWidget(const SizedBox.shrink());
    }),
  );

  testWidgets(
    'initial consent denial recovers on returning to the active tab',
    (t) => run(() async {
      respond = (_) async =>
          http.Response('{"error_code":"AI_CONSENT_REQUIRED"}', 428);
      await host(t);
      await path(true);
      await t.pumpAndSettle();
      expect(find.byType(BookRecapEntry), findsNothing);
      await host(t, active: false);
      respond = (_) async => capability();
      await host(t, refresh: 1);
      await t.pumpAndSettle();
      expect(find.byType(BookRecapEntry), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    }),
  );

  testWidgets(
    'offline start recovers once on network change without polling',
    (t) => run(() async {
      await host(t);
      await t.pumpAndSettle();
      expect(requests, isEmpty);
      await path(true);
      await t.pumpAndSettle();
      expect(find.byType(BookRecapEntry), findsOneWidget);
      await t.pump(const Duration(minutes: 1));
      expect(requests.length, 1);
      await path(false);
      await t.pumpAndSettle();
      expect(find.byType(BookRecapEntry), findsNothing);
      await path(true);
      await t.pumpAndSettle();
      expect(requests.length, 2);
      await t.pumpWidget(const SizedBox.shrink());
    }),
  );

  testWidgets(
    'account A to B to A rejects delayed discovery from the old epoch',
    (t) => run(() async {
      final held = Completer<http.Response>();
      respond = (_) => held.future;
      await host(t);
      await path(true);
      await t.pump();
      AuthSessionScope.beginTransition();
      AuthSessionScope.publish('22222222-2222-4222-8222-222222222222', 'other');
      respond = (_) async => capability(false);
      AuthSessionScope.beginTransition();
      AuthSessionScope.publish(owner, 'synthetic-only-token');
      held.complete(capability());
      await t.pumpAndSettle();
      expect(find.byType(BookRecapEntry), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    }),
  );

  testWidgets(
    'consent withdrawal and failed click hide previously discovered entry',
    (t) => run(() async {
      await host(t);
      await path(true);
      await t.pumpAndSettle();
      respond = (_) async =>
          http.Response('{"error_code":"RECAP_PILOT_DISABLED"}', 403);
      final entry = t.widget<BookRecapEntry>(find.byType(BookRecapEntry));
      expect(await entry.checkAccess!(), isFalse);
      await t.pumpAndSettle();
      expect(find.byType(BookRecapEntry), findsNothing);
      respond = (_) async => capability();
      await host(t, refresh: 1);
      await t.pumpAndSettle();
      expect(find.byType(BookRecapEntry), findsOneWidget);
      respond = (_) async =>
          http.Response('{"error_code":"AI_CONSENT_REQUIRED"}', 428);
      PrivacyService.aiConsentChanges.value++;
      await t.pumpAndSettle();
      expect(find.byType(BookRecapEntry), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    }),
  );

  testWidgets(
    'background cancels discovery and resume requires fresh capability',
    (t) => run(() async {
      final held = Completer<http.Response>();
      respond = (_) => held.future;
      await host(t);
      await path(true);
      await t.pump();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      held.complete(capability());
      await t.pumpAndSettle();
      expect(find.byType(BookRecapEntry), findsNothing);
      respond = (_) async => capability();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(find.byType(BookRecapEntry), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    }),
  );
}
