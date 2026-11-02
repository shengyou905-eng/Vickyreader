import 'dart:async';
import 'dart:convert';
import 'package:ai_reader/models/ai_conversation.dart';
import 'package:ai_reader/models/reading_ai_context.dart';
import 'package:ai_reader/models/user_entry.dart';
import 'package:ai_reader/services/ai_service.dart';
import 'package:ai_reader/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const complete =
    'data: {"content":"answer"}\n\ndata: {"status":"completed","finish_reason":"stop"}\n\ndata: [DONE]\n\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    AiService.clientFactoryForTesting = null;
  });
  Stream<String> decode(String text, {bool legacy = false}) =>
      AiService.decodeStream(
        Stream.fromIterable(utf8.encode(text).map((byte) => [byte])),
        requireCompletion: !legacy,
      );

  test('complete UTF8 stream and explicit legacy DONE compatibility', () async {
    expect(await decode(complete).toList(), ['answer']);
    expect(
      await decode(
        'data: {"content":"原文"}\n\ndata: [DONE]\n\n',
        legacy: true,
      ).toList(),
      ['原文'],
    );
  });

  test(
    'EOF, length error, malformed event and missing completion never succeed',
    () async {
      for (final text in [
        'data: {"content":"partial"}\n\n',
        'data: {"content":"partial"}\n\ndata: [DONE]\n\n',
        'data: {"content":"partial"}\n\ndata: {"error":"truncated"}\n\n',
        'data: broken\n\n',
        'data: {"status":"completed","finish_reason":"stop"}\n\ndata: [DONE]\n\n',
      ]) {
        await expectLater(decode(text).toList(), throwsA(isA<Exception>()));
      }
      await expectLater(
        decode('data: {"content":"partial"}\n\n', legacy: true).toList(),
        throwsException,
      );
    },
  );

  test('cancel closes source and does not deliver completion', () async {
    var cancelled = false;
    var done = false;
    final source = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    final arrived = Completer<void>();
    final subscription = AiService.decodeStream(source.stream).listen(
      (_) {
        arrived.complete();
      },
      onDone: () {
        done = true;
      },
    );
    source.add(utf8.encode('data: {"content":"partial"}\n\n'));
    await arrived.future;
    await subscription.cancel();
    expect(cancelled, true);
    expect(done, false);
    await source.close();
  });

  test(
    '14 actual followup requests keep first evidence, book and mode; IDs are independent',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'synthetic',
        'auth_user_id': 'test-user',
      });
      await AuthService.init();
      final entry = UserEntry(
        id: 'trace',
        source: 'ai_explanation',
        bookId: 'book',
        bookTitle: 'First Book',
        chapterTitle: 'First chapter',
        originalText: 'First evidence',
        aiExplanation: 'First explanation',
        createdAt: DateTime(2026),
        metadataJson: jsonEncode({
          'book_author': 'Known Author',
          'explain_mode': 'argument',
          'reading_ai_context': {'contextBefore': 'Before original'},
        }),
      );
      final fixed = ReadingAiContext.fromEntry(entry);
      final requests = <Map<String, dynamic>>[];
      final ids = <String>{};
      AiService.clientFactoryForTesting = () => MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        ids.add(
          request.headers['X-Request-ID'] ?? request.headers['x-request-id']!,
        );
        return http.Response(
          complete,
          200,
          headers: {'x-zhidu-ai-protocol': '2'},
        );
      });
      final history = <AiMessage>[];
      for (var round = 0; round < 14; round++) {
        history.add(
          AiMessage(
            role: 'user',
            content: 'q$round',
            timestamp: DateTime.now(),
          ),
        );
        history.add(
          AiMessage(
            role: 'assistant',
            content: 'a$round',
            timestamp: DateTime.now(),
          ),
        );
        await AiService.chatStream(
          message: 'next',
          conversationHistory: history,
          readingContext: fixed,
        ).toList();
      }
      expect(ids, hasLength(14));
      for (final body in requests) {
        expect(body['selectedText'], 'First evidence');
        expect(body['initialAnswer'], 'First explanation');
        expect(body['bookTitle'], 'First Book');
        expect(body['bookAuthor'], 'Known Author');
        expect(body['mode'], 'argument');
        expect((body['history'] as List).length, lessThanOrEqualTo(24));
      }
    },
  );

  test(
    'old entries without context metadata retain known evidence, do not invent author',
    () {
      final entry = UserEntry(
        id: 'old',
        source: 'ai_question',
        originalText: 'old original',
        userInput: 'old question',
        aiExplanation: 'old answer',
        bookTitle: 'old book',
        createdAt: DateTime(2020),
      );
      final value = ReadingAiContext.fromEntry(entry).toJson();
      expect(value['selectedText'], 'old original');
      expect(value['initialQuestion'], 'old question');
      expect(value['bookAuthor'], '');
      expect(value['mode'], 'auto');
    },
  );

  test(
    'saved reader question restores its evidence scope without changing preview',
    () {
      final entry = UserEntry(
        id: 'question',
        source: 'ai_question',
        originalText: 'Long original preview',
        userInput: 'First question',
        aiExplanation: 'First answer',
        bookTitle: 'Book',
        createdAt: DateTime(2026),
        metadataJson: jsonEncode({
          'reading_ai_context': {
            'scope': 'chapter',
            'selectedText': '',
            'chapterText': 'Original chapter evidence',
            'pageText': 'Original page evidence',
          },
        }),
      );
      final context = ReadingAiContext.fromEntry(entry);
      expect(context.path, '/api/ai/reader-question');
      expect(context.toJson()['scope'], 'chapter');
      expect(context.toJson()['chapterText'], 'Original chapter evidence');
      expect(context.toJson()['initialQuestion'], 'First question');
      expect(context.toJson()['initialAnswer'], 'First answer');
      expect(entry.originalText, 'Long original preview');
    },
  );
}
