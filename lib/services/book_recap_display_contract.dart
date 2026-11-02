import 'dart:convert';

import 'book_recap_client_contract.dart';

String _string(Object? value, {int min = 0, int? max}) {
  if (value is! String ||
      value.length < min ||
      (max != null && value.length > max)) {
    recapReject();
  }
  return value;
}

T _enum<T extends Enum>(Object? value, List<T> values) {
  for (final item in values) {
    if (item.name == value) return item;
  }
  recapReject();
}

// DateTime.parse normalizes invalid calendar dates; reject those explicitly.
DateTime _utc(Object? value) {
  final text = _string(value);
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?Z$',
  ).firstMatch(text);
  if (match == null) recapReject();
  final date = DateTime.tryParse(text);
  if (date == null || !date.isUtc) recapReject();
  final parts = [
    date.year,
    date.month,
    date.day,
    date.hour,
    date.minute,
    date.second,
  ];
  for (var i = 0; i < parts.length; i++) {
    if (parts[i] != int.parse(match.group(i + 1)!)) recapReject();
  }
  return date;
}

String recapEvidenceId(Object? value) {
  if (value is! String || !RegExp(r'^e-[a-f0-9]{64}$').hasMatch(value)) {
    recapReject();
  }
  return value;
}

/// Online verification metadata, never a bearer credential or cache permission.
class RecapDisplayGrant {
  final String policyVersion, recapId, bookId, revision, sourceFingerprint;
  final DateTime checkedAt, expiresAt;
  final int maxAgeMs;
  DateTime? _lastNow;
  Duration? _lastElapsed;
  bool _clockRejected = false;

  RecapDisplayGrant._(
    this.policyVersion,
    this.recapId,
    this.bookId,
    this.revision,
    this.sourceFingerprint,
    this.checkedAt,
    this.expiresAt,
    this.maxAgeMs,
  );

  factory RecapDisplayGrant.parse(Map<String, dynamic> value) {
    recapKeys(value, [
      'protocol_version',
      'policy_version',
      'recap_id',
      'book_id',
      'revision',
      'source_fingerprint',
      'checked_at',
      'expires_at',
      'max_age_ms',
      'local_pending_verified',
      'requires_online_on_open',
    ]);
    final policy = _string(value['policy_version'], min: 1, max: 64);
    final age = value['max_age_ms'];
    final checked = _utc(value['checked_at']);
    final expires = _utc(value['expires_at']);
    if (value['protocol_version'] is! int ||
        value['protocol_version'] != 1 ||
        value['local_pending_verified'] != false ||
        value['requires_online_on_open'] != true ||
        !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(policy) ||
        age is! int ||
        age < 1 ||
        age > 120000 ||
        expires.difference(checked) != Duration(milliseconds: age)) {
      recapReject();
    }
    return RecapDisplayGrant._(
      policy,
      _recapId(value['recap_id']),
      _string(value['book_id'], min: 1, max: 256),
      recapRevision(value['revision']),
      recapDigest(value['source_fingerprint']),
      checked,
      expires,
      age,
    );
  }

  /// elapsed starts before the HTTP request, including final local verification.
  /// A caller with a request wall-clock baseline can also detect first-call jumps.
  Duration remaining({
    required RecapHeader header,
    required Set<String> approvedPolicies,
    required DateTime now,
    required Duration elapsed,
    required Duration clientLimit,
    DateTime? requestStartedAt,
  }) {
    if (header.id != recapId ||
        header.bookId != bookId ||
        header.revision != revision ||
        header.sourceFingerprint != sourceFingerprint ||
        header.state != RecapServerState.ready) {
      recapReject('RECAP_REVISION_CONFLICT');
    }
    if (!approvedPolicies.contains(policyVersion)) {
      recapReject('RECAP_DISPLAY_POLICY_REQUIRED');
    }
    // This tolerance detects clock discontinuities, not a display-policy default.
    const tolerance = Duration(seconds: 2);
    final wallAge = now.difference(checkedAt);
    final previousNow = _lastNow;
    final previousElapsed = _lastElapsed;
    if (_clockRejected ||
        elapsed < Duration.zero ||
        clientLimit <= Duration.zero ||
        wallAge < Duration.zero ||
        wallAge > elapsed + tolerance ||
        (requestStartedAt != null &&
            (now.isBefore(requestStartedAt) ||
                (now.difference(requestStartedAt) - elapsed).abs() >
                    tolerance)) ||
        (previousNow != null &&
            previousElapsed != null &&
            (now.isBefore(previousNow) ||
                elapsed < previousElapsed ||
                (now.difference(previousNow) - (elapsed - previousElapsed))
                        .abs() >
                    tolerance))) {
      _clockRejected = true;
      recapReject('RECAP_DISPLAY_CLOCK_INVALID');
    }
    _lastNow = now;
    _lastElapsed = elapsed;
    final candidates = [
      Duration(milliseconds: maxAgeMs) - elapsed,
      expiresAt.difference(now),
      clientLimit - elapsed,
    ];
    final remaining = candidates.reduce((a, b) => a < b ? a : b);
    return remaining > Duration.zero ? remaining : Duration.zero;
  }
}

