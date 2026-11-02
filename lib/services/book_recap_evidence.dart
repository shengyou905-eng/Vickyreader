import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import 'auth_session_scope.dart';
import 'reading_anchor.dart';
import 'xiaou_trace_snapshot.dart';

/// A caller-supplied, owned document projection. Never loads a book or a network.
/// Chapter keys are stored sourceIndex values, not display-list positions.
class RecapDocument {
  final String userId;
  final String bookId;
  final String version;
  final Map<String, String> chapters;
  RecapDocument({
    required this.userId,
    required this.bookId,
    required this.version,
    required Map<String, String> chapters,
  }) : chapters = Map.unmodifiable(chapters);
}

class BookRecapSnapshot {
  final AuthSessionScope _session;
  final String _json;
  BookRecapSnapshot._(this._session, Map<String, dynamic> value)
    : _json = jsonEncode(value);

  /// A -> B -> A must not make an old snapshot available again.
  Map<String, dynamic> toJson() {
    _session.check();
    return jsonDecode(_json) as Map<String, dynamic>;
  }
}

/// Reads an already-open database; does not initialize/migrate it or call sync.
class BookRecapEvidence {
  static const _sources = {
    'highlight',
    'thought',
    'ai_explanation',
    'ai_question',
    'manual',
  };

