import 'dart:convert';

const recapDisplayPolicy = 'reading-recap-v1';

class RecapClientException implements Exception {
  final String code;
  const RecapClientException(this.code);

  String get message => switch (code) {
    'LOCAL_PENDING' || 'LOCAL_IDENTITY_MISSING' => '阅读记录尚未同步，请先确认同步状态。',
    'LOCAL_CHANGED' ||
    'RECAP_SOURCE_CHANGED' ||
    'RECAP_SCOPE_CHANGED' => '原始资料已发生变化，请重新选择并确认。',
    'RECAP_REVISION_CONFLICT' => '回望已更新，请重新读取并确认后再操作。',
    'RECAP_SCOPE_NOT_READY' ||
    'RECAP_INSUFFICIENT_EVIDENCE' => '这次选中的材料不足以生成可靠回望。',
    'RECAP_HISTORY_BUDGET' ||
    'RECAP_INPUT_BUDGET' ||
    'RECAP_SCOPE_TOO_LARGE' => '所选材料或对话已达到本次处理上限，请缩小范围。',
    'AUTH_CHANGED' || 'RECAP_AUTH_REQUIRED' => '登录状态已变化，请重新登录后查看。',
    'AI_CONSENT_REQUIRED' => '请先确认本次云端 AI 分析授权。',
    'RECAP_UNAVAILABLE' ||
    'RECAP_EXPIRED' ||
    'LOCAL_DELETED' => '这份回望或原始资料已不可用。',
    'CANCELLED' => '已停止本次等待，取消结果以服务器确认为准。',
    'OFFLINE' || 'NETWORK' || 'TIMEOUT' => '网络异常，暂时无法查看回望。',
    'BUSY' || 'RECAP_BUSY' => '已有操作正在处理，请稍后再试。',
    'NOT_CONFIGURED' => '回望功能尚未开放。',
    'RECAP_PILOT_DISABLED' => '阅读回望暂未开放。',
    'RECAP_RATE_LIMIT' => '请求较频繁，请稍后再试。',
    'RECAP_BUDGET_OR_BUSY' => '本次生成暂不可用：已有请求在处理，或今日预算已用完。',
    'RECAP_COST_LIMIT' => '本次生成超出费用限制，或服务计价尚待确认。',
    'CONFIRM_REQUIRED' => '请先确认本次阅读材料范围。',
    'INVALID_SELECTION' => '请选择可核验的阅读材料，并确认追问范围。',
    'RECAP_DISPLAY_EXPIRED' => '本次查看已到期，请重新在线核验。',
    'RECAP_DISPLAY_POLICY_REQUIRED' => '回望尚未配置安全的查看方式，暂时无法展示。',
    'RECAP_DISPLAY_CLOCK_INVALID' => '暂时无法确认查看期限，请校准设备时间后重试。',
    _ => '暂时无法完成这次操作，请重新确认后再试。',
  };

  @override
  String toString() => message;
}

Never recapReject([String code = 'INVALID_RESPONSE']) =>
    throw RecapClientException(code);

String recapId(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
      ).hasMatch(value)) {
    recapReject('INVALID_ID');
  }
  return value;
}

String recapRevision(Object? value) {
  if (value is! String ||
      !RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(value) ||
      BigInt.parse(value) > BigInt.parse('9223372036854775807')) {
    recapReject();
  }
  return value;
}

String recapDigest(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    recapReject();
  }
  return value;
}

Map<String, dynamic> recapObject(Object? value) {
  if (value is! Map<String, dynamic>) recapReject();
  return value;
}

void recapKeys(Map<String, dynamic> value, List<String> keys) {
  if (value.length != keys.length || !keys.every(value.containsKey)) {
    recapReject();
  }
}

List<dynamic> recapList(Object? value, int max) {
  if (value is! List || value.length > max) recapReject();
  return value;
}

void recapCoverage(Object? value) {
  final c = recapObject(value);
  recapKeys(c, [
    'basis',
    'fullBook',
    'sourceCompleteness',
    'availableEntries',
    'includedEntries',
    'includedFollowUps',
    'quarantinedEntries',
    'selectionApplied',
  ]);
  if (c['basis'] != 'reading_traces' ||
      c['fullBook'] != false ||
      c['sourceCompleteness'] != 'server_selected_records' ||
      c['selectionApplied'] != true) {
    recapReject();
  }
  for (final k in [
    'availableEntries',
    'includedEntries',
    'includedFollowUps',
    'quarantinedEntries',
  ]) {
    if (c[k] is! int || (c[k] as int) < 0) recapReject();
  }
  if (c['includedEntries'] != c['availableEntries'] ||
      c['includedEntries'] > 80 ||
      c['includedFollowUps'] > 320 ||
      c['quarantinedEntries'] != 0) {
    recapReject();
  }
}

