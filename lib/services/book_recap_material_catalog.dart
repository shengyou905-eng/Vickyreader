import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'auth_session_scope.dart';
import 'book_recap_client_contract.dart';
import 'book_recap_local_guard.dart';

class RecapBookChoice {
  final String id, title;
  const RecapBookChoice({required this.id, required this.title});
}

class RecapMaterialFollowUp {
  final String? remoteId;
  final String question;
  const RecapMaterialFollowUp({this.remoteId, required this.question});
}

class RecapMaterialChoice {
  final String localId;
  final String? remoteId;
  final String kind;

  /// Complete original text, not a truncated or deduplicated display snippet.
  final String preview;
  final String userText;
  final List<RecapMaterialFollowUp> followUps;

  /// A fixed, display-safe label. Non-null choices must not be selectable.
  final String? unavailableReason;

  RecapMaterialChoice({
    required this.localId,
    this.remoteId,
    required this.kind,
    required this.preview,
    required this.userText,
    required List<RecapMaterialFollowUp> followUps,
    this.unavailableReason,
  }) : followUps = List.unmodifiable(followUps);
}

class RecapMaterialCatalogException extends RecapClientException {
  const RecapMaterialCatalogException(super.code);

  @override
  String get message => switch (code) {
    'LOCAL_RESTORE_UNAVAILABLE' =>
      '\u672c\u673a\u7f3a\u5c11\u53ef\u6838\u9a8c\u7684\u539f\u59cb\u8bb0\u5f55\uff0c\u6682\u4e0d\u80fd\u6062\u590d\u8fd9\u4efd\u9009\u62e9\uff1b\u4e0d\u4f1a\u81ea\u52a8\u4e0b\u8f7d\u3002',
    'LOCAL_CATALOG_UNAVAILABLE' =>
      '\u6682\u65f6\u65e0\u6cd5\u6838\u9a8c\u672c\u5730\u6750\u6599\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5\u3002',
    _ => super.message,
  };
}

/// Read-only, request-local projections. No book service, network, or body cache.
/// A catalog result is not authorization: consumers must still use the guard
/// when confirming/generating. All limits reject, never silently truncate.
class BookRecapMaterialCatalog {
  static const maxBooks = 200;
  static const maxBookScanEntries = 4000;
  static const maxMaterials = 320;
  static const maxFollowUpRows = 640;
  static const maxTotalFollowUpRows = 2560;
  static const maxPayloadBytes = 512 * 1024;
  static const _sources = [
    'highlight',
    'thought',
    'manual',
    'ai_explanation',
    'ai_question',
  ];
  static const _columns = [
    'id',
    'bmob_id',
    'source',
    'original_text',
    'user_input',
    'metadata_json',
  ];

  final Future<Database> Function() database;
  final BookRecapLocalGuard _guard;

  BookRecapMaterialCatalog(this.database)
    : _guard = BookRecapLocalGuard(database);

  Future<List<RecapBookChoice>> books(AuthSessionScope session) =>
      _read(session, (db, owner) async {
        final rows = await db.query(
          'user_entries',
          columns: ['book_id', 'book_title', 'source', 'metadata_json'],
          where: '''user_id = ? AND book_id IS NOT NULL AND book_id <> ''
            AND NOT EXISTS (SELECT 1 FROM locally_deleted_books d
              WHERE d.user_id = ? AND d.book_id = user_entries.book_id)''',
          whereArgs: [owner, owner],
          orderBy: 'created_at DESC, id ASC',
          limit: maxBookScanEntries + 1,
        );
        _count(rows.length, maxBookScanEntries);
        final budget = _CatalogBudget();
        final choices = <String, RecapBookChoice>{};
        for (final row in rows) {
          budget.add(row);
          if (!_publicEntry(row)) continue;
          final id = _text(row['book_id']);
          if (!_validBook(id)) continue;
          choices.putIfAbsent(
            id,
            () => RecapBookChoice(
              id: id,
              title: _text(row['book_title']).trim().isEmpty
                  ? id
                  : _text(row['book_title']),
            ),
          );
          _count(choices.length, maxBooks);
        }
        return List.unmodifiable(choices.values);
      });