  static Future<BookRecapSnapshot> read(
    Database db, {
    required AuthSessionScope session,
    required String bookId,
    List<Map<String, dynamic>> remoteRows = const [],
    String? remoteOrigin,
    Set<String>? selectedEntryIds,
    RecapDocument? document,
  }) async {
    final owner = session.requireOwner();
    if (bookId.trim().isEmpty) throw ArgumentError('bookId is required');
    if (remoteRows.isNotEmpty && remoteOrigin != session.origin) {
      throw StateError('Remote cache environment mismatch');
    }
    if (document != null &&
        (document.userId != owner ||
            document.bookId != bookId ||
            document.version.isEmpty)) {
      throw StateError('Document scope mismatch');
    }
    // Do not borrow permissive legacy cache-owner inference from the home feed.
    final trustedRows = remoteRows
        .where((r) => r['user_id'] == owner && r['book_id'] == bookId)
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    final remoteIdentities = <String, String>{};
    for (final row in trustedRows) {
      final metadata = XiaouTraceSnapshot.metadata(row['metadata_json']);
      for (final identity in [
        'remote:${_text(row['id'])}',
        'client:${_text(row['client_entry_id']).isNotEmpty ? _text(row['client_entry_id']) : _text(metadata['local_id'])}',
      ]) {
        if (identity.endsWith(':')) continue;
        final signature = fingerprint(row);
        if (remoteIdentities.containsKey(identity) &&
            remoteIdentities[identity] != signature) {
          throw StateError('Conflicting trace identity');
        }
        remoteIdentities[identity] = signature;
      }
    }
    return db.transaction((txn) async {
      session.check();
      final deleted = await txn.query(
        'locally_deleted_books',
        where: 'user_id = ? AND book_id = ?',
        whereArgs: [owner, bookId],
      );
      if (deleted.isNotEmpty) throw StateError('Book permanently deleted');
      final projected = await XiaouTraceSnapshot.readInTransaction(
        txn,
        userId: owner,
        remoteRows: trustedRows,
        bookId: bookId,
      );
      final local = await txn.query(
        'user_entries',
        where: 'user_id = ? AND book_id = ?',
        whereArgs: [owner, bookId],
      );
      final localMetadata = {
        for (final r in local) r['id']: r['metadata_json'],
      };
      // An old remote context must not fill a metadata field removed locally.
      for (final row in projected) {
        if (localMetadata.containsKey(row['_view_id'])) {
          row['metadata_json'] = localMetadata[row['_view_id']];
        }
      }
      final candidates = projected
          .where((r) => r['user_id'] == owner && r['book_id'] == bookId)
          .toList();
      final rows = candidates.where((r) {
        final metadata = XiaouTraceSnapshot.metadata(r['metadata_json']);
        return _text(r['_view_id']).trim().isNotEmpty &&
            _sources.contains(r['source']) &&
            const {
              null,
              '',
              'reader',
              'xiaou_asks',
            }.contains(metadata['origin']) &&
            !metadata.containsKey('free_note_id') &&
            !metadata.containsKey('freeNoteId') &&
            !const {
              'free_note',
              'free_notes',
              'authorized_free_note',
            }.contains(metadata['origin']);
      }).toList();
      final ids = rows.map((r) => r['_view_id'] as String).toSet();
      if (selectedEntryIds != null && !ids.containsAll(selectedEntryIds)) {
        throw StateError('Selection includes unavailable evidence');
      }
      final selected =
          rows
              .where(
                (r) =>
                    selectedEntryIds == null ||
                    selectedEntryIds.contains(r['_view_id']),
              )
              .toList()
            ..sort(
              (a, b) =>
                  a['_view_id'].toString().compareTo(b['_view_id'].toString()),
            );
      final books = await txn.query(
        'books',
        columns: ['title', 'author'],
        where: 'id = ? AND user_id = ?',
        whereArgs: [bookId, owner],
      );
      final highlights = await txn.query(
        'highlights',
        where: 'user_id = ? AND bookId = ?',
        whereArgs: [owner, bookId],
      );
      final notes = await txn.query(
        'notes',
        where: 'user_id = ? AND bookId = ?',
        whereArgs: [owner, bookId],
      );
      final business = {
        for (final r in highlights) 'highlight:${r['id']}': r,
        for (final r in notes) 'thought:${r['id']}': r,
      };
      final aliases = <String, String>{};
      for (final row in selected) {
        final id = row['_view_id'] as String;
        for (final alias in [id, _text(row['id'])]) {
          if (alias.isEmpty) continue;
          if (aliases.containsKey(alias) && aliases[alias] != id) {
            throw StateError('Ambiguous entry identity');
          }
          aliases[alias] = id;
        }
      }
      final followUps = <Map<String, Object?>>[];
      final parentIds = aliases.keys.toList();
      // Keep each query below SQLite's older parameter limit.
      for (var start = 0; start < parentIds.length; start += 500) {
        final batch = parentIds.skip(start).take(500).toList();
        followUps.addAll(
          await txn.query(
            'user_entry_follow_ups',
            where:
                'user_id = ? AND entry_id IN (${List.filled(batch.length, '?').join(',')})',
            whereArgs: [owner, ...batch],
            orderBy: 'created_at ASC, id ASC',
          ),
        );
      }
      final evidence = <Map<String, dynamic>>[];
      for (final row in selected) {
        _entryEvidence(row, business, document, evidence);
      }
      // Collapse only a local/remote representation of the same follow-up ID.
      // Different IDs with identical words remain independent reading actions.
      final seen = <String, String>{};
      for (final row in followUps) {
        final parent = aliases[_text(row['entry_id'])];
        if (parent == null) continue;
        final id = _text(row['remote_id']).isNotEmpty
            ? _text(row['remote_id'])
            : _text(row['id']);
        final signature = jsonEncode([
          parent,
          row['question'],
          row['answer'],
          row['created_at'],
        ]);
        if (seen.containsKey(id)) {
          if (seen[id] != signature) {
            throw StateError('Conflicting follow-up identity');
          }
          continue;
        }
        seen[id] = signature;
        for (final pair in [
          ('question', 'user_question'),
          ('answer', 'historical_ai'),
        ]) {
          _add(
            evidence,
            parent,
            pair.$1,
            pair.$2,
            _text(row[pair.$1]),
            provenance: 'follow_up',
            createdAt: _date(row['created_at']),
            followUpId: id,
          );
        }
      }
      evidence.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
      final result = <String, dynamic>{
        'schemaVersion': 1,
        'scope': {'userId': owner, 'origin': session.origin, 'bookId': bookId},
        'book': {
          'title': books.isEmpty ? null : books.single['title'],
          'author': books.isEmpty ? null : books.single['author'],
          'documentVersion': document?.version,
        },
        'evidence': evidence,
        'coverage': {
          'basis': 'reading_traces',
          'fullBook': false,
          'sourceCompleteness': 'local_and_supplied_cache',
          'availableEntries': rows.length,
          'includedEntries': selected.length,
          'includedFollowUps': seen.length,
          'quarantinedEntries': candidates.length - rows.length,
          'selectionApplied': selectedEntryIds != null,
        },
      };
      result['fingerprint'] = fingerprint(result);
      session.check();
      return BookRecapSnapshot._(session, result);
    });
  }

