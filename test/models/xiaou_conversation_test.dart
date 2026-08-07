import 'package:ai_reader/models/xiaou_conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('conversation thread restores ordered messages', () {
    final thread = XiaouConversationThread.fromJson({
      'id': 'conversation-1',
      'title': '为什么我总在这里停留？',
      'message_count': 2,
      'created_at': '2026-07-31T10:00:00.000Z',
      'updated_at': '2026-07-31T10:01:00.000Z',
      'messages': [
        {
          'role': 'user',
          'content': '这几段话之间有什么联系？',
          'created_at': '2026-07-31T10:00:00.000Z',
        },
        {
          'role': 'assistant',
          'content': '它们都在追问主体如何形成。',
          'created_at': '2026-07-31T10:01:00.000Z',
        },
      ],
    });

    expect(thread.conversation.id, 'conversation-1');
    expect(thread.conversation.messageCount, 2);
    expect(thread.messages, hasLength(2));
    expect(thread.messages.first.role, 'user');
    expect(thread.messages.last.role, 'assistant');
  });

  test('empty title has a calm fallback', () {
    final conversation = XiaouConversationSummary.fromJson({
      'id': 'conversation-2',
      'title': '',
      'created_at': '2026-07-31T10:00:00.000Z',
      'updated_at': '2026-07-31T10:00:00.000Z',
    });

    expect(conversation.displayTitle, '和小U说话');
  });

  test('xiaou asks conversation keeps its independent identity', () {
    final conversation = XiaouConversationSummary.fromJson({
      'id': 'conversation-3',
      'kind': 'xiaou_asks',
      'title': '小U问我',
      'created_at': '2026-08-07T10:00:00.000Z',
      'updated_at': '2026-08-07T10:00:00.000Z',
    });

    expect(conversation.isXiaouAsks, isTrue);
    expect(conversation.displayTitle, '小U问我');
  });
}
