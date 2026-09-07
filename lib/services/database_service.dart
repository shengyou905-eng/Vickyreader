import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show sqfliteFfiInit, databaseFactoryFfi;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../config/constants.dart';
import 'upload_revision.dart';

class DatabaseService {
  static Database? _db;

  @visibleForTesting
  static Future<Database> openForTesting(String path) async {
    _db = await openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, AppConstants.dbName);
    return openDatabase(
      dbPath,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books (
        id TEXT PRIMARY KEY,
        user_id TEXT DEFAULT '',
        title TEXT NOT NULL,
        author TEXT NOT NULL,
        coverPath TEXT,
        filePath TEXT NOT NULL,
        format TEXT NOT NULL DEFAULT 'epub',
        description TEXT,
        addedAt TEXT NOT NULL,
        lastOpenedAt TEXT NOT NULL,
        readingProgress REAL DEFAULT 0.0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        chapterTitles TEXT DEFAULT '',
        updated_at TEXT DEFAULT '',
        bmob_id TEXT DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE highlights (
        id TEXT PRIMARY KEY,
        user_id TEXT DEFAULT '',
        bookId TEXT NOT NULL,
        chapterIndex TEXT NOT NULL,
        selectedText TEXT NOT NULL,
        contextBefore TEXT,
        contextAfter TEXT,
        startOffset INTEGER NOT NULL,
        endOffset INTEGER NOT NULL,
        color TEXT DEFAULT '#B39DDB',
        note TEXT,
        createdAt TEXT NOT NULL,
        updated_at TEXT DEFAULT '',
        bmob_id TEXT DEFAULT '',
        FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        user_id TEXT DEFAULT '',
        bookId TEXT NOT NULL,
        chapterIndex TEXT,
        selectedText TEXT,
        chapterTitle TEXT,
        content TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        updated_at TEXT DEFAULT '',
        bmob_id TEXT DEFAULT '',
        FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE ai_messages (
        id TEXT PRIMARY KEY,
        bookId TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE reading_progress (
        bookId TEXT PRIMARY KEY,
        user_id TEXT DEFAULT '',
        bmob_id TEXT DEFAULT '',
        chapterIndex TEXT NOT NULL,
        scrollOffset REAL DEFAULT 0.0,
        updatedAt TEXT NOT NULL,
        updated_at TEXT DEFAULT '',
        FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE bookmarks (
        id TEXT PRIMARY KEY,
        user_id TEXT DEFAULT '',
        bookId TEXT NOT NULL,
        chapterIndex TEXT NOT NULL,
        chapterTitle TEXT NOT NULL,
        snippet TEXT NOT NULL,
        scrollOffset REAL DEFAULT 0.0,
        progress REAL DEFAULT 0.0,
        createdAt TEXT NOT NULL,
        updated_at TEXT DEFAULT '',
        bmob_id TEXT DEFAULT '',
        FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE user_entries (
        id TEXT PRIMARY KEY,
        user_id TEXT DEFAULT '',
        source TEXT NOT NULL,
        book_id TEXT DEFAULT '',
        book_title TEXT DEFAULT '',
        chapter_index TEXT DEFAULT '',
        chapter_title TEXT DEFAULT '',
        original_text TEXT DEFAULT '',
        user_input TEXT DEFAULT '',
        ai_explanation TEXT DEFAULT '',
        auto_tags TEXT DEFAULT '',
        auto_summary TEXT DEFAULT '',
        metadata_json TEXT DEFAULT '',
        embedding TEXT DEFAULT '',
        is_important INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT DEFAULT '',
        bmob_id TEXT DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE free_notes (
        id TEXT PRIMARY KEY,
        user_id TEXT DEFAULT '',
        title TEXT DEFAULT '',
        content TEXT NOT NULL,
        xiaou_authorized INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE user_entry_follow_ups (
        id TEXT PRIMARY KEY,
        entry_id TEXT NOT NULL,
        question TEXT NOT NULL,
        answer TEXT NOT NULL,
        created_at TEXT NOT NULL,
        remote_id TEXT DEFAULT '',
        remote_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_user_entry_follow_ups_entry_created
      ON user_entry_follow_ups(entry_id, created_at ASC)
    ''');
    await _createPendingUploadTable(db);
    await createUploadRevisionSchema(db);
    await createProgressRevisionSchema(db);
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE books ADD COLUMN format TEXT NOT NULL DEFAULT 'epub'",
      );
    }
    if (oldVersion < 3) {
      await db.execute("ALTER TABLE notes ADD COLUMN selectedText TEXT");
      await db.execute("ALTER TABLE notes ADD COLUMN chapterTitle TEXT");
    }
    if (oldVersion < 4) {
      await db.execute("ALTER TABLE books ADD COLUMN user_id TEXT DEFAULT ''");
      await db.execute(
        "ALTER TABLE books ADD COLUMN updated_at TEXT DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE highlights ADD COLUMN user_id TEXT DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE highlights ADD COLUMN updated_at TEXT DEFAULT ''",
      );
      await db.execute("ALTER TABLE notes ADD COLUMN user_id TEXT DEFAULT ''");
      await db.execute(
        "ALTER TABLE notes ADD COLUMN updated_at TEXT DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE reading_progress ADD COLUMN user_id TEXT DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE reading_progress ADD COLUMN updated_at TEXT DEFAULT ''",
      );
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE bookmarks (
          id TEXT PRIMARY KEY,
          bookId TEXT NOT NULL,
          chapterIndex TEXT NOT NULL,
          chapterTitle TEXT NOT NULL,
          snippet TEXT NOT NULL,
          scrollOffset REAL DEFAULT 0.0,
          progress REAL DEFAULT 0.0,
          createdAt TEXT NOT NULL,
          FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 6) {
      await db.execute(
        "ALTER TABLE books ADD COLUMN chapterTitles TEXT DEFAULT ''",
      );
    }
    if (oldVersion < 9) {
      await _addColumnIfMissing(db, 'bookmarks', 'user_id', "TEXT DEFAULT ''");
      await _addColumnIfMissing(
        db,
        'bookmarks',
        'updated_at',
        "TEXT DEFAULT ''",
      );
      await _addColumnIfMissing(db, 'bookmarks', 'bmob_id', "TEXT DEFAULT ''");
      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_entries (
          id TEXT PRIMARY KEY,
          user_id TEXT DEFAULT '',
          source TEXT NOT NULL,
          book_id TEXT DEFAULT '',
          book_title TEXT DEFAULT '',
          chapter_index TEXT DEFAULT '',
          chapter_title TEXT DEFAULT '',
          original_text TEXT DEFAULT '',
          user_input TEXT DEFAULT '',
          ai_explanation TEXT DEFAULT '',
          auto_tags TEXT DEFAULT '',
          auto_summary TEXT DEFAULT '',
          metadata_json TEXT DEFAULT '',
          embedding TEXT DEFAULT '',
          is_important INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT DEFAULT '',
          bmob_id TEXT DEFAULT ''
        )
      ''');
    }
    if (oldVersion < 10) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS free_notes (
          id TEXT PRIMARY KEY,
          user_id TEXT DEFAULT '',
          content TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 11) {
      await _addColumnIfMissing(db, 'free_notes', 'title', "TEXT DEFAULT ''");
      await _addColumnIfMissing(
        db,
        'free_notes',
        'xiaou_authorized',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 12) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_entry_follow_ups (
          id TEXT PRIMARY KEY,
          entry_id TEXT NOT NULL,
          question TEXT NOT NULL,
          answer TEXT NOT NULL,
          created_at TEXT NOT NULL,
          remote_id TEXT DEFAULT '',
          remote_synced INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_user_entry_follow_ups_entry_created
        ON user_entry_follow_ups(entry_id, created_at ASC)
      ''');
    }
    if (oldVersion < 13) {
      await _addColumnIfMissing(
        db,
        'user_entries',
        'is_important',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 14) {
      await _createPendingUploadTable(db);
    }
    if (oldVersion < 15) {
      await _addColumnIfMissing(
        db,
        'books',
        'is_archived',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 16) {
      await createUploadRevisionSchema(db);
    }
    if (oldVersion < 17) {
      await createProgressRevisionSchema(db);
    }
  }

  static Future<void> createProgressRevisionSchema(Database db) async {
    await db.execute('''UPDATE pending_upload_operations
      SET client_revision = generation
      WHERE entity_type = 'reading_progress' AND client_revision = 0''');
    final pending = await db.query(
      'pending_upload_operations',
      where: "entity_type = 'reading_progress'",
    );
    for (final row in pending) {
      Map<String, dynamic> payload;
      try {
        payload = Map<String, dynamic>.from(
          jsonDecode(row['payload_json'] as String) as Map,
        );
      } catch (_) {
        throw StateError(
          'Invalid pending upload payload; migration was not applied',
        );
      }
      await db.insert('upload_entity_revisions', {
        'user_id': row['user_id'],
        'entity_type': 'reading_progress',
        'entity_id': row['entity_id'],
        'last_revision': row['client_revision'],
        'state_hash': uploadStateHash(row['operation'] as String, payload),
        'book_id': row['entity_id'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> createUploadRevisionSchema(Database db) async {
    await _addColumnIfMissing(
      db,
      'pending_upload_operations',
      'client_revision',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS upload_writer (
      id INTEGER PRIMARY KEY CHECK (id = 1), writer_id TEXT NOT NULL)''');
    await db.insert('upload_writer', {
      'id': 1,
      'writer_id': const Uuid().v4(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.execute('''CREATE TABLE IF NOT EXISTS upload_entity_revisions (
      user_id TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
      last_revision INTEGER NOT NULL, state_hash TEXT, book_id TEXT,
      PRIMARY KEY (user_id, entity_type, entity_id))''');
    await db.execute('''CREATE TABLE IF NOT EXISTS locally_deleted_books (
      user_id TEXT NOT NULL, book_id TEXT NOT NULL,
      PRIMARY KEY (user_id, book_id))''');
    await db.execute(
      '''UPDATE pending_upload_operations SET client_revision = generation
      WHERE entity_type = 'trace' AND client_revision = 0''',
    );
    final pending = await db.query(
      'pending_upload_operations',
      where: "entity_type = 'trace'",
    );
    for (final row in pending) {
      Map<String, dynamic> payload;
      try {
        payload = Map<String, dynamic>.from(
          jsonDecode(row['payload_json'] as String) as Map,
        );
      } catch (_) {
        throw StateError(
          'Invalid pending upload payload; migration was not applied',
        );
      }
      await db.insert('upload_entity_revisions', {
        'user_id': row['user_id'],
        'entity_type': 'trace',
        'entity_id': row['entity_id'],
        'last_revision': row['client_revision'],
        'state_hash': uploadStateHash(row['operation'] as String, payload),
        'book_id': payload['book_id'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> _createPendingUploadTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_upload_operations (
        operation_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL DEFAULT '',
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload_json TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error_at TEXT,
        next_retry_at TEXT NOT NULL,
        generation INTEGER NOT NULL DEFAULT 1,
        UNIQUE(user_id, entity_type, entity_id)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pending_upload_due
      ON pending_upload_operations(user_id, next_retry_at, created_at)
    ''');
  }

  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((c) => c['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }
}
