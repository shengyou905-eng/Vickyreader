import 'package:ai_reader/models/ai_conversation.dart';
import 'package:ai_reader/services/reading_history.dart';
import 'package:flutter_test/flutter_test.dart';

AiMessage message(String role, String content) => AiMessage(
  role: role,
  content: content,
  timestamp: DateTime.utc(2026, 10, 19),
);

void main() {
  test(
    'whole turns keep older corrections and unresolved questions in order',
    () {
      final history = <AiMessage>[
        message('assistant', 'orphan'),
        message('user', 'failed question'),
        for (var i = 0; i < 20; i++) ...[
          message(
            'user',
            i == 2
                ? '纠正：我指的是另一个条件'
                : i == 3
                ? '未解决：证据是否充分'
                : 'q$i',
          ),
          message('assistant', 'a$i'),
        ],
        message('user', 'current unanswered turn'),
      ];
      final selected = selectReadingHistory(history);
      expect(selected, hasLength(24));
      expect(selected.any((m) => m.content.startsWith('纠正：')), isTrue);
      expect(selected.any((m) => m.content.startsWith('未解决：')), isTrue);
      expect(selected.last.content, 'a19');
      expect(selected.any((m) => m.content == 'orphan'), isFalse);
      expect(selected.any((m) => m.content == 'failed question'), isFalse);
      expect(
        selected.any((m) => m.content == 'current unanswered turn'),
        isFalse,
      );
      for (var i = 0; i < selected.length; i += 2) {
        expect(selected[i].role, 'user');
        expect(selected[i + 1].role, 'assistant');
      }
    },
  );

  test(
    'budget drops whole turns, not half answers, and keeps inputs unchanged',
    () {
      final history = [
        message('user', 'older'),
        message('assistant', 'older answer'),
        message('user', 'x' * 8000),
        message('assistant', 'y' * 8000),
        message('user', 'newest'),
        message('assistant', 'answer'),
      ];
      final original = history.map((m) => m.content).toList();
      final selected = selectReadingHistory(history, maxCharacters: 50);
      expect(selected.map((m) => m.content), [
        'older',
        'older answer',
        'newest',
        'answer',
      ]);
      expect(history.map((m) => m.content), original);
      expect(selectReadingHistory(history, maxTurns: 0), isEmpty);
      expect(selectReadingHistory(history, maxCharacters: 0), isEmpty);
    },
  );

  test(
    'unpaired failed turns and empty stream placeholders never become history',
    () {
      final selected = selectReadingHistory([
        message('user', 'failed'),
        message('assistant', ''),
        message('user', 'successful'),
        message('assistant', 'complete answer'),
        message('user', 'in flight'),
        message('assistant', ''),
      ]);
      expect(selected.map((m) => m.content), ['successful', 'complete answer']);
    },
  );

  test(
    'bounded memory repeatedly retains explicit early concerns after 14 rounds',
    () {
      var history = <AiMessage>[];
      for (var i = 0; i < 14; i++) {
        history = selectReadingHistory([
          ...history,
          message(
            'user',
            i == 1
                ? 'Correction: I meant the original text'
                : i == 2
                ? 'Unresolved evidence question'
                : 'q$i',
          ),
          message('assistant', 'a$i'),
        ]);
      }
      expect(history.length, 24);
      expect(history.any((m) => m.content.startsWith('Correction:')), isTrue);
      expect(history.any((m) => m.content.startsWith('Unresolved')), isTrue);
      expect(history.last.content, 'a13');
    },
  );
}