enum RecapServerState { prepared, generating, ready, failed, cancelled }

enum RecapClientPhase {
  idle,
  checking,
  confirmation,
  running,
  ready,
  failed,
  cancelled,
  stale,
  invalidated,
  offline,
  reconfirm,
  unavailable,
}

enum RecapFollowScope { all, none, selected }

/// Local IDs are never sent as remote IDs. Empty and all are distinct choices.
class RecapLocalSelection {
  final String localEntryId;
  final RecapFollowScope followScope;
  final List<String> followUpIds;
  RecapLocalSelection(
    this.localEntryId, {
    this.followScope = RecapFollowScope.none,
    List<String> followUpIds = const [],
  }) : followUpIds = List.unmodifiable(followUpIds) {
    if (localEntryId.isEmpty ||
        localEntryId.length > 256 ||
        followUpIds.length > 320 ||
        followUpIds.toSet().length != followUpIds.length ||
        (followScope == RecapFollowScope.selected) != followUpIds.isNotEmpty) {
      recapReject('INVALID_SELECTION');
    }
    for (final id in followUpIds) {
      recapId(id);
    }
  }
}

/// Header contains no generated prose and is safe to retain as a placeholder.
class RecapHeader {
  final String id, bookId, revision, sourceFingerprint;
  final RecapServerState state;
  final bool isSaved;
  final String _coverage;
  final String _sources;
  List<Map<String, dynamic>> get sources =>
      (jsonDecode(_sources) as List).map(recapObject).toList();
  Map<String, dynamic> get coverage => recapObject(jsonDecode(_coverage));
  RecapHeader._(
    this.id,
    this.bookId,
    this.revision,
    this.sourceFingerprint,
    this.state,
    this.isSaved,
    this._coverage,
    this._sources,
  );

  factory RecapHeader.parse(Map<String, dynamic> value) =>
      RecapHeader._parse(value, metadataOnly: false);

  /// Validates the body-free scope projection without manufacturing a result.
  factory RecapHeader.fromScope(Map<String, dynamic> value) =>
      RecapHeader._parse(value, metadataOnly: true);

  static RecapHeader _parse(
    Map<String, dynamic> value, {
    required bool metadataOnly,
  }) {
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
      if (!metadataOnly) 'result',
      'scope_basis',
      'local_pending_verified',
    ]);
    if (value['book_id'] is! String ||
        (value['book_id'] as String).isEmpty ||
        value['is_saved'] is! bool ||
        value['local_pending_verified'] != false ||
        value['scope_basis'] != 'selected_cloud_records_only') {
      recapReject();
    }
    final states = RecapServerState.values.where(
      (s) => s.name == value['state'],
    );
    if (states.length != 1) recapReject();
    final state = states.single;
    if ((metadataOnly && state != RecapServerState.ready) ||
        (!metadataOnly &&
            (state == RecapServerState.ready) != (value['result'] != null)) ||
        (value['is_saved'] == true && state != RecapServerState.ready)) {
      recapReject();
    }
    recapCoverage(value['coverage']);
    final sources = recapList(value['sources'], 80);
    final ids = <String>{};
    var follows = 0;
    for (final source in sources) {
      final s = recapObject(source);
      recapKeys(s, ['entry_id', 'follow_up_ids']);
      if (!ids.add(recapId(s['entry_id']))) recapReject();
      final f = recapList(s['follow_up_ids'], 320).map(recapId).toList();
      if (f.toSet().length != f.length) recapReject();
      follows += f.length;
    }
    final coverage = recapObject(value['coverage']);
    if (ids.length != coverage['includedEntries'] ||
        follows != coverage['includedFollowUps']) {
      recapReject();
    }
    final summary = recapObject(value['evidence_summary']);
    recapKeys(summary, ['transmitted', 'excluded_unverified']);
    for (final k in summary.keys) {
      if (summary[k] is! int || summary[k] < 0) recapReject();
    }
    final fingerprint = recapDigest(value['source_fingerprint']);
    if (value['result'] != null) {
      validateRecapResult(value['result'], fingerprint);
    }
    return RecapHeader._(
      recapId(value['id']),
      value['book_id'],
      recapRevision(value['revision']),
      fingerprint,
      state,
      value['is_saved'],
      jsonEncode(coverage),
      jsonEncode(sources),
    );
  }
}

