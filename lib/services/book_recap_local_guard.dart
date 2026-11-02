import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import 'auth_session_scope.dart';
import 'book_recap_client_contract.dart';
import 'upload_revision.dart';
import 'xiaou_trace_snapshot.dart';

class RecapLocalProof {
  final String fingerprint;
  final String _sources;
  final Map<String, Set<String>> _knownFollowUps;
  RecapLocalProof._(
    this.fingerprint,
    List<Map<String, dynamic>> sources,
    Map<String, Set<String>> knownFollowUps,
  ) : _sources = jsonEncode(sources),
      _knownFollowUps = Map.unmodifiable(knownFollowUps);
  List<Map<String, dynamic>> get sources =>
      (jsonDecode(_sources) as List).map(recapObject).toList();

  void checkResolved(Object? value) {
    final actual = recapList(value, 80).map(recapObject).toList();
    final expected = sources;
    if (actual.length != expected.length) recapReject('RECAP_SCOPE_CHANGED');
    for (final source in expected) {
      final matches = actual.where((s) => s['entry_id'] == source['entry_id']);
      if (matches.length != 1) recapReject('RECAP_SCOPE_CHANGED');
      // All means the server's current set. Explicit empty/subset must match exactly.
      if (source.containsKey('follow_up_ids')) {
        final a = (matches.single['follow_up_ids'] as List)
            .cast<String>()
            .toSet();
        final b = (source['follow_up_ids'] as List).cast<String>().toSet();
        if (a.length != b.length || !a.containsAll(b)) {
          recapReject('RECAP_SCOPE_CHANGED');
        }
      } else if (!(matches.single['follow_up_ids'] as List)
          .cast<String>()
          .toSet()
          .containsAll(_knownFollowUps[source['entry_id']]!)) {
        recapReject('RECAP_SCOPE_CHANGED');
      }
    }
  }
}

/// No DB singleton, writes, uploads, book-file reads or remote cache fallback.
/// Missing local identities fail closed; cross-device bootstrap needs later wiring.
class BookRecapLocalGuard {
  final Future<Database> Function() database;
  BookRecapLocalGuard(this.database);

