import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../services/auth_session_scope.dart';
import '../services/book_recap_client_api.dart';
import '../services/book_recap_client_contract.dart';
import '../services/book_recap_local_guard.dart';
import '../services/book_recap_display_contract.dart';
import '../services/privacy_service.dart';

class _RecapCommand {
  final String requestId, path, json;
  final DateTime created;
  _RecapCommand(
    this.requestId,
    this.path,
    Map<String, dynamic> body,
    this.created,
  ) : json = jsonEncode(body);
  Map<String, dynamic> get body => recapObject(jsonDecode(json));
}

/// Revocable in-memory display data, never a durable permission or disk cache.
class RecapOnlineContent {
  String? _json;
  final void Function() _check;
  RecapOnlineContent._(Map<String, dynamic> data, this._check)
    : _json = jsonEncode(data);
  Map<String, dynamic> toJson() {
    _check();
    if (_json == null) recapReject('CONFIRM_REQUIRED');
    return recapObject(jsonDecode(_json!));
  }

  void _revoke() {
    _json = null;
  }
}

/// A single account/session/book scope. No registration in app.dart, disk body
/// cache, ordinary conversation calls, automatic polling or automatic retries.
class BookRecapController extends ChangeNotifier {
  final BookRecapClientApi api;
  final BookRecapLocalGuard localGuard;
  final String bookId;
  final AuthSessionScope _session;
  final Listenable localChanges;
  final DateTime Function() clock;
  final Duration replayLifetime;
  // Explicit composition policy: no production TTL or periodic polling is chosen here.
  final Duration displayLifetime;
  final Set<String> approvedDisplayPolicies;
  final Duration Function() monotonic;
  Duration? _issuedDeadline;
  RecapOnlineContent? _content;
  Timer? _displayTimer;
  List<RecapLocalSelection> _selection = const [];
  RecapHeader? _header;
  String? _id, _localFingerprint, _confirmedFingerprint, _confirmedRevision;
  _RecapCommand? _command;
  RecapRequestAbort? _abort;
  int _epoch = 0;
  bool _online = true, _busy = false, _disposed = false;
  bool _uncertain = false, _deletionRequested = false;
  RecapClientPhase _phase = RecapClientPhase.idle;
  RecapClientException? _error;

  BookRecapController({
    required this.api,
    required this.localGuard,
    required this.bookId,
    required this.localChanges,
    required this.displayLifetime,
    Set<String> approvedDisplayPolicies = const {},
    Duration Function()? monotonic,
    AuthSessionScope? session,
    DateTime Function()? clock,
    this.replayLifetime = const Duration(hours: 1),
  }) : _session = session ?? AuthSessionScope.capture(),
       clock = clock ?? DateTime.now,
       approvedDisplayPolicies = Set.unmodifiable(approvedDisplayPolicies),
       monotonic = monotonic ?? _stopwatchClock() {
    _session.requireOwner();
    if (bookId.isEmpty ||
        replayLifetime <= Duration.zero ||
        displayLifetime <= Duration.zero) {
      recapReject('INVALID_SELECTION');
    }
    AuthSessionScope.changes.addListener(_sessionChanged);
    localChanges.addListener(_localChanged);
    PrivacyService.aiConsentChanges.addListener(_consentChanged);
  }

  RecapClientPhase get phase =>
      _session.isCurrent ? _phase : RecapClientPhase.unavailable;
  RecapHeader? get header => _session.isCurrent && !_disposed ? _header : null;
  String? get message => _error?.message;
  bool get busy => _busy;
  RecapOnlineContent? get content =>
      _session.isCurrent && !_disposed ? _content : null;
  String? get recapIdValue => _session.isCurrent ? _id : null;
  bool get sessionCurrent => _session.isCurrent && !_disposed;

  static Duration Function() _stopwatchClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  String? get replayRequestId =>
      _session.isCurrent ? _command?.requestId : null;

  void _check() {
    if (_disposed || !_session.isCurrent) recapReject('AUTH_CHANGED');
    _session.requireOwner();
  }

