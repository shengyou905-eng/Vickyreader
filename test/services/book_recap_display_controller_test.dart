import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_reader/services/auth_session_scope.dart';
import 'package:ai_reader/services/privacy_service.dart';
import 'package:ai_reader/services/reading_source_changes.dart';
import '../support/recap_display_fixture.dart';
import 'book_recap_client_test.dart' as base;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecapDisplayFixture f;
  setUp(() async {
    f = RecapDisplayFixture();
    await f.init();
  });
  tearDown(() async {
    await f.dispose();
  });
  test(
    'old GET never issues body; new view must provide approved matching lease',
    () async {
      final c = f.controller(policies: {});
      await c.open(f.current['id'], f.selection);
      expect(c.content, isNull);
      await expectLater(c.readForDisplay(), throwsA(anything));
      expect(c.content, isNull);
      expect(f.requests.any((r) => r.url.path.endsWith('/view')), isTrue);
    },
  );
  for (final key in [
    'policy_version',
    'recap_id',
    'book_id',
    'revision',
    'source_fingerprint',
  ]) {
    test('reject mismatched display $key', () async {
      final c = await f.open();
      f.alterGrant = (g) => g[key] = key == 'revision' ? '999' : 'wrong';
      await expectLater(c.readForDisplay(), throwsA(anything));
      expect(c.content, isNull);
    });
  }
  test(
    'monotonic RTT consumes permission even if wall clock looks fresh',
    () async {
      final c = await f.open();
      f.alterGrant = (g) => f.elapsed += const Duration(seconds: 21);
      await expectLater(c.readForDisplay(), throwsA(anything));
      expect(c.content, isNull);
    },
  );
  test(
    'renewal is explicit, old body revoked; expiry cannot revive cached data',
    () async {
      final c = await f.open(), old = await c.readForDisplay();
      final next = await c.renewDisplay();
      expect(old.toJson, base.code('CONFIRM_REQUIRED'));
      expect(next.toJson()['result'], isNotNull);
      f.elapsed += const Duration(seconds: 21);
      expect(next.toJson, base.code('CONFIRM_REQUIRED'));
      await expectLater(c.renewDisplay(), throwsA(anything));
      final calls = f.requests.length;
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(f.requests.length, calls);
    },
  );
  test(
    'evidence and follow-ups receive version bound grants, no ordinary conversation path',
    () async {
      final c = await f.open();
      final evidence = await c.evidenceForDisplay([
        RecapDisplayFixture.evidenceId,
      ]);
      expect(evidence.toJson()['evidence'], hasLength(1));
      await c.followUp('为什么不能保证？');
      expect(evidence.toJson, base.code('CONFIRM_REQUIRED'));
      final history = await c.followUpsForDisplay();
      expect(history.toJson()['turns'], hasLength(1));
      expect(
        f.requests.any((r) => r.url.path.contains('conversation')),
        isFalse,
      );
    },
  );
  test('wrong evidence response cannot expand requested selection', () async {
    final c = await f.open();
    await expectLater(
      c.evidenceForDisplay(['e-${'c' * 64}']),
      base.code('INVALID_RESPONSE'),
    );
  });
  test(
    'revoke consent, offline and committed source writes withdraw memory',
    () async {
      final c = await f.open();
      final first = await c.readForDisplay();
      PrivacyService.aiConsentChanges.value++;
      expect(first.toJson, base.code('CONFIRM_REQUIRED'));
      final second = await c.readForDisplay();
      c.setOnline(false);
      expect(second.toJson, base.code('CONFIRM_REQUIRED'));
      c.setOnline(true);
      final third = await c.readForDisplay();
      ReadingSourceChanges.committed();
      expect(third.toJson, base.code('CONFIRM_REQUIRED'));
    },
  );
  test(
    'account A-B-A and view response arriving late cannot issue content',
    () async {
      final c = await f.open();
      f.hold = Completer();
      f.heldAction = 'view';
      final future = c.readForDisplay();
      final check = expectLater(future, throwsA(anything));
      while (!f.requests.any((r) => r.url.path.endsWith('/view'))) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      AuthSessionScope.publish(base.other, 'other');
      AuthSessionScope.publish(base.owner, 'synthetic-token');
      f.hold!.complete();
      f.hold = null;
      await check;
      expect(c.content, isNull);
    },
  );
}
