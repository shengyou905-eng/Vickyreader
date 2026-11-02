import '../models/ai_conversation.dart';

const readingPromptVersion = 'xiaou-reading-v4.20261020';

/// A bounded discussion window, not a source of book evidence.
List<AiMessage> selectReadingHistory(
  Iterable<AiMessage> messages, {
  int maxTurns = 12,
  int maxCharacters = 32000,
}) {
  final turns = <List<AiMessage>>[];
  AiMessage? question;
  for (final message in messages) {
    if (message.content.trim().isEmpty) continue;
    if (message.role == 'user') {
      question = message;
    } else if (message.role == 'assistant' && question != null) {
      turns.add([question, message]);
      question = null;
    } else {
      question = null;
    }
  }
  final chosen = <int>{};
  var remaining = maxCharacters;
  bool take(int index) {
    if (index < 0 || chosen.contains(index) || chosen.length >= maxTurns) {
      return false;
    }
    final size = turns[index].fold<int>(
      0,
      (sum, message) => sum + message.content.trim().length,
    );
    if (size > remaining) return false;
    chosen.add(index);
    remaining -= size;
    return true;
  }

  for (var i = turns.length - 1; i >= 0 && i >= turns.length - 6; i--) {
    take(i);
  }
  final important = RegExp(
    r'纠正|更正|我指的是|不是这个意思|还没回答|尚未回答|未解决|仍不明白|还不明白|correction|i meant|unanswered|unresolved|still unclear',
    caseSensitive: false,
  );
  var priority = 0;
  for (var i = turns.length - 1; i >= 0 && priority < 2; i--) {
    if (important.hasMatch(turns[i][0].content) && take(i)) priority++;
  }
  for (var i = turns.length - 1; i >= 0; i--) {
    take(i);
  }
  final ordered = chosen.toList()..sort();
  return [for (final index in ordered) ...turns[index]];
}
