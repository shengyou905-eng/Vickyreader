import 'package:flutter_test/flutter_test.dart';
import 'package:ai_reader/models/ai_conversation.dart';

void main() {
  group('AiMessage', () {
    test('toApiFormat returns correct role and content', () {
      final msg = AiMessage(
        role: 'user',
        content: '这段话是什么意思？',
        timestamp: DateTime(2026, 5, 21),
      );

      final apiFormat = msg.toApiFormat();

      expect(apiFormat['role'], 'user');
      expect(apiFormat['content'], '这段话是什么意思？');
      expect(apiFormat.length, 2);
    });

    test('toMap includes timestamp as ISO string', () {
      final timestamp = DateTime(2026, 5, 21, 14, 30);
      final msg = AiMessage(
        role: 'assistant',
        content: '这是对存在主义的探讨...',
        timestamp: timestamp,
      );

      final map = msg.toMap();

      expect(map['role'], 'assistant');
      expect(map['content'], '这是对存在主义的探讨...');
      expect(map['timestamp'], '2026-05-21T14:30:00.000');
    });

    test('fromMap reverses toMap', () {
      final original = AiMessage(
        role: 'user',
        content: '追问：能详细展开吗？',
        timestamp: DateTime(2026, 5, 21),
      );

      final restored = AiMessage.fromMap(original.toMap());

      expect(restored.role, original.role);
      expect(restored.content, original.content);
      expect(restored.timestamp, original.timestamp);
    });

    test('toMap → fromMap roundtrip preserves data', () {
      final messages = [
        AiMessage(role: 'user', content: '问题1', timestamp: DateTime(2026, 1, 1)),
        AiMessage(role: 'assistant', content: '回答1', timestamp: DateTime(2026, 1, 1, 0, 0, 1)),
        AiMessage(role: 'user', content: '问题2', timestamp: DateTime(2026, 1, 1, 0, 0, 2)),
      ];

      for (final original in messages) {
        final roundtripped = AiMessage.fromMap(original.toMap());
        expect(roundtripped.role, original.role);
        expect(roundtripped.content, original.content);
      }
    });
  });

  group('AiConversation', () {
    test('constructor assigns all fields', () {
      final messages = [
        AiMessage(role: 'user', content: '你好', timestamp: DateTime(2026, 5, 21)),
      ];
      final createdAt = DateTime(2026, 5, 21);
      final updatedAt = DateTime(2026, 5, 21, 14, 30);

      final conv = AiConversation(
        id: 'conv-001',
        bookId: 'book-abc',
        messages: messages,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(conv.id, 'conv-001');
      expect(conv.bookId, 'book-abc');
      expect(conv.messages, same(messages));
      expect(conv.createdAt, createdAt);
      expect(conv.updatedAt, updatedAt);
    });
  });
}