// Avoid the grant's recapId field shadowing the shared validator.
String _recapId(Object? value) => recapId(value);

enum RecapHistoryFilter { all, saved, preview }

enum RecapHistoryState {
  prepared,
  generating,
  ready,
  stale,
  invalidated,
  deleted,
  failed,
  cancelled,
  expired,
}

// Wire names intentionally match the backend vocabulary exactly.
// ignore: constant_identifier_names
enum RecapHistoryAvailability { requires_online_verification, unavailable }

class RecapHistoryItem {
  final String id, revision, createdAt;
  final String? bookId;
  final RecapHistoryState state;
  final RecapHistoryAvailability availability;
  final bool isSaved;
  final DateTime updatedAt;
  final DateTime? expiresAt;
  RecapHistoryItem._(
    this.id,
    this.bookId,
    this.revision,
    this.state,
    this.isSaved,
    this.createdAt,
    this.updatedAt,
    this.expiresAt,
    this.availability,
  );

  factory RecapHistoryItem.parse(Map<String, dynamic> value) {
    recapKeys(value, [
      'id',
      'book_id',
      'revision',
      'state',
      'is_saved',
      'created_at',
      'updated_at',
      'expires_at',
      'availability',
    ]);
    final state = _enum(value['state'], RecapHistoryState.values);
    final availability = _enum(
      value['availability'],
      RecapHistoryAvailability.values,
    );
    if (value['is_saved'] is! bool ||
        (state == RecapHistoryState.ready) !=
            (availability ==
                RecapHistoryAvailability.requires_online_verification)) {
      recapReject();
    }
    return RecapHistoryItem._(
      recapId(value['id']),
      value['book_id'] == null ? null : _string(value['book_id']),
      recapRevision(value['revision']),
      state,
      value['is_saved'],
      _string(value['created_at']),
      _utc(value['updated_at']),
      value['expires_at'] == null ? null : _utc(value['expires_at']),
      availability,
    );
  }
}

class RecapHistoryPage {
  final List<RecapHistoryItem> items;
  final String? nextCursor;
  bool get containsPrivateBody => false;
  bool get snapshotConsistent => false;
  RecapHistoryPage._(List<RecapHistoryItem> items, this.nextCursor)
    : items = List.unmodifiable(items);

  factory RecapHistoryPage.parse(Map<String, dynamic> value) {
    recapKeys(value, [
      'items',
      'next_cursor',
      'contains_private_body',
      'snapshot_consistent',
    ]);
    if (value['contains_private_body'] != false ||
        value['snapshot_consistent'] != false) {
      recapReject();
    }
    final items = recapList(
      value['items'],
      50,
    ).map((item) => RecapHistoryItem.parse(recapObject(item))).toList();
    if (items.map((item) => item.id).toSet().length != items.length) {
      recapReject();
    }
    return RecapHistoryPage._(
      items,
      value['next_cursor'] == null
          ? null
          : _string(value['next_cursor'], min: 1, max: 2048),
    );
  }
}

