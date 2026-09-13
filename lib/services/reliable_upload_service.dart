import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'upload_revision.dart';

import 'bmob_api.dart';
import 'database_service.dart';
import '../config/local_diagnostics_mode.dart';

typedef UploadDatabaseProvider = Future<Database> Function();
typedef UploadClock = DateTime Function();
typedef UploadUserIdProvider = String? Function();
typedef UploadAuthProvider = bool Function();

class PendingUploadOperation {
  final String operationId;
  final String userId;
  final String entityType;
  final String entityId;
  final String operation;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final int generation;
  final int clientRevision;

  const PendingUploadOperation({
    required this.operationId,
    required this.userId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.createdAt,
    required this.retryCount,
    required this.generation,
    required this.clientRevision,
  });

  factory PendingUploadOperation.fromMap(Map<String, Object?> row) {
    final decoded = jsonDecode(row['payload_json']?.toString() ?? '{}');
    return PendingUploadOperation(
      operationId: row['operation_id']?.toString() ?? '',
      userId: row['user_id']?.toString() ?? '',
      entityType: row['entity_type']?.toString() ?? '',
      entityId: row['entity_id']?.toString() ?? '',
      operation: row['operation']?.toString() ?? '',
      payload: decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{},
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      retryCount: (row['retry_count'] as num?)?.toInt() ?? 0,
      generation: (row['generation'] as num?)?.toInt() ?? 1,
      clientRevision: (row['client_revision'] as num?)?.toInt() ?? 0,
    );
  }
}

abstract class ReliableUploadClient {
  Future<Map<String, dynamic>?> upsertTrace(
    String clientEntryId,
    Map<String, dynamic> payload,
  );

  Future<void> deleteTrace(String clientEntryId, Map<String, dynamic> version);

  Future<void> permanentlyDeleteBookData(String bookId);

  Future<void> upsertReadingProgress(Map<String, dynamic> payload);

  Future<void> deleteReadingProgress(
    String bookId,
    Map<String, dynamic> version,
  );

  Future<void> replaceLibraryBooks(List<Map<String, dynamic>> books);
}

class BmobReliableUploadClient implements ReliableUploadClient {
  const BmobReliableUploadClient();

  @override
  Future<Map<String, dynamic>?> upsertTrace(
    String clientEntryId,
    Map<String, dynamic> payload,
  ) {
    return BmobApi.instance.upsertUserEntryByClientId(clientEntryId, payload);
  }

  @override
  Future<void> deleteTrace(String clientEntryId, Map<String, dynamic> version) {
    return BmobApi.instance.deleteUserEntryByClientId(clientEntryId, version);
  }

  @override
  Future<void> permanentlyDeleteBookData(String bookId) {
    return BmobApi.instance.permanentlyDeleteBookData(bookId);
  }

  @override
  Future<void> upsertReadingProgress(Map<String, dynamic> payload) async {
    await BmobApi.instance.saveReadingProgress(
      bookId: payload['book_id']?.toString() ?? '',
      progress: (payload['progress'] as num?)?.toDouble() ?? 0,
      chapterIndex: payload['chapter_index']?.toString() ?? '0',
      scrollOffset: (payload['scroll_offset'] as num?)?.toDouble() ?? 0,
      cfi: payload['cfi']?.toString(),
      version: {
        'writer_id': payload['writer_id'],
        'client_revision': payload['client_revision'],
      },
    );
  }

  @override
  Future<void> deleteReadingProgress(
    String bookId,
    Map<String, dynamic> version,
  ) {
    return BmobApi.instance.deleteReadingProgress(bookId, version);
  }

  @override
  Future<void> replaceLibraryBooks(List<Map<String, dynamic>> books) {
    return BmobApi.instance.syncMcpLibraryBooks(books, replace: true);
  }
}

class ReliableUploadService {
  ReliableUploadService({
    UploadDatabaseProvider? databaseProvider,
    ReliableUploadClient? client,
    UploadClock? clock,
    UploadUserIdProvider? userIdProvider,
    UploadAuthProvider? isAuthenticated,
  }) : _databaseProvider = databaseProvider ?? (() => DatabaseService.database),
       _client = client ?? const BmobReliableUploadClient(),
       _clock = clock ?? (() => DateTime.now().toUtc()),
       _userIdProvider = userIdProvider ?? (() => BmobApi.instance.userId),
       _isAuthenticated =
           isAuthenticated ?? (() => BmobApi.instance.isLoggedIn);