  void _sessionChanged() {
    if (!_session.isCurrent) {
      _withdraw(RecapClientPhase.unavailable);
      _header = null;
      _id = null;
      _selection = const [];
      _command = null;
      _localFingerprint = null;
    }
  }

  void _localChanged() => invalidateSources();
  void _consentChanged() {
    if (_disposed) return;
    _error = const RecapClientException('AI_CONSENT_REQUIRED');
    _withdraw(RecapClientPhase.unavailable);
  }

  /// Committed source notifications withdraw immediately; every subsequent
  /// operation also re-reads SQLite instead of trusting notifications alone.
  void invalidateSources() {
    if (_disposed) return;
    _withdraw(RecapClientPhase.stale);
    _error = const RecapClientException('LOCAL_CHANGED');
    notifyListeners();
  }

  void setOnline(bool value) {
    if (_disposed || value == _online) return;
    _online = value;
    _withdraw(value ? RecapClientPhase.reconfirm : RecapClientPhase.offline);
  }

  /// Route leave, background, privacy overlay or consent change withdraws access.
  /// Re-entry requires an explicit online read; this does not start any polling.
  void suspend() => _withdraw(RecapClientPhase.reconfirm);

  void _withdraw(RecapClientPhase next) {
    _revokeContent();
    _epoch++;
    _abort?.cancel();
    _abort = null;
    _busy = false;
    _confirmedFingerprint = null;
    _confirmedRevision = null;
    _phase = next;
    if (!_disposed) notifyListeners();
  }

  void _revokeContent() {
    _content?._revoke();
    _content = null;
    _issuedDeadline = null;
    _displayTimer?.cancel();
    _displayTimer = null;
  }

  RecapOnlineContent _issueContent(
    Map<String, dynamic> data,
    int epoch,
    Duration deadline,
  ) {
    _check();
    if (!_online ||
        _deletionRequested ||
        epoch != _epoch ||
        _phase != RecapClientPhase.ready) {
      recapReject('CONFIRM_REQUIRED');
    }
    final remaining = deadline - monotonic();
    if (remaining <= Duration.zero) recapReject('RECAP_DISPLAY_EXPIRED');
    final content = RecapOnlineContent._(data, () {
      _check();
      if (!_online || epoch != _epoch || monotonic() >= deadline) {
        recapReject('CONFIRM_REQUIRED');
      }
    });
    _content = content;
    _issuedDeadline = deadline;
    _displayTimer = Timer(remaining, () {
      if (!_disposed && epoch == _epoch) _withdraw(RecapClientPhase.reconfirm);
    });
    notifyListeners();
    return content;
  }

  Future<RecapLocalProof> _inspect() async {
    _check();
    final proof = await localGuard.inspect(_session, bookId, _selection);
    _check();
    if (_localFingerprint != null && proof.fingerprint != _localFingerprint) {
      recapReject('LOCAL_CHANGED');
    }
    return proof;
  }

