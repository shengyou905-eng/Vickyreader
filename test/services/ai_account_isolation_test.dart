import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_reader/models/ai_conversation.dart';
import 'package:ai_reader/config/constants.dart';
import 'package:ai_reader/providers/ai_provider.dart';
import 'package:ai_reader/providers/reader_provider.dart';
import 'package:ai_reader/models/book.dart';
import 'package:ai_reader/services/ai_service.dart';
import 'package:ai_reader/services/auth_service.dart';
import 'package:ai_reader/services/auth_session_scope.dart';
import 'package:ai_reader/services/book_service.dart';
import 'package:ai_reader/services/database_service.dart';
import 'package:ai_reader/services/reliable_upload_service.dart';
import 'package:ai_reader/services/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_reader/widgets/session_bound_state.dart';

class _OfflineClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      throw const SocketException('synthetic offline');
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _PrivateView extends StatefulWidget {
  const _PrivateView();
  @override
  State<_PrivateView> createState() => _PrivateViewState();
}

class _PrivateViewState extends State<_PrivateView>
    with SessionBoundState<_PrivateView> {
  @override
  Widget build(BuildContext context) =>
      sessionActive ? const Text('private A history') : const SizedBox.shrink();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory dir;
  late Database db;
  Future<T> offline<T>(Future<T> Function() run) =>
      HttpOverrides.runZoned(run, createHttpClient: (_) => _OfflineClient());
  Future<void> asUser(String? owner) async {
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

  Future<void> entry(String id, String owner) => db
      .insert('user_entries', {
        'id': id,
        'user_id': owner,
        'source': 'ai_explanation',
        'book_id': 'shared-book',
        'book_title': 'Synthetic',
        'original_text': 'Same original passage',
        'ai_explanation': '$owner answer',
        'auto_tags': jsonEncode(['tag-$owner']),
        'created_at': '2026-01-01',
      })
      .then((_) {});
  AiMessage message(String text) => AiMessage(
    role: 'assistant',
    content: text,
    timestamp: DateTime.utc(2026),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await asUser('A');
    dir = await Directory.systemTemp.createTemp('zhidu-isolation-');
    db = await DatabaseService.openForTesting('${dir.path}/fixture.db');
    await db.insert('books', {
      'id': 'shared-book',
      'title': 'Synthetic',
      'author': '',
      'filePath': '',
      'addedAt': '2026-01-01',
      'lastOpenedAt': '2026-01-01',
    });
  });
  tearDown(() async {
    AiService.clientFactoryForTesting = null;
    await db.close();
    await dir.delete(recursive: true);
  });

  test(
    'same book and timestamp isolate A/B; unknown legacy row survives logout and restart',
    () async {
      await db.insert('ai_messages', {
        'id': 'legacy',
        'bookId': 'shared-book',
        'role': 'assistant',
        'content': 'unknown history',
        'timestamp': '2025-01-01',
      });
      await BookService.insertAiMessage('shared-book', message('A history'));
      await asUser('B');
      expect(await BookService.getAiMessages('shared-book'), isEmpty);
      await BookService.insertAiMessage('shared-book', message('B history'));
      expect(
        (await BookService.getAiMessages('shared-book')).single.content,
        'B history',
      );
      await asUser(null);
      expect(await BookService.getAiMessages('shared-book'), isEmpty);
      await asUser('A');
      await db.close();
      db = await DatabaseService.openForTesting('${dir.path}/fixture.db');
      expect(
        (await BookService.getAiMessages('shared-book')).single.content,
        'A history',
      );
      final rows = await db.query('ai_messages');
      expect(rows, hasLength(3));
      expect(rows.singleWhere((r) => r['id'] == 'legacy')['user_id'], isNull);
    },
  );

  test(
    'follow-ups require owned parent; offline fallback cannot reveal foreign or unknown rows',
    () => offline(() async {
      await entry('entry-A', 'A');
      await entry('entry-B', 'B');
      await db.insert('user_entry_follow_ups', {
        'id': 'unknown-followup',
        'entry_id': 'entry-A',
        'question': 'unknown',
        'answer': 'preserve',
        'created_at': '2025-01-01',
      });
      await BookService.insertUserEntryFollowUp(
        entryId: 'entry-A',
        question: 'A question',
        answer: 'A answer',
      );
      expect(
        (await BookService.getUserEntryFollowUps('entry-A')).single.question,
        'A question',
      );
      await asUser('B');
      await expectLater(
        BookService.getUserEntryFollowUps('entry-A'),
        throwsStateError,
      );
      await expectLater(
        BookService.insertUserEntryFollowUp(
          entryId: 'entry-A',
          question: 'wrong',
          answer: 'wrong',
        ),
        throwsStateError,
      );
      expect(await BookService.getUserEntryFollowUps('entry-B'), isEmpty);
      expect(await db.query('user_entry_follow_ups'), hasLength(2));
      expect(
        (await db.query(
          'user_entry_follow_ups',
          where: 'id = ?',
          whereArgs: ['unknown-followup'],
        )).single['user_id'],
        isNull,
      );
    }),
  );

  test(
    'trace lists, tags and local lookup are user scoped offline',
    () => offline(() async {
      await entry('entry-A', 'A');
      await entry('entry-B', 'B');
      await entry('entry-unknown', '');
      expect((await BookService.getUserEntries()).map((e) => e.id), [
        'entry-A',
      ]);
      expect(await BookService.getUserEntryTags(), ['tag-A']);
      await asUser('B');
      expect(await BookService.getLocalUserEntry('entry-A'), isNull);
      expect((await BookService.getLocalUserEntries()).map((e) => e.id), [
        'entry-B',
      ]);
      await expectLater(
        BookService.getLocalUserEntries(userId: 'A'),
        throwsA(isA<StaleAuthSession>()),
      );
      expect((await BookService.getUserEntries()).map((e) => e.id), [
        'entry-B',
      ]);
      expect(await BookService.getUserEntryTags(), ['tag-B']);
      expect(await db.query('user_entries'), hasLength(3));
    }),
  );

  test(
    'same-book reader annotations and review lists retain both owners but show only current owner',
    () async {
      for (final owner in ['A', 'B']) {
        await db.insert('highlights', {
          'id': 'highlight-$owner',
          'user_id': owner,
          'bookId': 'shared-book',
          'chapterIndex': '0',
          'selectedText': '$owner passage',
          'contextBefore': '',
          'contextAfter': '',
          'startOffset': 0,
          'endOffset': 3,
          'createdAt': '2026-01-01',
        });
        await BookService.insertNote(
          id: 'note-$owner',
          bookId: 'shared-book',
          content: '$owner thought',
          userId: owner,
        );
      }
      expect(
        (await BookService.getHighlights('shared-book')).single.userId,
        'A',
      );
      expect((await BookService.getAllNotes()).single['user_id'], 'A');
      await asUser('B');
      expect(
        (await BookService.getHighlights('shared-book')).single.userId,
        'B',
      );
      expect((await BookService.getAllHighlights()).single.userId, 'B');
      expect((await BookService.getAllNotes()).single['user_id'], 'B');
      expect(await db.query('highlights'), hasLength(2));
      expect(await db.query('notes'), hasLength(2));
    },
  );

  test('queued history read remains invalid after A to B to A', () async {
    final provider = AiProvider();
    final locked = Completer<void>(), release = Completer<void>();
    final transaction = db.transaction((txn) async {
      locked.complete();
      await release.future;
    });
    await locked.future;
    final reading = provider.loadHistory('shared-book');
    final rejected = expectLater(reading, throwsA(isA<StaleAuthSession>()));
    await asUser('B');
    await asUser('A');
    release.complete();
    await transaction;
    await rejected;
    expect(provider.messages, isEmpty);
    expect(provider.isLoading, isFalse);
    provider.dispose();
  });

  test(
    'in-flight model response cannot persist or revive across A to B to A',
    () => offline(() async {
      final provider = AiProvider();
      await provider.loadHistory('shared-book');
      final started = Completer<void>(), response = Completer<http.Response>();
      var calls = 0;
      AiService.clientFactoryForTesting = () => MockClient((request) {
        calls++;
        started.complete();
        return response.future;
      });
      final generation = provider.explain(
        selectedText: 'passage',
        bookTitle: 'book',
        bookAuthor: '',
        chapterContent: '<p>passage</p>',
        chapterIndex: '0',
      );
      await started.future;
      final old = AuthSessionScope.capture();
      await asUser('B');
      await asUser('A');
      expect(old.isCurrent, isFalse);
      response.complete(
        http.Response(
          'data: {"content":"old answer"}\n\ndata: {"status":"completed","finish_reason":"stop"}\n\ndata: [DONE]\n\n',
          200,
          headers: {'x-zhidu-ai-protocol': '2'},
        ),
      );
      await generation;
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      expect(provider.messages, isEmpty);
      expect(provider.isLoading, isFalse);
      expect(await db.query('ai_messages'), isEmpty);
      expect(await db.query('user_entries'), isEmpty);
      provider.dispose();
    }),
  );

  test('stale session cannot save into the reconnected same account', () async {
    final old = AuthSessionScope.capture();
    await asUser('B');
    await asUser('A');
    await expectLater(
      BookService.insertAiMessage(
        'shared-book',
        message('stale'),
        session: old,
      ),
      throwsA(isA<StaleAuthSession>()),
    );
    expect(await db.query('ai_messages'), isEmpty);
  });

  test(
    'queued history write rolls back when identity changes while SQLite is busy',
    () async {
      final locked = Completer<void>(), release = Completer<void>();
      final transaction = db.transaction((txn) async {
        locked.complete();
        await release.future;
      });
      await locked.future;
      final writing = BookService.insertAiMessage(
        'shared-book',
        message('stale queued write'),
      );
      final rejected = expectLater(writing, throwsA(isA<StaleAuthSession>()));
      await asUser('B');
      await asUser('A');
      release.complete();
      await transaction;
      await rejected;
      expect(await db.query('ai_messages'), isEmpty);
    },
  );

  test(
    'AI history write failure rolls back without changing existing history or upload state',
    () async {
      await BookService.insertAiMessage(
        'shared-book',
        message('original A history'),
      );
      final rows = await db.query('ai_messages');
      final pending = await db.query('pending_upload_operations');
      await db.execute(
        "CREATE TRIGGER fail_ai_history BEFORE INSERT ON ai_messages BEGIN SELECT RAISE(ABORT, 'synthetic insert failure'); END",
      );
      await expectLater(
        BookService.insertAiMessage('shared-book', message('must roll back')),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query('ai_messages'), rows);
      expect(await db.query('pending_upload_operations'), pending);
    },
  );

  test(
    'reader questions preserve scope metadata and original session ownership',
    () => offline(() async {
      final reader = ReaderProvider();
      await reader.openBook(
        Book(
          id: 'shared-book',
          userId: 'A',
          title: 'Synthetic',
          author: '',
          filePath: '',
          format: 'pdf',
          addedAt: DateTime.utc(2026),
          lastOpenedAt: DateTime.utc(2026),
        ),
      );
      final original = AuthSessionScope.capture();
      await reader.addAiQuestion(
        question: 'question',
        answer: 'answer',
        scope: 'selection',
        contextText: 'long original passage',
        pageText: 'page',
        session: original,
      );
      final row = (await db.query('user_entries')).single;
      expect(row['user_id'], 'A');
      expect(
        (jsonDecode(row['metadata_json'] as String) as Map)['question_scope'],
        'selection',
      );
      await asUser('B');
      await asUser('A');
      expect(reader.book, isNull);
      await expectLater(
        reader.addAiQuestion(
          question: 'stale',
          answer: 'stale',
          scope: 'page',
          contextText: '',
          pageText: '',
          session: original,
        ),
        throwsA(isA<StaleAuthSession>()),
      );
      expect(await db.query('user_entries'), hasLength(1));
      reader.dispose();
    }),
  );

  test(
    'disk and memory caches isolate account and origin without claiming legacy cache',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final origin = sha256.convert(utf8.encode(AppConstants.apiBaseUrl));
      await prefs.setString(
        'xiaou_home_cache_v4_${origin}_A',
        jsonEncode({'weekly_summary': 'A cache'}),
      );
      await prefs.setString(
        'xiaou_home_cache_v4_${origin}_B',
        jsonEncode({'weekly_summary': 'B cache'}),
      );
      await prefs.setString(
        'xiaou_home_cache_v4_A',
        jsonEncode({'weekly_summary': 'unknown origin legacy'}),
      );
      expect(
        (await BookService.restoreCachedXiaouHomeInsight())!.weeklySummary,
        'A cache',
      );
      await asUser('B');
      expect(BookService.cachedXiaouHomeInsight(), isNull);
      expect(
        (await BookService.restoreCachedXiaouHomeInsight())!.weeklySummary,
        'B cache',
      );
      await asUser(null);
      expect(await BookService.restoreCachedXiaouHomeInsight(), isNull);
      await asUser('A');
      expect(
        (await BookService.restoreCachedXiaouHomeInsight())!.weeklySummary,
        'A cache',
      );
      expect(
        prefs.getString('xiaou_home_cache_v4_A'),
        contains('unknown origin legacy'),
      );
    },
  );

  test(
    'pending disk cache restoration rejects an A to B to A session',
    () async {
      final loading = BookService.restoreCachedXiaouHomeInsight();
      AuthSessionScope.beginTransition();
      AuthSessionScope.publish('B', 'synthetic-B');
      AuthSessionScope.publish('A', 'synthetic-A');
      await expectLater(loading, throwsA(isA<StaleAuthSession>()));
    },
  );

  test(
    'unknown AI pending and revision are not claimed by a login',
    () => offline(() async {
      await entry('unknown-ai', '');
      final uploader = ReliableUploadService(databaseProvider: () async => db);
      await db.transaction((txn) async {
        await uploader.enqueueTrace(
          txn,
          userId: '',
          entityId: 'unknown-ai',
          operation: 'create',
          payload: {'source': 'ai_explanation', 'book_id': 'shared-book'},
        );
      });
      final before = await db.query('pending_upload_operations');
      final revisions = await db.query('upload_entity_revisions');
      await uploader.claimAnonymousOperations('B');
      expect(await db.query('pending_upload_operations'), before);
      expect(await db.query('upload_entity_revisions'), revisions);
      expect((await db.query('user_entries')).single['user_id'], '');
      await SyncService.instance.mergeAnonymousData('A');
      expect((await db.query('user_entries')).single['user_id'], '');
      expect(await db.query('pending_upload_operations'), before);
      expect(await db.query('upload_entity_revisions'), revisions);
      SyncService.instance.setUserId(null);
    }),
  );

  testWidgets(
    'private view hides immediately at identity transition and never revives',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _PrivateView()));
      expect(find.text('private A history'), findsOneWidget);
      AuthSessionScope.beginTransition();
      await tester.pump();
      expect(find.text('private A history'), findsNothing);
      await asUser('A');
      await tester.pump();
      expect(find.text('private A history'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
