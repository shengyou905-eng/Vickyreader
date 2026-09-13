import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_reader/app.dart';
import 'package:ai_reader/config/constants.dart';
import 'package:ai_reader/config/local_diagnostics_mode.dart';
import 'package:ai_reader/providers/auth_provider.dart';
import 'package:ai_reader/screens/settings/local_sync_diagnostics_screen.dart';
import 'package:ai_reader/services/database_service.dart';
import 'package:ai_reader/services/local_sync_diagnostics.dart';
import 'package:ai_reader/services/reliable_upload_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late Database db;
  late String path;
  late int databaseRequests;
  late ReliableUploadService uploader;
  const evidence = LocalDiagnosticsMode.enabled;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'zhidu_evidence_mode_test_',
    );
    path = '${directory.path}/${AppConstants.dbName}';
    databaseFactory = databaseFactoryFfi;
    db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.rawQuery('PRAGMA journal_mode = WAL');
    await db.rawQuery('PRAGMA wal_autocheckpoint = 0');
    // Older schema intentionally: opening evidence mode must not upgrade it.
    await db.execute('PRAGMA user_version = 14');
    await db.execute('CREATE TABLE upload_writer (writer_id TEXT)');
    await db.insert('upload_writer', {'writer_id': 'test-writer'});
    await db.execute(
      'CREATE TABLE pending_upload_operations (operation_id TEXT, user_id TEXT, entity_type TEXT, entity_id TEXT, operation TEXT, payload_json TEXT, created_at TEXT, updated_at TEXT, client_revision INTEGER, generation INTEGER, retry_count INTEGER, last_error_at TEXT, next_retry_at TEXT)',
    );
    await db.insert('pending_upload_operations', {
      'operation_id': 'original-op',
      'user_id': 'fixture-user',
      'entity_type': 'trace',
      'entity_id': 'trace-1',
      'operation': 'create',
      'payload_json': '{}',
      'created_at': '2026-09-01',
      'updated_at': '2026-09-01',
      'client_revision': 7,
      'generation': 11,
      'retry_count': 3,
      'last_error_at': '2026-09-01',
      'next_retry_at': '2000-01-01',
    });
    databaseRequests = 0;
    uploader = ReliableUploadService(
      databaseProvider: () async {
        databaseRequests++;
        return db;
      },
      userIdProvider: () => 'no-pending-for-this-user',
      isAuthenticated: () => true,
    );
    SharedPreferences.setMockInitialValues({
      'auth_user_id': 'fixture-user',
      'auth_token': 'fixture-secret-never-export',
      'unrelated-setting': 42,
    });
  });

  tearDown(() async {
    uploader.stop();
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'compile-time mode controls start and scheduler without runtime override',
    () async {
      var periodicTimers = 0;
      await runZoned(
        () async {
          uploader.start();
          await uploader.drain();
          uploader.stop();
        },
        zoneSpecification: ZoneSpecification(
          createPeriodicTimer: (self, parent, zone, duration, callback) {
            periodicTimers++;
            return parent.createPeriodicTimer(zone, duration, callback);
          },
        ),
      );
      expect(periodicTimers, evidence ? 0 : 1);
      expect(databaseRequests, evidence ? 0 : greaterThan(0));
    },
  );

  test(
    'evidence mode refuses queue writes and business database initialization',
    () async {
      final before = await File(path).readAsBytes();
      final wal = await File('$path-wal').readAsBytes();
      final auth = AuthProvider();
      await Future<void>.value();
      // Even accidental construction must not initialize the stored session.
      expect(auth.isLoggedIn, false);
      auth.dispose();
      await uploader.claimAnonymousOperations('fixture-user');
      await uploader.drain();
      await expectLater(DatabaseService.database, throwsStateError);
      await expectLater(
        uploader.enqueueTrace(
          db,
          userId: 'fixture-user',
          entityId: 'new',
          operation: 'create',
        ),
        throwsStateError,
      );
      await expectLater(
        uploader.enqueueLibrarySnapshot(db, userId: 'fixture-user', books: []),
        throwsStateError,
      );
      await expectLater(
        uploader.enqueueReadingProgress(
          db,
          userId: 'fixture-user',
          bookId: 'book',
          operation: 'upsert',
        ),
        throwsStateError,
      );
      await expectLater(
        uploader.enqueuePermanentBookDeletion(
          db,
          userId: 'fixture-user',
          bookId: 'book',
          localTraceIds: [],
        ),
        throwsStateError,
      );
      expect(databaseRequests, 0);
      expect(await File(path).readAsBytes(), before);
      expect(await File('$path-wal').readAsBytes(), wal);
    },
    skip: !evidence,
  );

  testWidgets('normal build retains original provider startup tree', (
    tester,
  ) async {
    Widget? root;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          root = const AiReaderApp().build(context);
          return const SizedBox.shrink();
        },
      ),
    );
    expect(root, isA<MultiProvider>());
    expect(LocalSyncDiagnostics.enabled, false);
  }, skip: evidence);

  testWidgets(
    'evidence boot, foreground, timers, export and share leave DB/WAL and account unchanged',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      const bundleChannel = MethodChannel('zhidu/local_sync_diagnostics');
      var pathCalls = 0;
      Map<String, dynamic>? exported;
      messenger.setMockMethodCallHandler(pathChannel, (call) async {
        pathCalls++;
        expect([
          'getApplicationDocumentsDirectory',
          'getTemporaryDirectory',
        ], contains(call.method));
        return directory.path;
      });
      messenger.setMockMethodCallHandler(
        bundleChannel,
        (call) async => {'version': '1.0.0', 'build_number': '9'},
      );
      messenger.setMockMethodCallHandler(shareChannel, (call) async {
        expect(call.method, 'shareFiles');
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final files = args['paths'] as List;
        expect(files, hasLength(1));
        expect(files.single, contains('zhidu_diagnostic_'));
        exported =
            jsonDecode(await File(files.single as String).readAsString())
                as Map<String, dynamic>;
        return 'dev.fluttercommunity.plus/share/unavailable';
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(pathChannel, null);
        messenger.setMockMethodCallHandler(bundleChannel, null);
        messenger.setMockMethodCallHandler(shareChannel, null);
      });
      final prefs = await SharedPreferences.getInstance();
      final prefsBefore = {
        for (final key in prefs.getKeys()) key: prefs.get(key),
      };
      final before = await tester.runAsync(() => File(path).readAsBytes());
      final wal = await tester.runAsync(() => File('$path-wal').readAsBytes());

      await tester.pumpWidget(const AiReaderApp());
      await tester.pumpAndSettle();
      expect(find.byType(LocalSyncDiagnosticsScreen), findsOneWidget);
      expect(find.byType(MainScreen), findsNothing);
      expect(find.byType(ChangeNotifierProvider<AuthProvider>), findsNothing);
      expect(
        pathCalls,
        0,
      ); // No business DB or startup migration was even opened.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(minutes: 3));
      expect(pathCalls, 0);
      await tester.runAsync(() async {
        expect(await File(path).readAsBytes(), before);
        expect(await File('$path-wal').readAsBytes(), wal);
        await tester.tap(find.text('Export Local Sync State'));
        // Wait for real filesystem/plugin operations without pumping forever.
        for (var i = 0; i < 200 && exported == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(exported, isNotNull);
        expect((exported!['database'] as Map)['user_version'], 14);
        expect((exported!['app'] as Map)['automatic_sync_disabled'], true);
        expect(jsonEncode(exported), isNot(contains('fixture-secret')));
        final pending =
            ((exported!['records'] as Map)['pending_upload_operations'] as List)
                    .single
                as Map;
        expect(pending['client_revision'], 7);
        expect(pending['generation'], 11);
        expect(pending['retry_count'], 3);
        expect(pending['next_retry_at'], '2000-01-01');
      });
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(minutes: 3));
      await tester.runAsync(() async {
        expect(await File(path).readAsBytes(), before);
        expect(await File('$path-wal').readAsBytes(), wal);
      });
      expect({
        for (final key in prefs.getKeys()) key: prefs.get(key),
      }, prefsBefore);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !evidence,
  );
}
