import 'ai_conversation.dart';

class XiaouConversationSummary {
  final String id;
  final String kind;
  final String title;
  final String bookId;
  final String bookTitle;
  final int messageCount;
  final String lastMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  const XiaouConversationSummary({
    required this.id,
    this.kind = 'chat',
    required this.title,
    required this.bookId,
    required this.bookTitle,
    required this.messageCount,
    required this.lastMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  factory XiaouConversationSummary.fromJson(Map<String, dynamic> json) {
    return XiaouConversationSummary(
      id: json['id']?.toString() ?? '',
      kind: json['kind']?.toString() == 'xiaou_asks' ? 'xiaou_asks' : 'chat',
      title: json['title']?.toString().trim() ?? '',
      bookId: json['book_id']?.toString() ?? '',
      bookTitle: json['book_title']?.toString() ?? '',
      messageCount: int.tryParse(json['message_count']?.toString() ?? '') ?? 0,
      lastMessage: json['last_message']?.toString().trim() ?? '',
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
    );
  }

  String get displayTitle => title.isEmpty ? '和小U说话' : title;

  bool get isXiaouAsks => kind == 'xiaou_asks';
}

class XiaouConversationThread {
  final XiaouConversationSummary conversation;
  final List<AiMessage> messages;

  const XiaouConversationThread({
    required this.conversation,
    required this.messages,
  });

  factory XiaouConversationThread.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List? ?? const [];
    return XiaouConversationThread(
      conversation: XiaouConversationSummary.fromJson(json),
      messages: rawMessages
          .whereType<Map>()
          .map(
            (message) => AiMessage(
              role: message['role']?.toString() == 'assistant'
                  ? 'assistant'
                  : 'user',
              content: message['content']?.toString() ?? '',
              timestamp: _date(message['created_at']),
            ),
          )
          .where((message) => message.content.trim().isNotEmpty)
          .toList(growable: false),
    );
  }
}

DateTime _date(Object? value) {
  return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now().toUtc();
}
