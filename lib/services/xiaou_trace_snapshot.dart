import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'upload_revision.dart';

/// A read-only projection. Remote cache rows never become local business rows.
class XiaouTraceSnapshot {
  static Future<List<Map<String, dynamic>>> read(
    Database db, {
    required String userId,
    required List<Map<String, dynamic>> remoteRows,
  }) => db.transaction((txn) async {
    final local = await txn.query(
      'user_entries',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    final pending = await txn.query(
      'pending_upload_operations',
      columns: ['entity_id', 'operation'],
      where: "user_id = ? AND entity_type = 'trace'",
      whereArgs: [userId],
    );
    final tombstones = await txn.query(
      'upload_entity_revisions',
      columns: ['entity_id'],
      where: "user_id = ? AND entity_type = 'trace' AND state_hash = ?",
      whereArgs: [userId, uploadStateHash('delete', const {})],
    );
    final deletedBooks = await txn.query(
      'locally_deleted_books',
      columns: ['book_id'],
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    final operations = {
      for (final row in pending) row['entity_id'].toString(): row['operation'],
    };
    final deletedIds = {
      ...tombstones.map((row) => row['entity_id'].toString()),
      ...pending
          .where((row) => row['operation'] == 'delete')
          .map((row) => row['entity_id'].toString()),
    };
    final books = deletedBooks.map((row) => row['book_id'].toString()).toSet();
    final byId = {for (final row in local) row['id'].toString(): row};
    final byRemoteId = {
      for (final row in local)
        if ((row['bmob_id']?.toString() ?? '').isNotEmpty)
          row['bmob_id'].toString(): row,
    };
    final result = <String, Map<String, dynamic>>{};
    for (final remote in remoteRows) {
      final owner = remote['user_id']?.toString();
      if (owner != null && owner != userId) continue;
      final remoteId = remote['id']?.toString() ?? '';
      if (remoteId.isEmpty) continue;
      final clientId =
          remote['client_entry_id']?.toString() ??
          metadata(remote['metadata_json'])['local_id']?.toString() ??
          '';
      final localRow = byId[clientId] ?? byRemoteId[remoteId] ?? byId[remoteId];
      final id =
          localRow?['id']?.toString() ??
          (clientId.isNotEmpty ? clientId : remoteId);
      if (deletedIds.contains(id) ||
          deletedIds.contains(remoteId) ||
          books.contains(remote['book_id']?.toString())) {
        continue;
      }
      final hasPending = operations.containsKey(id);
      final row = <String, dynamic>{
        ...remote,
        // A late GET or disk cache is not an acknowledgement of local edits.
        // Keep local content; use the remote row for identity/follow-up details.
        if (localRow != null) ...localRow,
        'id': remoteId,
        'metadata_json': {
          ...metadata(remote['metadata_json']),
          if (localRow != null) ...metadata(localRow['metadata_json']),
          'local_id': id,
        },
        '_view_id': id,
        '_pending_sync': hasPending,
      };
      result[id] = row;
    }
    for (final localRow in local) {
      final id = localRow['id'].toString();
      if (deletedIds.contains(id) ||
          books.contains(localRow['book_id']?.toString())) {
        continue;
      }
      result.putIfAbsent(
        id,
        () => {
          ...localRow,
          'id': localRow['bmob_id']?.toString() ?? '',
          'metadata_json': {
            ...metadata(localRow['metadata_json']),
            'local_id': id,
          },
          '_view_id': id,
          '_pending_sync': operations.containsKey(id),
        },
      );
    }
    return result.values.toList()..sort((a, b) {
      final aTime = DateTime.tryParse(a['created_at']?.toString() ?? '');
      final bTime = DateTime.tryParse(b['created_at']?.toString() ?? '');
      final order = (bTime?.millisecondsSinceEpoch ?? 0).compareTo(
        aTime?.millisecondsSinceEpoch ?? 0,
      );
      return order != 0
          ? order
          : a['_view_id'].toString().compareTo(b['_view_id'].toString());
    });
  });

  static Map<String, dynamic> metadata(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FormatException {
        // An invalid optional metadata field must not hide the original trace.
      }
    }
    return {};
  }
}