void _text(Object? value, int max) {
  if (value is! String || value.trim().isEmpty || value.length > max) {
    recapReject();
  }
}

void _evidence(Map<String, dynamic> item) {
  if (![
    'source_supported',
    'user_explicit',
    'ai_inference',
  ].contains(item['basis'])) {
    recapReject();
  }
  final refs = recapList(item['evidenceRefs'], 24);
  if (refs.isEmpty || refs.toSet().length != refs.length) recapReject();
  for (final ref in refs) {
    _text(ref, 256);
  }
  if (item.containsKey('quotes')) {
    for (final quote in recapList(item['quotes'], 8)) {
      final q = recapObject(quote);
      recapKeys(q, ['evidenceId', 'text', 'voice']);
      _text(q['text'], 2000);
      if (!refs.contains(q['evidenceId']) ||
          !['author', 'user', 'historical_ai'].contains(q['voice'])) {
        recapReject();
      }
    }
  }
}

/// Structural defense only. Without server evidence text, this cannot prove a quote.
void validateRecapResult(Object? value, String fingerprint) {
  final result = recapObject(value);
  recapKeys(result, [
    'schemaVersion',
    'snapshotFingerprint',
    'knowledge',
    'relations',
    'myThinking',
    'openQuestions',
    'nextQuestions',
  ]);
  if (result['schemaVersion'] != 1 ||
      result['snapshotFingerprint'] != fingerprint) {
    recapReject();
  }
  final ids = <String>{}, knowledge = <String>{};
  for (final group in [
    'knowledge',
    'myThinking',
    'openQuestions',
    'nextQuestions',
  ]) {
    for (final raw in recapList(
      result[group],
      group == 'nextQuestions' ? 3 : 12,
    )) {
      final item = recapObject(raw);
      recapKeys(item, [
        'id',
        'title',
        'summary',
        'basis',
        'evidenceRefs',
        'quotes',
        if (group == 'knowledge') 'kind',
      ]);
      _text(item['id'], 256);
      _text(item['title'], 3000);
      _text(item['summary'], 3000);
      if (!ids.add(item['id'])) recapReject();
      if (group == 'knowledge') {
        if (!['concept', 'viewpoint', 'argument'].contains(item['kind'])) {
          recapReject();
        }
        knowledge.add(item['id']);
      }
      _evidence(item);
    }
  }
  for (final raw in recapList(result['relations'], 16)) {
    final item = recapObject(raw);
    recapKeys(item, [
      'id',
      'from',
      'to',
      'type',
      'explanation',
      'basis',
      'evidenceRefs',
    ]);
    _text(item['id'], 256);
    _text(item['explanation'], 3000);
    if (!ids.add(item['id']) ||
        !knowledge.contains(item['from']) ||
        !knowledge.contains(item['to']) ||
        ![
          'supports',
          'conflicts',
          'complements',
          'compares',
          'unconfirmed',
        ].contains(item['type'])) {
      recapReject();
    }
    _evidence(item);
  }
}

void validateRecapTurns(Map<String, dynamic> value, RecapHeader header) {
  recapKeys(value, [
    'revision',
    'source_fingerprint',
    'coverage',
    'local_pending_verified',
    'turns',
  ]);
  recapCoverage(value['coverage']);
  if (value['revision'] != header.revision ||
      value['source_fingerprint'] != header.sourceFingerprint ||
      value['local_pending_verified'] != false ||
      jsonEncode(value['coverage']) != jsonEncode(header.coverage)) {
    recapReject('RECAP_REVISION_CONFLICT');
  }
  var index = 0;
  for (final raw in recapList(value['turns'], 64)) {
    final turn = recapObject(raw);
    recapKeys(turn, ['turn', 'question', 'answer']);
    if (turn['turn'] != ++index) recapReject();
    _text(turn['question'], 4000);
    final answer = recapObject(turn['answer']);
    recapKeys(answer, ['schemaVersion', 'snapshotFingerprint', 'parts']);
    if (answer['schemaVersion'] != 1 ||
        answer['snapshotFingerprint'] != header.sourceFingerprint) {
      recapReject();
    }
    final parts = recapList(answer['parts'], 8);
    if (parts.isEmpty) recapReject();
    for (final rawPart in parts) {
      final part = recapObject(rawPart);
      recapKeys(part, ['text', 'basis', 'evidenceRefs', 'quotes']);
      _text(part['text'], 3000);
      _evidence(part);
    }
  }
}
