import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ai_reader/models/ai_explain_mode.dart';
import 'package:ai_reader/providers/ai_provider.dart';
import 'package:ai_reader/services/ai_service.dart';
import 'package:ai_reader/services/auth_service.dart';
import 'package:ai_reader/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _OfflineClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      throw const SocketException('synthetic offline');
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory dir;
  late Database db;
  late AiProvider provider;
  final requests = <Map<String, dynamic>>[];
  const complete =
      'data: {"content":"verified answer"}\n\ndata: {"status":"completed","finish_reason":"stop"}\n\ndata: [DONE]\n\n';
  Future<void> offline(Future<void> Function() run) =>
      HttpOverrides.runZoned(run, createHttpClient: (_) => _OfflineClient());
  Future<void> explain() => provider.explain(
    selectedText: 'Original passage',
    bookTitle: 'Original book',
    bookAuthor: 'Original author',
    chapterContent: '<p>Original passage</p>',
    chapterIndex: '3',
    chapterTitle: 'Original chapter',
    mode: AiExplainMode.argument,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'auth_token': 'synthetic',
      'auth_user_id': 'synthetic-owner',
    });
    await AuthService.init();
    dir = await Directory.systemTemp.createTemp('p0a-provider-');
    db = await DatabaseService.openForTesting('${dir.path}/test.db');
    await db.insert('books', {
      'id': 'book',
      'title': 'Synthetic',
      'author': '',
      'filePath': '',
      'addedAt': '2026-01-01',
      'lastOpenedAt': '2026-01-01',
    });
    provider = AiProvider();
    await provider.loadHistory('book');
    requests.clear();
    AiService.clientFactoryForTesting = () => MockClient((request) async {
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(
        complete,
        200,
        headers: {'x-zhidu-ai-protocol': '2'},
      );
    });
  });
  tearDown(() async {
    provider.clearMessages();
    provider.dispose();
    AiService.clientFactoryForTesting = null;
    await db.close();
    await dir.delete(recursive: true);
  });

  test(
    'provider retains first evidence after 14 turns and saves independent active explanations',
    () => offline(() async {
      await explain();
      expect(provider.error, isNull);
      for (var round = 1; round <= 14; round++) {
        final question = round == 2
            ? '纠正：这里的条件不能省略'
            : round == 3
            ? '未解决：因果证据是否充分'
            : 'Followup $round';
        await provider.sendFollowUp(question);
        expect(provider.error, isNull);
        expect(requests.last['selectedText'], 'Original passage');
        expect(requests.last['bookTitle'], 'Original book');
        expect(requests.last['bookAuthor'], 'Original author');
        expect(requests.last['mode'], 'argument');
        expect(requests.last['initialAnswer'], 'verified answer');
        final history = requests.last['history'] as List;
        expect(history.length % 2, 0);
        expect(history.length, lessThanOrEqualTo(24));
        expect(history.any((m) => m['content'] == question), isFalse);
        if (round == 14) {
          expect(history.any((m) => m['content'] == '纠正：这里的条件不能省略'), isTrue);
          expect(history.any((m) => m['content'] == '未解决：因果证据是否充分'), isTrue);
        }
      }
      expect(await db.query('user_entries'), hasLength(1));
      expect(await db.query('user_entry_follow_ups'), hasLength(14));
      await explain();
      expect(provider.error, isNull);
      expect(await db.query('user_entries'), hasLength(2));
      expect(
        requests,
        hasLength(15),
      ); // Cache reuse still saves a separate trace.
      await provider.sendFollowUp('new independent discussion');
      final newHistory = requests.last['history'] as List;
      expect(newHistory.any((m) => m['content'] == '纠正：这里的条件不能省略'), isFalse);
      expect(await db.query('user_entry_follow_ups'), hasLength(15));
    }),
  );

  test(
    'answer cache distinguishes book metadata while independent same-context history survives',
    () => offline(() async {
      await explain();
      await explain();
      expect(requests, hasLength(1));
      await provider.explain(
        selectedText: 'Original passage',
        bookTitle: 'Changed title',
        bookAuthor: 'Original author',
        chapterContent: '<p>Original passage</p>',
        chapterIndex: '3',
        chapterTitle: 'Original chapter',
        mode: AiExplainMode.argument,
      );
      expect(provider.error, isNull);
      expect(requests, hasLength(2));
      expect(requests.last['bookTitle'], 'Changed title');
      expect((requests.last['history'] as List), isEmpty);
      final entries = await db.query('user_entries');
      expect(entries, hasLength(3));
      expect(entries.map((row) => row['id']).toSet(), hasLength(3));
    }),
  );

  test(
    'partial stream EOF never creates success messages or trace',
    () => offline(() async {
      AiService.clientFactoryForTesting = () => MockClient(
        (_) async => http.Response(
          'data: {"content":"partial"}\n\n',
          200,
          headers: {'x-zhidu-ai-protocol': '2'},
        ),
      );
      await explain();
      expect(provider.error, isNotNull);
      expect(await db.query('user_entries'), isEmpty);
      expect(await db.query('ai_messages'), isEmpty);
      expect(provider.messages.where((m) => m.role == 'assistant'), isEmpty);
    }),
  );

  test(
    'cancelled partial answer is not saved and repeated click during stream is ignored',
    () => offline(() async {
      var calls = 0;
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      AiService.clientFactoryForTesting = () =>
          MockClient.streaming((request, stream) async {
            calls++;
            await stream.toBytes();
            return http.StreamedResponse(
              body.stream,
              200,
              headers: {'x-zhidu-ai-protocol': '2'},
            );
          });
      final received = Completer<void>();
      provider.addListener(() {
        if (provider.messages.any(
              (m) => m.role == 'assistant' && m.content == 'partial',
            ) &&
            !received.isCompleted) {
          received.complete();
        }
      });
      final pending = explain();
      body.add(utf8.encode('data: {"content":"partial"}\n\n'));
      await received.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw StateError('partial event not delivered'),
      );
      await explain();
      expect(calls, 1);
      await provider.cancelGeneration().timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw StateError('cancel did not finish'),
      );
      await pending.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw StateError('provider did not finish'),
      );
      expect(cancelled, true);
      expect(await db.query('user_entries'), isEmpty);
      expect(await db.query('ai_messages'), isEmpty);
      await body.close().timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw StateError('source did not close'),
      );
    }),
  );
}