  Future<T> _run<T>(
    Future<T> Function(RecapLocalProof, RecapRequestAbort) action,
  ) async {
    _check();
    if (_deletionRequested) recapReject('RECAP_UNAVAILABLE');
    if (!_online) recapReject('OFFLINE');
    if (_busy) recapReject('BUSY');
    _revokeContent();
    final epoch = ++_epoch;
    final abort = RecapRequestAbort();
    _abort = abort;
    _busy = true;
    _phase = RecapClientPhase.checking;
    _error = null;
    notifyListeners();
    try {
      final before = await _inspect();
      if (epoch != _epoch) recapReject('CANCELLED');
      final result = await action(before, abort);
      _check();
      final after = await _inspect();
      if (epoch != _epoch || !_online || abort.cancelled) {
        recapReject('CANCELLED');
      }
      if (before.fingerprint != after.fingerprint) recapReject('LOCAL_CHANGED');
      return result;
    } catch (e) {
      final error = e is RecapClientException
          ? e
          : RecapClientException(
              e is StaleAuthSession ? 'AUTH_CHANGED' : 'NETWORK',
            );
      if (epoch == _epoch && !_disposed) {
        _error = error;
        if ([
              'NETWORK',
              'TIMEOUT',
              'INVALID_RESPONSE',
              'RECAP_INTERNAL_ERROR',
            ].contains(error.code) &&
            _command != null) {
          _uncertain = true;
        }
        _confirmedFingerprint = null;
        _confirmedRevision = null;
        _phase = switch (error.code) {
          'LOCAL_CHANGED' ||
          'RECAP_SOURCE_CHANGED' ||
          'RECAP_SCOPE_CHANGED' => RecapClientPhase.stale,
          'LOCAL_DELETED' ||
          'RECAP_UNAVAILABLE' ||
          'RECAP_EXPIRED' => RecapClientPhase.invalidated,
          'RECAP_REVISION_CONFLICT' => RecapClientPhase.reconfirm,
          'TIMEOUT' || 'NETWORK' || 'OFFLINE' => RecapClientPhase.offline,
          'CANCELLED' => RecapClientPhase.cancelled,
          'AUTH_CHANGED' ||
          'RECAP_AUTH_REQUIRED' ||
          'AI_CONSENT_REQUIRED' => RecapClientPhase.unavailable,
          _ => RecapClientPhase.failed,
        };
      }
      throw error;
    } finally {
      if (epoch == _epoch && !_disposed) {
        _busy = false;
        _abort = null;
        notifyListeners();
      }
    }
  }

  void _accept(Map<String, dynamic> data, RecapLocalProof proof) {
    final next = RecapHeader.parse(data);
    if (next.id != _id || next.bookId != bookId) {
      recapReject('RECAP_SCOPE_CHANGED');
    }
    proof.checkResolved(data['sources']);
    final old = _header;
    if (old != null && old.id == next.id) {
      if (old.sourceFingerprint != next.sourceFingerprint) {
        recapReject('RECAP_SOURCE_CHANGED');
      }
      if (BigInt.parse(next.revision) < BigInt.parse(old.revision)) {
        recapReject('RECAP_REVISION_CONFLICT');
      }
    }
    _header = next;
    _phase = switch (next.state) {
      RecapServerState.prepared => RecapClientPhase.confirmation,
      RecapServerState.generating => RecapClientPhase.running,
      RecapServerState.ready => RecapClientPhase.ready,
      RecapServerState.cancelled => RecapClientPhase.cancelled,
      RecapServerState.failed => RecapClientPhase.failed,
    };
  }

  Future<void> prepare(List<RecapLocalSelection> selection) async {
    _check();
    if (_busy) recapReject('BUSY');
    if (_uncertain) recapReject('CONFIRM_REQUIRED');
    _deletionRequested = false;
    _selection = List.unmodifiable(selection);
    _id = const Uuid().v4();
    _header = null;
    _localFingerprint = null;
    _command = null;
    _confirmedFingerprint = null;
    _confirmedRevision = null;
    await _run((proof, abort) async {
      _localFingerprint = proof.fingerprint;
      _command = _RecapCommand(const Uuid().v4(), 'prepare', {}, clock());
      final body = {
        'recap_id': _id,
        'request_id': _command!.requestId,
        'book_id': bookId,
        'selected_sources': proof.sources,
      };
      _command = _RecapCommand(_command!.requestId, 'prepare', body, clock());
      final data = await api.send(
        _session,
        'POST',
        'prepare',
        body: body,
        abort: abort,
      );
      await _validateAfter(proof, abort);
      _accept(data, proof);
    });
  }

  Future<void> _validateAfter(
    RecapLocalProof before,
    RecapRequestAbort abort,
  ) async {
    final after = await _inspect();
    if (before.fingerprint != after.fingerprint) recapReject('LOCAL_CHANGED');
    if (abort.cancelled || !_online) recapReject('CANCELLED');
  }

