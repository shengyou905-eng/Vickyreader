class AiMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;

  AiMessage({
    required this.role,
    required this.content,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'role': role,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory AiMessage.fromMap(Map<String, dynamic> map) {
    return AiMessage(
      role: map['role'] as String,
      content: map['content'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }

  Map<String, String> toApiFormat() {
    return {'role': role, 'content': content};
  }
}