  Future<RecapLocalProof> inspect(
    AuthSessionScope session,
    String bookId,
    List<RecapLocalSelection> selection,
  ) async {
    final owner = session.requireOwner();
    if (bookId.isEmpty ||
        bookId.trim() != bookId ||
        bookId.length > 200 ||
        selection.isEmpty ||
        selection.length > 80 ||
        selection.map((s) => s.localEntryId).toSet().length !=
            selection.length) {
      recapReject('INVALID_SELECTION');
    }
    final db = await database();
    session.check();
    final result = await db.transaction((tx) async {
      session.check();
      final deleted = await tx.query(
        'locally_deleted_books',
        columns: ['book_id'],
        where: 'user_id = ? AND book_id = ?',
        whereArgs: [owner, bookId],
      );
      if (deleted.isNotEmpty) recapReject('LOCAL_DELETED');
      final material = <Object>[], sources = <Map<String, dynamic>>[];
      final seen = <String>{};
      final knownFollowUps = <String, Set<String>>{};
      for (final item in selection) {
        final rows = await tx.query(
          'user_entries',
          where: 'user_id = ? AND book_id = ? AND id = ?',
          whereArgs: [owner, bookId, item.localEntryId],
        );
        if (rows.length != 1) recapReject('LOCAL_IDENTITY_MISSING');
        final row = rows.single;
        final remote = row['bmob_id']?.toString() ?? '';
        if (remote.isEmpty) recapReject('LOCAL_IDENTITY_MISSING');
        recapId(remote);
        if (!seen.add(remote)) recapReject('LOCAL_IDENTITY_MISSING');
        final aliases = await tx.query(
          'user_entries',
          columns: ['id'],
          where: 'user_id = ? AND bmob_id = ?',
          whereArgs: [owner, remote],
        );
        if (aliases.length != 1) recapReject('LOCAL_IDENTITY_MISSING');
        final pending = await tx.query(
          'pending_upload_operations',
          columns: ['operation'],
          where:
              "user_id = ? AND entity_type = 'trace' AND entity_id IN (?, ?)",
          whereArgs: [owner, item.localEntryId, remote],
        );
        final revisions = await tx.query(
          'upload_entity_revisions',
          where:
              "user_id = ? AND entity_type = 'trace' AND entity_id IN (?, ?)",
          whereArgs: [owner, item.localEntryId, remote],
          orderBy: 'entity_id',
        );
        if (pending.any((p) => p['operation'] == 'delete') ||
            revisions.any(
              (r) => r['state_hash'] == uploadStateHash('delete', const {}),
            )) {
          recapReject('LOCAL_DELETED');
        }
        if (pending.isNotEmpty) recapReject('LOCAL_PENDING');
        final metadata = XiaouTraceSnapshot.metadata(row['metadata_json']);
        if (_privateSource(metadata) ||
            ![
              'highlight',
              'thought',
              'manual',
              'ai_explanation',
              'ai_question',
            ].contains(row['source'])) {
          recapReject('LOCAL_IDENTITY_MISSING');
        }
        // Only metadata is checked here; raw source text is never logged or sent.
        final follows = await tx.query(
          'user_entry_follow_ups',
          where: 'user_id = ? AND entry_id IN (?, ?)',
          whereArgs: [owner, item.localEntryId, remote],
          orderBy: 'id',
        );
        if (follows.length > 640) recapReject('RECAP_SCOPE_TOO_LARGE');
        final byRemote = <String, Map<String, Object?>>{};
        for (final f in follows) {
          final id = f['remote_id']?.toString() ?? '';
          if (f['remote_synced'] != 1 || id.isEmpty) {
            recapReject('LOCAL_PENDING');
          }
          recapId(id);
          final previous = byRemote[id];
          if (previous != null &&
              [
                'question',
                'answer',
                'created_at',
              ].any((k) => previous[k] != f[k])) {
            recapReject('LOCAL_CHANGED');
          }
          byRemote[id] = f;
        }
        // Unknown ownership is preserved but cannot silently become this account's input.
        final unknown = await tx.query(
          'user_entry_follow_ups',
          columns: ['id'],
          where: "(user_id IS NULL OR user_id = '') AND entry_id IN (?, ?)",
          whereArgs: [item.localEntryId, remote],
          limit: 1,
        );
        if (unknown.isNotEmpty) recapReject('LOCAL_IDENTITY_MISSING');
        if (!byRemote.keys.toSet().containsAll(item.followUpIds)) {
          recapReject('LOCAL_IDENTITY_MISSING');
        }
        knownFollowUps[remote] = Set.unmodifiable(byRemote.keys);
        sources.add({
          'entry_id': remote,
          if (item.followScope != RecapFollowScope.all)
            'follow_up_ids': item.followUpIds.toList()..sort(),
        });
        material.add({
          'row': row,
          'revisions': revisions,
          'followUps': follows,
          'mode': item.followScope.name,
          'selected': item.followUpIds.toList()..sort(),
        });
      }
      sources.sort(
        (a, b) => (a['entry_id'] as String).compareTo(b['entry_id'] as String),
      );
      final encoded = jsonEncode(
        _canonical({
          'owner': owner,
          'epoch': session.epoch,
          'origin': session.origin,
          'book': bookId,
          'material': material,
        }),
      );
      if (utf8.encode(encoded).length > 512 * 1024) {
        recapReject('RECAP_SCOPE_TOO_LARGE');
      }
      session.check();
      return RecapLocalProof._(
        sha256.convert(utf8.encode(encoded)).toString(),
        sources,
        knownFollowUps,
      );
    });
    session.check();
    return result;
  }

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: _canonical(value[k])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  static bool _privateSource(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if ([
          'free_note_id',
          'freeNoteId',
          'free_note',
          'free_notes',
          'authorized_free_note',
        ].contains(entry.key)) {
          return true;
        }
        if (entry.key == 'origin' &&
            !['reader', 'xiaou_asks', null, ''].contains(entry.value)) {
          return true;
        }
        if (_privateSource(entry.value)) return true;
      }
    }
    if (value is List) return value.any(_privateSource);
    return false;
  }
}