enum RecapEvidenceKind {
  // ignore: constant_identifier_names
  book_excerpt,
  highlight,
  // ignore: constant_identifier_names
  user_note,
  // ignore: constant_identifier_names
  user_question,
  // ignore: constant_identifier_names
  historical_ai,
  // ignore: constant_identifier_names
  ai_prompt,
}

// ignore: constant_identifier_names
enum RecapEvidenceProvenance { reader_context, trace, follow_up, ai_prompt }

class RecapEvidenceCatalogItem {
  final String id, entryId;
  final String? followUpId;
  final RecapEvidenceKind kind;
  final RecapEvidenceProvenance provenance;
  RecapEvidenceCatalogItem._(
    this.id,
    this.entryId,
    this.followUpId,
    this.kind,
    this.provenance,
  );

  factory RecapEvidenceCatalogItem.parse(Map<String, dynamic> value) {
    recapKeys(value, ['id', 'entry_id', 'follow_up_id', 'kind', 'provenance']);
    return RecapEvidenceCatalogItem._(
      recapEvidenceId(value['id']),
      recapId(value['entry_id']),
      value['follow_up_id'] == null ? null : recapId(value['follow_up_id']),
      _enum(value['kind'], RecapEvidenceKind.values),
      _enum(value['provenance'], RecapEvidenceProvenance.values),
    );
  }

  void checkSource(RecapHeader header) {
    final sources = header.sources.where(
      (source) => source['entry_id'] == entryId,
    );
    if (sources.length != 1 ||
        (followUpId != null &&
            !(sources.single['follow_up_ids'] as List).contains(followUpId))) {
      recapReject();
    }
  }

  bool sameSource(RecapEvidenceCatalogItem other) =>
      id == other.id &&
      entryId == other.entryId &&
      followUpId == other.followUpId &&
      kind == other.kind &&
      provenance == other.provenance;
}

class RecapRecoveredScope {
  final RecapHeader header;
  final List<RecapEvidenceCatalogItem> evidenceCatalog;
  bool get requiresLocalConfirmation => true;
  RecapRecoveredScope._(this.header, List<RecapEvidenceCatalogItem> catalog)
    : evidenceCatalog = List.unmodifiable(catalog);

  factory RecapRecoveredScope.parse(Map<String, dynamic> value) {
    recapKeys(value, [
      'id',
      'book_id',
      'revision',
      'state',
      'is_saved',
      'source_fingerprint',
      'coverage',
      'sources',
      'evidence_summary',
      'scope_basis',
      'local_pending_verified',
      'evidence_catalog',
      'requires_local_confirmation',
    ]);
    if (value['requires_local_confirmation'] != true) recapReject();
    final metadata = Map<String, dynamic>.of(value)
      ..remove('evidence_catalog')
      ..remove('requires_local_confirmation');
    final header = RecapHeader.fromScope(metadata);
    final catalog = recapList(
      value['evidence_catalog'],
      320,
    ).map((item) => RecapEvidenceCatalogItem.parse(recapObject(item))).toList();
    if (catalog.map((item) => item.id).toSet().length != catalog.length ||
        recapObject(value['evidence_summary'])['transmitted'] !=
            catalog.length) {
      recapReject();
    }
    for (final item in catalog) {
      item.checkSource(header);
    }
    return RecapRecoveredScope._(header, catalog);
  }
}

class RecapEvidenceLocation {
  final String? chapterIndex;
  final String chapterTitle;
  String get status => 'fragment_only';
  bool get exact => false;
  RecapEvidenceLocation._(this.chapterIndex, this.chapterTitle);
  factory RecapEvidenceLocation.parse(Map<String, dynamic> value) {
    recapKeys(value, ['status', 'exact', 'chapter_index', 'chapter_title']);
    if (value['status'] != 'fragment_only' || value['exact'] != false) {
      recapReject();
    }
    return RecapEvidenceLocation._(
      value['chapter_index'] == null
          ? null
          : _string(value['chapter_index'], max: 100),
      _string(value['chapter_title'], max: 1000),
    );
  }
}

