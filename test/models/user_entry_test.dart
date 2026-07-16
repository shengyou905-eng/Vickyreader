import 'package:ai_reader/models/user_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('important flag survives the local database map round trip', () {
    final entry = UserEntry(
      id: 'entry-1',
      source: 'thought',
      bookId: 'book-1',
      bookTitle: '第二性',
      isImportant: true,
      createdAt: DateTime.utc(2026, 7, 16),
    );

    final restored = UserEntry.fromMap(entry.toMap());

    expect(restored.isImportant, isTrue);
    expect(restored.bookId, 'book-1');
  });
}