  Future<List<RecapMaterialChoice>> materials(
    AuthSessionScope session,
    String bookId,
  ) => _read(session, (db, owner) async {
    _book(bookId);
    final entries = await db.query(
      'user_entries',
      columns: ['id'],
      where: 'user_id = ? AND book_id = ?',
      whereArgs: [owner, bookId],
      orderBy: 'created_at DESC, id ASC',
      limit: maxMaterials + 1,
    );
    _count(entries.length, maxMaterials);
    final result = <RecapMaterialChoice>[];
    final budget = _CatalogBudget();
    var totalFollows = 0;
    for (final entry in entries) {
      session.check();
      final localId = _text(entry['id']);
      String? reason;
      RecapLocalProof? before;
      try {
        before = await _guard.inspect(session, bookId, [
          RecapLocalSelection(localId),
        ]);
      } catch (error) {
        reason = _unavailable(session, error);
      }
      // Bracket the actual projection with guard proofs so an intervening edit
      // cannot yield old text labelled selectable. The controller rechecks later.
      final rows = await db.query(
        'user_entries',
        columns: _columns,
        where: 'user_id = ? AND book_id = ? AND id = ?',
        whereArgs: [owner, bookId, localId],
        limit: 2,
      );
      session.check();
      if (rows.length != 1) continue;
      final row = rows.single;
      budget.add(row);
      if (!_publicEntry(row)) continue;
      final remote = _optionalId(row['bmob_id']);
      final follows = await db.query(
        'user_entry_follow_ups',
        columns: ['remote_id', 'question'],
        where: remote == null
            ? 'user_id = ? AND entry_id = ?'
            : 'user_id = ? AND entry_id IN (?, ?)',
        whereArgs: [owner, localId, ?remote],
        orderBy: 'created_at ASC, id ASC',
        limit: maxFollowUpRows + 1,
      );
      _count(follows.length, maxFollowUpRows);
      totalFollows += follows.length;
      _count(totalFollows, maxTotalFollowUpRows);
      budget.add(follows);
      try {
        final after = await _guard.inspect(session, bookId, [
          RecapLocalSelection(localId),
        ]);
        if (before != null && before.fingerprint != after.fingerprint) {
          reason = const RecapClientException('LOCAL_CHANGED').message;
        }
      } catch (error) {
        reason = _unavailable(session, error);
      }
      final seen = <String>{};
      result.add(
        RecapMaterialChoice(
          localId: localId,
          remoteId: remote,
          kind: _text(row['source']),
          preview: _text(row['original_text']),
          userText: _text(row['user_input']),
          followUps: [
            for (final follow in follows)
              if (_optionalId(follow['remote_id']) == null ||
                  seen.add(_text(follow['remote_id'])))
                RecapMaterialFollowUp(
                  remoteId: _optionalId(follow['remote_id']),
                  question: _text(follow['question']),
                ),
          ],
          unavailableReason: reason,
        ),
      );
    }
    return List.unmodifiable(result);
  });