  /// No source selection is inferred from book title or server result prose.
  Future<void> open(
    String recapIdValue,
    List<RecapLocalSelection> selection, {
    String? expectedRevision,
    String? expectedFingerprint,
  }) async {
    _check();
    if (_busy) recapReject('BUSY');
    if (_uncertain || (_deletionRequested && recapIdValue == _id)) {
      recapReject('CONFIRM_REQUIRED');
    }
    _deletionRequested = false;
    _id = recapId(recapIdValue);
    _selection = List.unmodifiable(selection);
    _header = null;
    _localFingerprint = null;
    _command = null;
    _confirmedFingerprint = null;
    _confirmedRevision = null;
    await refresh();
    if ((expectedRevision != null && _header?.revision != expectedRevision) ||
        (expectedFingerprint != null &&
            _header?.sourceFingerprint != expectedFingerprint)) {
      _withdraw(RecapClientPhase.reconfirm);
      recapReject('RECAP_REVISION_CONFLICT');
    }
  }

  Future<Map<String, dynamic>> _get(
    RecapLocalProof proof,
    RecapRequestAbort abort,
  ) async {
    if (_id == null) recapReject('CONFIRM_REQUIRED');
    final data = await api.send(_session, 'GET', _id!, abort: abort);
    await _validateAfter(proof, abort);
    _localFingerprint ??= proof.fingerprint;
    _accept(data, proof);
    return data;
  }

  Future<void> refresh() => _run((p, a) async {
    await _get(p, a);
  });

  Map<String, dynamic> _displayVersion() {
    final h = _header;
    if (h == null || h.state != RecapServerState.ready) {
      recapReject('CONFIRM_REQUIRED');
    }
    return {
      'book_id': bookId,
      'expected_revision': h.revision,
      'expected_source_fingerprint': h.sourceFingerprint,
    };
  }

  Duration _displayDeadline(Map<String, dynamic> data, Duration started) {
    _check();
    if (_header == null) recapReject('CONFIRM_REQUIRED');
    final remaining = RecapDisplayGrant.parse(recapObject(data['display']))
        .remaining(
          header: _header!,
          approvedPolicies: approvedDisplayPolicies,
          now: clock(),
          elapsed: monotonic() - started,
          clientLimit: displayLifetime,
        );
    return monotonic() + remaining;
  }

  RecapOnlineContent _finishDisplay(
    Map<String, dynamic> body,
    Map<String, dynamic> permit,
    Duration started,
    int epoch,
  ) {
    try {
      return _issueContent(body, epoch, _displayDeadline(permit, started));
    } on RecapClientException catch (error) {
      if (!_disposed && epoch == _epoch) {
        _error = error;
        _withdraw(RecapClientPhase.reconfirm);
      }
      rethrow;
    }
  }

  /// Legacy GET can refresh status only. It never issues display permission.
  Future<RecapOnlineContent> readForDisplay() async {
    final response = await _run((p, a) async {
      await _get(p, a);
      if (_header?.state != RecapServerState.ready) {
        recapReject('RECAP_UNAVAILABLE');
      }
      final started = monotonic();
      final data = await api.send(
        _session,
        'POST',
        'display/$_id/view',
        body: _displayVersion(),
        abort: a,
      );
      recapKeys(data, ['recap', 'display']);
      final recap = recapObject(data['recap']);
      final received = RecapHeader.parse(recap);
      if (received.revision != _header!.revision ||
          received.sourceFingerprint != _header!.sourceFingerprint ||
          received.id != _id ||
          received.bookId != bookId) {
        recapReject('RECAP_REVISION_CONFLICT');
      }
      _accept(recap, p);
      return (recap, data, started, _epoch);
    });
    return _finishDisplay(response.$1, response.$2, response.$3, response.$4);
  }

  Future<RecapOnlineContent> evidenceForDisplay(List<String> ids) async {
    final requested = List<String>.unmodifiable(ids);
    if (requested.isEmpty ||
        requested.length > 24 ||
        requested.toSet().length != requested.length) {
      recapReject('INVALID_REQUEST');
    }
    requested.forEach(recapEvidenceId);
    final response = await _run((p, a) async {
      final started = monotonic();
      final data = await api.send(
        _session,
        'POST',
        'display/$_id/evidence',
        body: {..._displayVersion(), 'evidence_ids': requested},
        abort: a,
      );
      RecapEvidenceResponse.parse(
        data,
        header: _header,
        requestedIds: requested,
      );
      _phase = RecapClientPhase.ready;
      return (data, started, _epoch);
    });
    return _finishDisplay(response.$1, response.$1, response.$2, response.$3);
  }

