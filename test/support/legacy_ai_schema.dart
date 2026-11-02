import 'package:sqflite/sqflite.dart';

/// AI history existed before the queue-only v14/v15/v16 test fixtures.
/// Include those legacy tables when exercising the complete upgrade chain.
Future<void> createLegacyAiHistoryTables(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE ai_messages (
    id TEXT PRIMARY KEY, bookId TEXT NOT NULL, role TEXT NOT NULL,
    content TEXT NOT NULL, timestamp TEXT NOT NULL)''');
  await db.execute('''CREATE TABLE user_entry_follow_ups (
    id TEXT PRIMARY KEY, entry_id TEXT NOT NULL, question TEXT NOT NULL,
    answer TEXT NOT NULL, created_at TEXT NOT NULL, remote_id TEXT DEFAULT '',
    remote_synced INTEGER NOT NULL DEFAULT 0)''');
}