  static final ReliableUploadService instance = ReliableUploadService();

  final UploadDatabaseProvider _databaseProvider;
  final ReliableUploadClient _client;
  final UploadClock _clock;
  final UploadUserIdProvider _userIdProvider;
  final UploadAuthProvider _isAuthenticated;
  Timer? _timer;
  Future<void>? _activeDrain;

  static const _libraryEntityId = '__library__';
  static const _baseRetryDelay = Duration(seconds: 5);
  static const _maxRetryDelay = Duration(minutes: 15);

  void start() {
    if (LocalDiagnosticsMode.enabled) return;
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(drain());
    });
    unawaited(drain());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> claimAnonymousOperations(String userId) async {
    if (LocalDiagnosticsMode.enabled) return;
    final normalized = userId.trim();
    if (normalized.isEmpty) return;
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      await txn.rawInsert(
        '''INSERT OR IGNORE INTO locally_deleted_books (user_id, book_id)
        SELECT ?, book_id FROM locally_deleted_books WHERE user_id = '' ''',
        [normalized],
      );
      await txn.delete('locally_deleted_books', where: "user_id = ''");
      await txn.rawInsert(
        '''INSERT OR IGNORE INTO upload_entity_revisions
        (user_id, entity_type, entity_id, last_revision, state_hash, book_id)
        SELECT ?, entity_type, entity_id, last_revision, state_hash, book_id
        FROM upload_entity_revisions WHERE user_id = '' ''',
        [normalized],
      );
      final rows = await txn.query(
        'pending_upload_operations',
        where: "user_id = ''",
        orderBy: 'created_at ASC',
      );
      for (final row in rows) {
        final pending = PendingUploadOperation.fromMap(row);
        await _enqueue(
          txn,
          userId: normalized,
          entityType: pending.entityType,
          entityId: pending.entityId,
          operation: pending.operation,
          payload: pending.payload,
        );
        await txn.delete(
          'pending_upload_operations',
          where: 'operation_id = ?',
          whereArgs: [pending.operationId],
        );
      }
    });
  }

  Future<String> enqueueTrace(
    DatabaseExecutor db, {
    required String userId,
    required String entityId,
    required String operation,
    Map<String, dynamic> payload = const {},
  }) {
    return _enqueue(
      db,
      userId: userId,
      entityType: 'trace',
      entityId: entityId,
      operation: operation,
      payload: payload,
    );
  }

  Future<String> enqueueReadingProgress(
    DatabaseExecutor db, {
    required String userId,
    required String bookId,
    required String operation,
    Map<String, dynamic> payload = const {},
  }) async {
    LocalDiagnosticsMode.requireBusinessWritesAllowed();
    if ((await db.query(
      'locally_deleted_books',
      where: 'user_id = ? AND book_id = ?',
      whereArgs: [userId, bookId],
    )).isNotEmpty) {
      throw StateError('Book data was permanently deleted');
    }
    return _enqueue(
      db,
      userId: userId,
      entityType: 'reading_progress',
      entityId: bookId,
      operation: operation,
      payload: payload,
    );
  }

  Future<String> enqueueLibrarySnapshot(
    DatabaseExecutor db, {
    required String userId,
    required List<Map<String, dynamic>> books,
  }) {
    return _enqueue(
      db,
      userId: userId,
      entityType: 'book',
      entityId: _libraryEntityId,
      operation: 'replace',
      payload: {'books': books},
    );
  }

  Future<void> enqueuePermanentBookDeletion(
    DatabaseExecutor db, {
    required String userId,
    required String bookId,
    required List<String> localTraceIds,
  }) async {
    LocalDiagnosticsMode.requireBusinessWritesAllowed();
    await db.insert('locally_deleted_books', {
      'user_id': userId,
      'book_id': bookId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final rows = await db.query(
      'pending_upload_operations',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    // A queued DELETE has no body, but its persistent revision retains book identity.
    final revisionRows = await db.query(
      'upload_entity_revisions',
      columns: ['entity_id'],
      where: "user_id = ? AND entity_type = 'trace' AND book_id = ?",
      whereArgs: [userId, bookId],
    );
    final traceIds = {
      ...localTraceIds,
      ...revisionRows.map((row) => row['entity_id'].toString()),
    };
    for (final row in rows) {
      final pending = PendingUploadOperation.fromMap(row);
      if ((pending.entityType == 'trace' &&
              (traceIds.contains(pending.entityId) ||
                  pending.payload['book_id'] == bookId)) ||
          (pending.entityType == 'reading_progress' &&
              pending.entityId == bookId)) {
        await db.delete(
          'pending_upload_operations',
          where: 'operation_id = ?',
          whereArgs: [pending.operationId],
        );
      }
    }
    await _enqueue(
      db,
      userId: userId,
      entityType: 'book',
      entityId: bookId,
      operation: 'purge',
      payload: {'book_id': bookId},
    );
  }

  Future<String> _enqueue(
    DatabaseExecutor db, {
    required String userId,
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    LocalDiagnosticsMode.requireBusinessWritesAllowed();
    final normalizedUserId = userId.trim();
    final existing = await db.query(
      'pending_upload_operations',
      where: 'user_id = ? AND entity_type = ? AND entity_id = ?',
      whereArgs: [normalizedUserId, entityType, entityId],
      limit: 1,
    );
    final now = _clock().toUtc().toIso8601String();
    final current = existing.isEmpty ? null : existing.first;
    var revision = 0;
    if (entityType == 'trace' || entityType == 'reading_progress') {
      final states = await db.query(
        'upload_entity_revisions',
        where: 'user_id = ? AND entity_type = ? AND entity_id = ?',
        whereArgs: [normalizedUserId, entityType, entityId],
      );
      final state = states.isEmpty ? null : states.single;
      final bookId = entityType == 'reading_progress'
          ? entityId
          : payload['book_id']?.toString() ?? state?['book_id']?.toString();
      if (bookId != null &&
          (await db.query(
            'locally_deleted_books',
            where: 'user_id = ? AND book_id = ?',
            whereArgs: [normalizedUserId, bookId],
          )).isNotEmpty) {
        throw StateError('Book data was permanently deleted');
      }
      final hash = uploadStateHash(operation, payload);
      final sameState = state?['state_hash'] == hash;
      if (sameState && current != null) {
        return current['operation_id']!.toString();
      }
      revision =
          ((state?['last_revision'] as num?)?.toInt() ?? 0) +
          (sameState ? 0 : 1);
      if (revision > 9007199254740991) {
        throw StateError('Upload revision exhausted');
      }
      await db.insert('upload_entity_revisions', {
        'user_id': normalizedUserId,
        'entity_type': entityType,
        'entity_id': entityId,
        'last_revision': revision,
        'state_hash': hash,
        'book_id': bookId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    final nextOperation = _coalesceOperation(
      current?['operation']?.toString(),
      operation,
    );
    final operationId = current?['operation_id']?.toString().isNotEmpty == true
        ? current!['operation_id']!.toString()
        : const Uuid().v4();
    final generation = ((current?['generation'] as num?)?.toInt() ?? 0) + 1;
    await db.insert('pending_upload_operations', {
      'operation_id': operationId,
      'user_id': normalizedUserId,
      'entity_type': entityType,
      'entity_id': entityId,
      'operation': nextOperation,
      'payload_json': jsonEncode(payload),
      'created_at': current?['created_at']?.toString() ?? now,
      'updated_at': now,
      'retry_count': 0,
      'last_error_at': null,
      'next_retry_at': now,
      'generation': generation,
      'client_revision': revision,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return operationId;
  }

  String _coalesceOperation(String? previous, String next) {
    if (next == 'delete') return 'delete';
    if (previous == 'create' && next == 'update') return 'create';
    if (previous == 'delete' && (next == 'create' || next == 'update')) {
      return 'create';
    }
    return next;
  }

  Future<void> drain() {
    if (LocalDiagnosticsMode.enabled) return Future<void>.value();
    final running = _activeDrain;
    if (running != null) return running;
    final future = _drainInternal();
    _activeDrain = future;
    return future.whenComplete(() {
      if (identical(_activeDrain, future)) _activeDrain = null;
    });
  }

  Future<void> _drainInternal() async {
    final userId = _userIdProvider()?.trim() ?? '';
    if (!_isAuthenticated() || userId.isEmpty) return;
    final db = await _databaseProvider();
    final writerId = (await db.query(
      'upload_writer',
    )).single['writer_id']!.toString();
    final now = _clock().toUtc().toIso8601String();
    final rows = await db.query(
      'pending_upload_operations',
      where: 'user_id = ? AND next_retry_at <= ?',
      whereArgs: [userId, now],
      orderBy: 'created_at ASC, operation_id ASC',
      limit: 50,
    );
    for (final row in rows) {
      if (!_isAuthenticated() || _userIdProvider()?.trim() != userId) break;
      final pending = PendingUploadOperation.fromMap(row);
      final current = await db.query(
        'pending_upload_operations',
        columns: ['generation'],
        where: 'operation_id = ?',
        whereArgs: [pending.operationId],
      );
      if (current.isEmpty ||
          current.single['generation'] != pending.generation) {
        continue;
      }
      if (!_isAuthenticated() || _userIdProvider()?.trim() != userId) break;
      final startedAt = _clock();
      try {
        final remote = await _upload(pending, writerId);
        if (pending.entityType == 'trace' && remote != null) {
          final remoteId = remote['id']?.toString() ?? '';
          if (remoteId.isNotEmpty) {
            await db.update(
              'user_entries',
              {'bmob_id': remoteId},
              where: 'id = ?',
              whereArgs: [pending.entityId],
            );
          }
        }
        await db.delete(
          'pending_upload_operations',
          where: 'operation_id = ? AND generation = ?',
          whereArgs: [pending.operationId, pending.generation],
        );
        _log(pending, 'success', startedAt);
      } catch (_) {
        final retryCount = pending.retryCount + 1;
        final failedAt = _clock().toUtc();
        await db.update(
          'pending_upload_operations',
          {
            'retry_count': retryCount,
            'last_error_at': failedAt.toIso8601String(),
            'next_retry_at': failedAt
                .add(_retryDelay(retryCount))
                .toIso8601String(),
            'updated_at': failedAt.toIso8601String(),
          },
          where: 'operation_id = ? AND generation = ?',
          whereArgs: [pending.operationId, pending.generation],
        );
        _log(pending, 'retry_scheduled', startedAt, retryCount: retryCount);
      }
    }
  }

  Future<Map<String, dynamic>?> _upload(
    PendingUploadOperation pending,
    String writerId,
  ) async {
    switch (pending.entityType) {
      case 'trace':
        final version = {
          'writer_id': writerId,
          'client_revision': pending.clientRevision,
        };
        if (pending.operation == 'delete') {
          await _client.deleteTrace(pending.entityId, version);
          return null;
        }
        return _client.upsertTrace(pending.entityId, {
          ...pending.payload,
          ...version,
        });
      case 'reading_progress':
        final version = {
          'writer_id': writerId,
          'client_revision': pending.clientRevision,
        };
        if (pending.operation == 'delete') {
          await _client.deleteReadingProgress(pending.entityId, version);
        } else {
          await _client.upsertReadingProgress({...pending.payload, ...version});
        }
        return null;
      case 'book':
        if (pending.operation == 'purge') {
          await _client.permanentlyDeleteBookData(pending.entityId);
          return null;
        }
        final rawBooks = pending.payload['books'];
        final books = rawBooks is List
            ? rawBooks
                  .whereType<Map>()
                  .map((book) => Map<String, dynamic>.from(book))
                  .toList(growable: false)
            : <Map<String, dynamic>>[];
        await _client.replaceLibraryBooks(books);
        return null;
      default:
        throw StateError('Unsupported pending entity type');
    }
  }

  Duration _retryDelay(int retryCount) {
    final exponent = (retryCount - 1).clamp(0, 8);
    final milliseconds = _baseRetryDelay.inMilliseconds * (1 << exponent);
    return Duration(
      milliseconds: milliseconds.clamp(
        _baseRetryDelay.inMilliseconds,
        _maxRetryDelay.inMilliseconds,
      ),
    );
  }

  void _log(
    PendingUploadOperation pending,
    String status,
    DateTime startedAt, {
    int? retryCount,
  }) {
    if (!kDebugMode) return;
    final latency = _clock().difference(startedAt).inMilliseconds;
    debugPrint(
      '[ReliableUpload] operation_id=${pending.operationId} '
      'entity_type=${pending.entityType} operation=${pending.operation} '
      'status=$status retry_count=${retryCount ?? pending.retryCount} '
      'latency_ms=$latency',
    );
  }
}