  /// User-triggered renewal only, while the original in-memory lease is live.
  Future<RecapOnlineContent> renewDisplay() async {
    final old = _content;
    final deadline = _issuedDeadline;
    if (old == null || deadline == null) recapReject('CONFIRM_REQUIRED');
    final body = old.toJson();
    final response = await _run((p, a) async {
      final started = monotonic();
      final data = await api.send(
        _session,
        'POST',
        'display/$_id/validate',
        body: _displayVersion(),
        abort: a,
      );
      recapKeys(data, ['display']);
      if (monotonic() >= deadline) recapReject('RECAP_DISPLAY_EXPIRED');
      _phase = RecapClientPhase.ready;
      return (data, started, _epoch);
    });
    if (monotonic() >= deadline) {
      _withdraw(RecapClientPhase.reconfirm);
      recapReject('RECAP_DISPLAY_EXPIRED');
    }
    return _finishDisplay(body, response.$1, response.$2, response.$3);
  }

  Future<void> confirmScope({
    required String fingerprint,
    required String revision,
  }) async {
    await _run((p, a) async {
      await _get(p, a);
      if (_header?.state != RecapServerState.prepared ||
          fingerprint != _header?.sourceFingerprint ||
          revision != _header?.revision) {
        recapReject('CONFIRM_REQUIRED');
      }
      _confirmedFingerprint = fingerprint;
      _confirmedRevision = revision;
    });
  }

  Future<void> generate() async {
    if (_confirmedFingerprint == null ||
        _confirmedRevision != _header?.revision ||
        _confirmedFingerprint != _header?.sourceFingerprint) {
      recapReject('CONFIRM_REQUIRED');
    }
    await _mutate('generate', {
      'source_fingerprint': _confirmedFingerprint,
      'consent_scope_fingerprint': _confirmedFingerprint,
    });
  }

  Future<void> save() => _mutate('save', const {});

  Future<void> followUp(String question, {String? itemId}) {
    if (question.trim().isEmpty ||
        question.trim().length > 4000 ||
        (itemId != null && (itemId.isEmpty || itemId.length > 256))) {
      recapReject('INVALID_REQUEST');
    }
    return _mutate('follow-ups', {
      'question': question.trim(),
      'item_id': ?itemId,
    });
  }

  Future<void> feedback(
    String category, {
    String comment = '',
    String? itemId,
  }) {
    if (!['inaccurate', 'low_value', 'wrong_relation'].contains(category) ||
        comment.length > 1000 ||
        (itemId != null && (itemId.isEmpty || itemId.length > 256))) {
      recapReject('INVALID_REQUEST');
    }
    return _mutate('feedback', {
      'category': category,
      'comment': comment,
      'item_id': ?itemId,
    });
  }

  Future<void> _mutate(String action, Map<String, dynamic> extra) =>
      _run((p, a) async {
        if (_uncertain) recapReject('CONFIRM_REQUIRED');
        final header = _header;
        if (header == null ||
            (action != 'generate' && header.state != RecapServerState.ready)) {
          recapReject('CONFIRM_REQUIRED');
        }
        final requestId = const Uuid().v4();
        _command = _RecapCommand(requestId, '${header.id}/$action', {
          'request_id': requestId,
          'expected_revision': header.revision,
          ...extra,
        }, clock());
        await _execute(_command!, p, a);
      });