class RecapEvidenceItem {
  final RecapEvidenceCatalogItem source;
  final String text;
  final RecapEvidenceLocation location;
  String get id => source.id;
  String get entryId => source.entryId;
  String? get followUpId => source.followUpId;
  RecapEvidenceKind get kind => source.kind;
  RecapEvidenceProvenance get provenance => source.provenance;
  RecapEvidenceItem._(this.source, this.text, this.location);
  factory RecapEvidenceItem.parse(Map<String, dynamic> value) {
    recapKeys(value, [
      'id',
      'entry_id',
      'follow_up_id',
      'kind',
      'provenance',
      'text',
      'location',
    ]);
    final source = Map<String, dynamic>.of(value)
      ..remove('text')
      ..remove('location');
    return RecapEvidenceItem._(
      RecapEvidenceCatalogItem.parse(source),
      _string(value['text'], min: 1, max: 100000),
      RecapEvidenceLocation.parse(recapObject(value['location'])),
    );
  }
}

class RecapEvidenceResponse {
  final List<RecapEvidenceItem> evidence;
  final RecapDisplayGrant display;
  RecapEvidenceResponse._(List<RecapEvidenceItem> evidence, this.display)
    : evidence = List.unmodifiable(evidence);

  factory RecapEvidenceResponse.parse(
    Map<String, dynamic> value, {
    RecapHeader? header,
    List<String>? requestedIds,
    RecapRecoveredScope? scope,
  }) {
    recapKeys(value, ['evidence', 'display']);
    if (utf8.encode(jsonEncode(value)).length > 256 * 1024) recapReject();
    final evidence = recapList(
      value['evidence'],
      24,
    ).map((item) => RecapEvidenceItem.parse(recapObject(item))).toList();
    final ids = evidence.map((item) => item.id).toSet();
    if (ids.length != evidence.length) recapReject();
    if (requestedIds != null) {
      final requested = requestedIds.map(recapEvidenceId).toSet();
      if (requested.isEmpty ||
          requested.length > 24 ||
          requested.length != requestedIds.length ||
          ids.length != requested.length ||
          !ids.containsAll(requested)) {
        recapReject();
      }
    }
    final boundHeader = header ?? scope?.header;
    final display = RecapDisplayGrant.parse(recapObject(value['display']));
    if (boundHeader != null) {
      _binding(display, boundHeader);
      for (final item in evidence) {
        item.source.checkSource(boundHeader);
      }
    }
    if (scope != null) {
      _binding(display, scope.header);
      for (final item in evidence) {
        if (!scope.evidenceCatalog.any(item.source.sameSource)) recapReject();
      }
    }
    return RecapEvidenceResponse._(evidence, display);
  }
}

void _binding(RecapDisplayGrant grant, RecapHeader header) {
  if (grant.recapId != header.id ||
      grant.bookId != header.bookId ||
      grant.revision != header.revision ||
      grant.sourceFingerprint != header.sourceFingerprint) {
    recapReject('RECAP_REVISION_CONFLICT');
  }
}

class RecapViewResponse {
  final RecapHeader header;
  final RecapDisplayGrant display;
  final String _result;
  Map<String, dynamic> get result => recapObject(jsonDecode(_result));
  RecapViewResponse._(this.header, this.display, this._result);
  factory RecapViewResponse.parse(
    Map<String, dynamic> value, {
    RecapHeader? expectedHeader,
  }) {
    recapKeys(value, ['recap', 'display']);
    final recap = recapObject(value['recap']);
    final header = RecapHeader.parse(recap);
    if (header.state != RecapServerState.ready) recapReject();
    final display = RecapDisplayGrant.parse(recapObject(value['display']));
    _binding(display, header);
    if (expectedHeader != null) _binding(display, expectedHeader);
    return RecapViewResponse._(header, display, jsonEncode(recap['result']));
  }
}

class RecapValidationResponse {
  final RecapDisplayGrant display;
  RecapValidationResponse._(this.display);
  factory RecapValidationResponse.parse(
    Map<String, dynamic> value, {
    RecapHeader? header,
  }) {
    recapKeys(value, ['display']);
    final display = RecapDisplayGrant.parse(recapObject(value['display']));
    if (header != null) _binding(display, header);
    return RecapValidationResponse._(display);
  }
}
