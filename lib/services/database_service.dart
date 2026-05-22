import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show sqfliteFfiInit, databaseFactoryFfi;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../config/constants.dart';

class DatabaseService {
  static Database? _db;

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
        created_at TEXT NOT NULL,
        updated_at TEXT DEFAULT '',
        bmob_id TEXT DEFAULT ''
      )
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          "ALTER TABLE books ADD COLUMN format TEXT NOT NULL DEFAULT 'epub'");
    }
    if (oldVersion < 3) {
      await db.execute("ALTER TABLE notes ADD COLUMN selectedText TEXT");
      await db.execute("ALTER TABLE notes ADD COLUMN chapterTitle TEXT");
    }
    if (oldVersion < 4) {
      await db.execute("ALTER TABLE books ADD COLUMN user_id TEXT DEFAULT ''");
      await db.execute("ALTER TABLE books ADD COLUMN updated_at TEXT DEFAULT ''");
      await db.execute("ALTER TABLE highlights ADD COLUMN user_id TEXT DEFAULT ''");
      await db.execute("ALTER TABLE highlights ADD COLUMN updated_at TEXT DEFAULT ''");
      await db.execute("ALTER TABLE notes ADD COLUMN user_id TEXT DEFAULT ''");
      await db.execute("ALTER TABLE notes ADD COLUMN updated_at TEXT DEFAULT ''");
      await db.execute("ALTER TABLE reading_progress ADD COLUMN user_id TEXT DEFAULT ''");
      await db.execute("ALTER TABLE reading_progress ADD COLUMN updated_at TEXT DEFAULT ''");
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
      await db.execute("ALTER TABLE books ADD COLUMN chapterTitles TEXT DEFAULT ''");
    }
    if (oldVersion < 9) {
      await _addColumnIfMissing(db, 'bookmarks', 'user_id', "TEXT DEFAULT ''");
      await _addColumnIfMissing(db, 'bookmarks', 'updated_at', "TEXT DEFAULT ''");
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
          created_at TEXT NOT NULL,
          updated_at TEXT DEFAULT '',
          bmob_id TEXT DEFAULT ''
        )
      ''');
    }
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