  Future<void> _execute(
    _RecapCommand command,
    RecapLocalProof p,
    RecapRequestAbort a,
  ) async {
    final data = await api.send(
      _session,
      'POST',
      command.path,
      body: command.body,
      abort: a,
    );
    await _validateAfter(p, a);
    if (command.path == 'prepare' || command.path.endsWith('/save')) {
      _accept(data, p);
      _uncertain = false;
      return;
    }
    if (command.path.endsWith('/feedback')) {
      recapKeys(data, ['id']);
      recapId(data['id']);
      await _get(p, a);
      _uncertain = false;
      return;
    }
    recapKeys(data, ['status', 'replay']);
    if (data['replay'] is! bool ||
        ![
          'running',
          'succeeded',
          'failed',
          'cancelled',
          'interrupted',
          'expired',
          'revoked',
        ].contains(data['status'])) {
      recapReject();
    }
    await _get(p, a);
    _uncertain = data['status'] == 'running';
    if (data['status'] == 'running') _phase = RecapClientPhase.running;
    if (!['running', 'succeeded'].contains(data['status'])) {
      _phase = data['status'] == 'cancelled'
          ? RecapClientPhase.cancelled
          : RecapClientPhase.failed;
    }
  }

  /// Explicit status recovery via the existing POST replay contract, not an
  /// invented operations GET endpoint. Exact ID/body stay unchanged in memory.
  Future<void> replay() => _run((p, a) async {
    final command = _command;
    if (command == null ||
        clock().difference(command.created) > replayLifetime) {
      recapReject('CONFIRM_REQUIRED');
    }
    await _execute(command, p, a);
  });

  Future<RecapOnlineContent> followUpsForDisplay() async {
    final response = await _run((p, a) async {
      await _get(p, a);
      if (_header?.state != RecapServerState.ready) {
        recapReject('RECAP_UNAVAILABLE');
      }
      final data = await api.send(_session, 'GET', '$_id/follow-ups', abort: a);
      await _validateAfter(p, a);
      validateRecapTurns(data, _header!);
      final started = monotonic();
      final permit = await api.send(
        _session,
        'POST',
        'display/$_id/validate',
        body: _displayVersion(),
        abort: a,
      );
      recapKeys(permit, ['display']);
      return (data, permit, started, _epoch);
    });
    return _finishDisplay(response.$1, response.$2, response.$3, response.$4);
  }

  /// Cleanup remains possible after local deletion or AI consent withdrawal.
  Future<void> cancel() async {
    _check();
    final command = _command;
    if (command == null ||
        !(command.path.endsWith('/generate') ||
            command.path.endsWith('/follow-ups'))) {
      recapReject('CONFIRM_REQUIRED');
    }
    _withdraw(RecapClientPhase.checking);
    if (!_online) {
      _phase = RecapClientPhase.offline;
      recapReject('OFFLINE');
    }
    final epoch = _epoch;
    _busy = true;
    try {
      await api.send(
        _session,
        'POST',
        '$_id/operations/${command.requestId}/cancel',
        body: const {},
      );
      _check();
      if (epoch != _epoch) recapReject('CANCELLED');
      _phase = RecapClientPhase.cancelled;
      _uncertain = false;
    } catch (e) {
      if (epoch == _epoch) {
        _phase = RecapClientPhase.reconfirm;
        _error = e is RecapClientException
            ? e
            : const RecapClientException('NETWORK');
      }
      rethrow;
    } finally {
      if (epoch == _epoch && !_disposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> delete() async {
    _check();
    if (_id == null) recapReject('CONFIRM_REQUIRED');
    _deletionRequested = true;
    _withdraw(RecapClientPhase.invalidated);
    final epoch = _epoch;
    if (!_online) recapReject('OFFLINE');
    _busy = true;
    try {
      await api.send(_session, 'DELETE', _id!, body: const {});
      _check();
      if (epoch != _epoch) recapReject('CANCELLED');
      _header = null;
      _command = null;
      _uncertain = false;
    } finally {
      if (epoch == _epoch && !_disposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _revokeContent();
    _disposed = true;
    _epoch++;
    _abort?.cancel();
    _command = null;
    _header = null;
    _selection = const [];
    AuthSessionScope.changes.removeListener(_sessionChanged);
    localChanges.removeListener(_localChanged);
    PrivacyService.aiConsentChanges.removeListener(_consentChanged);
    super.dispose();
  }
}
