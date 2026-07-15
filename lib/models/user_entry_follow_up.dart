class UserEntryFollowUp {
  final String id;
  final String entryId;
  final String question;
  final String answer;
  final DateTime createdAt;

  const UserEntryFollowUp({
    required this.id,
    required this.entryId,
    required this.question,
    required this.answer,
    required this.createdAt,
  });

  factory UserEntryFollowUp.fromRemote(Map<String, dynamic> row) {
    return UserEntryFollowUp(
      id: row['id']?.toString() ?? '',
      entryId: row['entry_id']?.toString() ?? '',
      question: row['question']?.toString() ?? '',
      answer: row['answer']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }
}