  static void _entryEvidence(
    Map<String, dynamic> row,
    Map<String, Map<String, Object?>> business,
    RecapDocument? document,
    List<Map<String, dynamic>> output,
  ) {
    final id = row['_view_id'] as String;
    final source = _text(row['source']);
    final m = XiaouTraceSnapshot.metadata(row['metadata_json']);
    final context = XiaouTraceSnapshot.metadata(m['reading_ai_context']);
    final original = _text(row['original_text']);
    final chapter = _text(row['chapter_index']);
    final origin = _text(m['origin']);
    final record = business['$source:${m['source_record_id']}'];
    final matchesBusiness =
        record != null &&
        record['selectedText'] == original &&
        record['chapterIndex']?.toString() == chapter;
    final scope = _text(context['scope']);
    final field = source == 'ai_explanation' || scope == 'selection'
        ? 'selectedText'
        : scope == 'page'
        ? 'pageText'
        : scope == 'chapter'
        ? 'chapterText'
        : '';
    final storedExcerpt = field.isEmpty ? '' : _text(context[field]);
    final readerOrigin = origin.isEmpty || origin == 'reader';
    // A stored reader context is stronger provenance than a field name alone.
    final readerContext =
        readerOrigin &&
        const {'ai_explanation', 'ai_question'}.contains(source) &&
        storedExcerpt.isNotEmpty;
    final excerpt = readerContext ? storedExcerpt : original;
    var kind = origin == 'xiaou_asks'
        ? 'ai_prompt'
        : readerOrigin && (matchesBusiness || readerContext)
        ? 'book_excerpt'
        : 'unverified_excerpt';
    var provenance = kind == 'book_excerpt'
        ? readerContext
              ? 'reader_context'
              : 'business_record'
        : kind == 'ai_prompt'
        ? 'ai_prompt'
        : 'legacy_unverified';
    final anchor = <String, dynamic>{
      'chapterIndex': chapter.isEmpty ? null : chapter,
      'chapterTitle': _text(row['chapter_title']),
      'documentVersion': document?.version,
      'status': 'fragment_only',
      'start': null,
      'end': null,
    };
    if (document != null &&
        readerOrigin &&
        (kind == 'book_excerpt' || kind == 'unverified_excerpt') &&
        excerpt.isNotEmpty) {
      final text = document.chapters[chapter];
      if (text == null) {
        anchor['status'] = 'unavailable';
      } else if (!text.contains(excerpt)) {
        anchor['status'] = 'changed';
        kind = 'unverified_excerpt';
        provenance = 'legacy_unverified';
      } else {
        // Without a matching edition fingerprint, legacy offsets cannot select
        // one of several identical phrases in a reimported document.
        final sameVersion = m['document_version'] == document.version;
        final resolved = ReadingAnchor.resolve(
          text,
          excerpt,
          before: _text(m['contextBefore']),
          after: _text(m['contextAfter']),
          startOffset: sameVersion ? _int(m['startOffset']) : null,
          endOffset: sameVersion ? _int(m['endOffset']) : null,
        );
        anchor['status'] = resolved == null ? 'ambiguous' : 'exact';
        anchor['start'] = resolved?.start;
        anchor['end'] = resolved?.end;
        if (resolved != null && kind == 'unverified_excerpt') {
          kind = 'book_excerpt';
          provenance = 'current_document';
        }
      }
    }
    void add(
      String field,
      String type,
      String text,
      String proof, {
      Map<String, dynamic>? location,
    }) => _add(
      output,
      id,
      field,
      type,
      text,
      provenance: proof,
      createdAt: _date(row['created_at']),
      updatedAt: _date(row['updated_at']),
      anchor: location,
      pending: row['_pending_sync'] == true,
    );
    add(
      readerContext ? 'reading_ai_context.$field' : 'original_text',
      kind,
      excerpt,
      provenance,
      location: anchor,
    );
    if (source == 'highlight') {
      add('highlight', 'highlight', original, 'trace');
    }
    add(
      'user_input',
      source == 'ai_question' ? 'user_question' : 'user_note',
      _text(row['user_input']),
      'trace',
    );
    add(
      'ai_explanation',
      'historical_ai',
      _text(row['ai_explanation']),
      'trace',
    );
  }

  static void _add(
    List<Map<String, dynamic>> output,
    String entryId,
    String field,
    String kind,
    String text, {
    required String provenance,
    String? createdAt,
    String? updatedAt,
    String? followUpId,
    Map<String, dynamic>? anchor,
    bool pending = false,
  }) {
    if (text.trim().isEmpty) return;
    output.add({
      'id': 'e-${fingerprint([entryId, followUpId, field])}',
      'entryId': entryId,
      'followUpId': followUpId,
      'kind': kind,
      'text': text,
      'sourceField': field,
      'provenance': provenance,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'anchor': anchor,
      'pendingUpload': pending,
    });
  }

  static String fingerprint(Object? value) =>
      sha256.convert(utf8.encode(jsonEncode(_canonical(value)))).toString();
  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  static String _text(Object? value) => value is String ? value : '';
  static int? _int(Object? value) => value is int ? value : null;
  static String? _date(Object? value) =>
      DateTime.tryParse(_text(value))?.toUtc().toIso8601String();
}
