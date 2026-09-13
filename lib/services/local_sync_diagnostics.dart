import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../config/local_diagnostics_mode.dart';
import 'upload_revision.dart';

/// Deliberately independent of DatabaseService and all upload/auth services.
class LocalSyncDiagnostics {
  static const enabled = LocalDiagnosticsMode.enabled;
  static const _channel = MethodChannel('zhidu/local_sync_diagnostics');

  static Future<String?> storedUserId() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString('auth_user_id');
  }

  static Future<Map<String, Object?>> appInfo() async {
    Map<dynamic, dynamic>? native;
    try {
      native = await _channel.invokeMapMethod('getAppInfo');
    } on MissingPluginException {
      // Bundle metadata is available on iOS only; never substitute source version.
    } on PlatformException {
      // Absence is evidence, not permission to guess a version.
    }
    const commit = String.fromEnvironment('BUILD_COMMIT');
    final uri = Uri.parse(AppConstants.apiBaseUrl);
    return {
      'version': native?['version'],
      'build_number': native?['build_number'],
      'version_source': native == null ? 'unavailable' : 'installed_ios_bundle',
      'commit': RegExp(r'^[0-9a-fA-F]{7,40}$').hasMatch(commit) ? commit : null,
      'commit_source': 'optional_BUILD_COMMIT_build_define_not_verified',
      'api_base_url': Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: uri.path,
      ).toString(),
      'backend_environment': null,
      'backend_environment_status': 'not_probed_no_network_requests',
      'diagnostics_build_enabled': enabled,
      'evidence_only_startup': enabled,
      'automatic_sync_disabled': enabled,
      'expected_database_version': AppConstants.dbVersion,
    };
  }

  static Future<File> export({required String? currentUserId}) async {
    final documents = await getApplicationDocumentsDirectory();
    final info = await appInfo();
    final snapshot = await inspect(
      path: p.join(documents.path, AppConstants.dbName),
      currentUserId: currentUserId,
    );
    final report = {'app': info, ...snapshot};
    final temporary = await getTemporaryDirectory();
    // Only this new export file is written. No database files are copied/changed.
    final exportDirectory = await temporary.createTemp('zhidu_diagnostic_');
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '');
    final file = File(
      p.join(exportDirectory.path, 'zhidu_diagnostic_$stamp.json'),
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    return file;
  }

  /// A separate SQLite read-only connection includes committed WAL frames.
  /// No schema version/callback is supplied, so this cannot run migrations.
  static Future<Map<String, Object?>> inspect({
    required String path,
    required String? currentUserId,
    DatabaseFactory? factory,
  }) async {
    if (!await File(path).exists()) {
      throw StateError('diagnostic_database_missing');
    }
    final db = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    var began = false;
    try {
      // sqflite's transaction() skips BEGIN on read-only connections. Explicit
      // deferred transaction control pins ONE snapshot across all SELECTs.
      await db.rawQuery('BEGIN DEFERRED');
      began = true;
      final version = (await db.rawQuery(
        'PRAGMA user_version',
      )).single.values.first;
      final started = DateTime.now().toUtc().toIso8601String();
      final schema = <String, Object?>{};
      final records = <String, Object?>{};
      for (final spec in _columns.entries) {
        final columns = (await db.rawQuery(
          'PRAGMA table_info("${spec.key}")',
        )).map((column) => column['name'] as String).toSet();
        final selected = spec.value.where(columns.contains).toList();
        schema[spec.key] = {
          'present': columns.isNotEmpty,
          'selected_columns': selected,
          'missing_columns': spec.value
              .where((c) => !columns.contains(c))
              .toList(),
        };
        final rows = selected.isEmpty
            ? <Map<String, Object?>>[]
            : await db.query(spec.key, columns: selected);
        records[spec.key] = rows
            .map((row) => _redact(spec.key, row, currentUserId))
            .toList();
      }
      _attachEvidence(records);
      final result = <String, Object?>{
        'diagnostic_schema_version': 1,
        'snapshot_started_at': started,
        'snapshot_finished_at': DateTime.now().toUtc().toIso8601String(),
        'database': {
          'user_version': version,
          'journal_mode': (await db.rawQuery(
            'PRAGMA journal_mode',
          )).single.values.first,
          'sqlite_version': (await db.rawQuery(
            'SELECT sqlite_version()',
          )).single.values.first,
          'read_only': true,
          'snapshot':
              'single_deferred_read_transaction_including_committed_wal',
        },
        'current_user_ref': userRef(currentUserId),
        'authentication_verified': null,
        'authentication_note':
            'stored_user_id_only_no_auth_initialization_or_server_validation',
        'scope': 'all_local_owners_pseudonymized_to_allow_ownership_diagnosis',
        'schema': schema,
        'records': records,
        'limitations': [
          'server_revision_is_not_persisted_locally',
          'pending_last_error_message_is_not_persisted_only_last_error_at',
          'hard_deleted_business_rows_cannot_be_reconstructed',
          'tombstones_are_pending_deletes_revision_state_hashes_and_locally_deleted_books',
          'deleted_state_derived_only_from_exact_known_delete_hash_or_explicit_pending_delete',
          'no_network_no_sync_no_backfill_no_checkpoint',
          enabled
              ? 'evidence_build_skips_business_startup_and_blocks_upload_scheduling'
              : 'normal_build_background_sync_is_not_frozen',
          'reading_text_note_bodies_chat_auth_and_raw_json_are_excluded',
        ],
      };
      await db.rawQuery('COMMIT');
      began = false;
      return result;
    } finally {
      try {
        if (began) await db.rawQuery('ROLLBACK');
      } finally {
        await db.close();
      }
    }
  }

  static String userRef(String? value) => value == null || value.isEmpty
      ? 'anonymous_or_unavailable'
      : 'sha256:${sha256.convert(utf8.encode('zhidu-diagnostics-user:$value'))}';

  static Map<String, Object?> _redact(
    String table,
    Map<String, Object?> row,
    String? currentUserId,
  ) {
    final result = Map<String, Object?>.from(row);
    if (result.containsKey('user_id')) {
      final owner = result.remove('user_id') as String?;
      result['user_ref'] = userRef(owner);
      result['owner_relation'] = owner == null || owner.isEmpty
          ? 'anonymous'
          : owner == currentUserId
          ? 'current'
          : 'other';
    }
    for (final field in ['metadata_json', 'payload_json']) {
      if (!result.containsKey(field)) continue;
      final raw = result.remove(field);
      Map<dynamic, dynamic>? parsed;
      try {
        final value = jsonDecode(raw is String && raw.isNotEmpty ? raw : '{}');
        if (value is Map) parsed = value;
      } on FormatException {
        // Report corruption without exporting the potentially sensitive input.
      }
      result['${field}_parse_status'] = parsed == null ? 'invalid' : 'ok';
      if (field == 'metadata_json') {
        result['source_record_id'] = _identifier(parsed?['source_record_id']);
        result['metadata_local_id'] = _identifier(parsed?['local_id']);
      } else {
        final metadata = parsed?['metadata_json'];
        Map<dynamic, dynamic>? nested;
        if (metadata is Map) nested = metadata;
        if (metadata is String) {
          try {
            final value = jsonDecode(metadata);
            if (value is Map) nested = value;
          } on FormatException {
            /* Raw payload must never escape. */
          }
        }
        result['payload_identity'] = {
          'book_id': _identifier(parsed?['book_id']),
          'source': _identifier(parsed?['source']),
          'source_record_id': _identifier(nested?['source_record_id']),
          'book_ids': parsed?['books'] is List
              ? (parsed!['books'] as List)
                    .whereType<Map>()
                    .map((b) => _identifier(b['book_id']))
                    .toList()
              : null,
        };
      }
    }
    if (table == 'highlights' || table == 'notes') {
      result['source_record_id'] = row['id'];
      result['row_present'] = true;
      result['deleted_state'] = 'no_row_tombstone_column_hard_delete_model';
    }
    if (table == 'user_entries') {
      result['local_uuid'] = row['id'];
      result['client_entry_id'] = row['id'];
      result['client_entry_id_basis'] = 'local_id_used_as_upload_endpoint_id';
      result['type'] = row['source'];
      result['remote_id'] = row['bmob_id'];
      result['server_revision'] = null;
      result['client_revision_lookup'] =
          'upload_entity_revisions:(user_ref,trace,id)';
      result['tombstone'] = null;
      result['row_present'] = true;
    }
    if (table == 'pending_upload_operations') {
      result['client_entry_id'] = row['entity_type'] == 'trace'
          ? row['entity_id']
          : null;
      result['last_error'] = null;
    }
    return result;
  }

  static String? _identifier(Object? value) =>
      value is String && RegExp(r'^[a-zA-Z0-9_:\-]{1,160}$').hasMatch(value)
      ? value
      : null;

  static void _attachEvidence(Map<String, Object?> records) {
    List<Map<String, Object?>> rows(String table) =>
        (records[table] as List).cast<Map<String, Object?>>();
    String key(Object? owner, Object? type, Object? id) =>
        jsonEncode([owner, type, id]);
    final revisions = {
      for (final r in rows('upload_entity_revisions'))
        key(r['user_ref'], r['entity_type'], r['entity_id']): r,
    };
    final pending = {
      for (final r in rows('pending_upload_operations'))
        key(r['user_ref'], r['entity_type'], r['entity_id']): r,
    };
    final deleteHash = uploadStateHash('delete', {});
    for (final r in revisions.values) {
      r['known_delete_tombstone'] = r['state_hash'] == deleteHash;
      r['tombstone_basis'] = 'exact_hash_of_delete_with_empty_payload';
    }
    for (final table in ['user_entries', 'reading_progress']) {
      final type = table == 'user_entries' ? 'trace' : 'reading_progress';
      for (final row in rows(table)) {
        final id = row[type == 'trace' ? 'id' : 'bookId'];
        final lookup = key(row['user_ref'], type, id);
        row['client_revision'] = revisions[lookup]?['last_revision'];
        row['server_revision'] = null;
        row['known_delete_tombstone'] =
            revisions[lookup]?['known_delete_tombstone'];
        row['pending_operation_id'] = pending[lookup]?['operation_id'];
        row['pending_operation'] = pending[lookup]?['operation'];
        row['pending_client_revision'] = pending[lookup]?['client_revision'];
        row['pending_generation'] = pending[lookup]?['generation'];
      }
    }
    final linked = <String, List<Object?>>{};
    for (final trace in rows('user_entries')) {
      if (trace['source_record_id'] == null) continue;
      final lookup = key(
        trace['user_ref'],
        trace['type'],
        trace['source_record_id'],
      );
      (linked[lookup] ??= []).add(trace['id']);
    }
    for (final table in ['highlights', 'notes']) {
      for (final row in rows(table)) {
        row['linked_trace_ids'] =
            linked[key(
              row['user_ref'],
              table == 'highlights' ? 'highlight' : 'thought',
              row['id'],
            )] ??
            [];
      }
    }
  }

  // Explicit allowlist: never SELECT *, raw content, credentials, or chat tables.
  static const _columns = <String, List<String>>{
    'books': [
      'id',
      'user_id',
      'is_archived',
      'readingProgress',
      'addedAt',
      'lastOpenedAt',
      'updated_at',
    ],
    'highlights': [
      'id',
      'user_id',
      'bookId',
      'chapterIndex',
      'startOffset',
      'endOffset',
      'createdAt',
      'updated_at',
      'bmob_id',
    ],
    'notes': [
      'id',
      'user_id',
      'bookId',
      'chapterIndex',
      'createdAt',
      'updatedAt',
      'updated_at',
      'bmob_id',
    ],
    'user_entries': [
      'id',
      'user_id',
      'source',
      'book_id',
      'chapter_index',
      'metadata_json',
      'created_at',
      'updated_at',
      'bmob_id',
    ],
    'reading_progress': [
      'bookId',
      'user_id',
      'chapterIndex',
      'scrollOffset',
      'updatedAt',
      'updated_at',
      'bmob_id',
    ],
    'pending_upload_operations': [
      'operation_id',
      'user_id',
      'entity_type',
      'entity_id',
      'operation',
      'payload_json',
      'created_at',
      'updated_at',
      'client_revision',
      'generation',
      'retry_count',
      'last_error_at',
      'next_retry_at',
    ],
    'upload_writer': ['writer_id'],
    'upload_entity_revisions': [
      'user_id',
      'entity_type',
      'entity_id',
      'last_revision',
      'state_hash',
      'book_id',
    ],
    'locally_deleted_books': ['user_id', 'book_id'],
  };
}