  /// Maps only exact owner/book/bmob_id identities, never title or source text.
  /// Explicit empty follow_up_ids restores `none`, never `all`.
  Future<List<RecapLocalSelection>> restoreSelection(
    AuthSessionScope session,
    String bookId,
    List<Map<String, dynamic>> sources,
  ) async {
    // Snapshot caller-owned input before the first await.
    _owner(session);
    _book(bookId);
    _count(sources.length, 80);
    if (sources.isEmpty) recapReject('INVALID_SELECTION');
    final seen = <String>{};
    var totalFollows = 0;
    final parsed = <(String, List<String>)>[];
    for (final source in sources) {
      recapKeys(source, ['entry_id', 'follow_up_ids']);
      final remote = recapId(source['entry_id']);
      if (!seen.add(remote)) recapReject('INVALID_SELECTION');
      final raw = source['follow_up_ids'];
      if (raw is! List) recapReject('INVALID_SELECTION');
      _count(raw.length, 320);
      final follows = raw.map(recapId).toList();
      if (follows.toSet().length != follows.length) {
        recapReject('INVALID_SELECTION');
      }
      totalFollows += follows.length;
      _count(totalFollows, 320);
      parsed.add((remote, follows));
    }
    return _read(session, (db, owner) async {
      final selection = <RecapLocalSelection>[];
      for (final (remote, follows) in parsed) {
        final rows = await db.query(
          'user_entries',
          columns: ['id', 'source', 'metadata_json'],
          where: 'user_id = ? AND book_id = ? AND bmob_id = ?',
          whereArgs: [owner, bookId, remote],
          limit: 2,
        );
        session.check();
        if (rows.length != 1 || !_publicEntry(rows.single)) {
          throw const RecapMaterialCatalogException(
            'LOCAL_RESTORE_UNAVAILABLE',
          );
        }
        selection.add(
          RecapLocalSelection(
            _text(rows.single['id']),
            followScope: follows.isEmpty
                ? RecapFollowScope.none
                : RecapFollowScope.selected,
            followUpIds: follows,
          ),
        );
      }
      try {
        final proof = await _guard.inspect(session, bookId, selection);
        proof.checkResolved([
          for (final (remote, follows) in parsed)
            {'entry_id': remote, 'follow_up_ids': follows},
        ]);
      } on RecapClientException catch (error) {
        if (error.code == 'LOCAL_IDENTITY_MISSING') {
          throw const RecapMaterialCatalogException(
            'LOCAL_RESTORE_UNAVAILABLE',
          );
        }
        rethrow;
      }
      return List.unmodifiable(selection);
    });
  }

  Future<T> _read<T>(
    AuthSessionScope session,
    Future<T> Function(Database, String) action,
  ) async {
    try {
      final owner = _owner(session);
      final db = await database();
      session.check();
      final result = await action(db, owner);
      session.check();
      return result;
    } catch (error) {
      session.check();
      if (error is RecapClientException) rethrow;
      if (session.userId == null) recapReject('RECAP_AUTH_REQUIRED');
      throw const RecapMaterialCatalogException('LOCAL_CATALOG_UNAVAILABLE');
    }
  }

  static String _unavailable(AuthSessionScope session, Object error) {
    session.check();
    if (error is RecapClientException) {
      if (error.code == 'RECAP_SCOPE_TOO_LARGE') throw error;
      return error.message;
    }
    return const RecapMaterialCatalogException(
      'LOCAL_CATALOG_UNAVAILABLE',
    ).message;
  }

  static void _count(int count, int limit) {
    if (count > limit) recapReject('RECAP_SCOPE_TOO_LARGE');
  }

  static String _text(Object? value) => value is String ? value : '';
  static String _owner(AuthSessionScope session) {
    session.check();
    if (session.userId == null) recapReject('RECAP_AUTH_REQUIRED');
    return session.requireOwner();
  }

  static String? _optionalId(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
  static bool _validBook(String id) =>
      id.isNotEmpty && id.trim() == id && id.length <= 200;
  static void _book(String id) {
    if (!_validBook(id)) recapReject('INVALID_SELECTION');
  }

  static bool _publicEntry(Map<String, Object?> row) {
    if (!_sources.contains(row['source'])) return false;
    final raw = row['metadata_json'];
    if (raw == null || raw == '') return true;
    try {
      final metadata = raw is String ? jsonDecode(raw) : raw;
      return metadata is Map && !_privateMetadata(metadata);
    } catch (_) {
      return false;
    }
  }

  // Mirrors the guard's privacy exclusion before any text reaches the UI.
  static bool _privateMetadata(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (const [
          'free_note_id',
          'freeNoteId',
          'free_note',
          'free_notes',
          'authorized_free_note',
        ].contains(entry.key)) {
          return true;
        }
        if (entry.key == 'origin' &&
            !const ['reader', 'xiaou_asks', null, ''].contains(entry.value)) {
          return true;
        }
        if (_privateMetadata(entry.value)) return true;
      }
    }
    return value is List && value.any(_privateMetadata);
  }
}

class _CatalogBudget {
  int _bytes = 0;
  void add(Object value) {
    _bytes += utf8.encode(jsonEncode(value)).length;
    BookRecapMaterialCatalog._count(
      _bytes,
      BookRecapMaterialCatalog.maxPayloadBytes,
    );
  }
}
