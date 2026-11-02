import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/theme.dart';
import '../../providers/book_recap_controller.dart';
import '../../services/auth_session_scope.dart';
import '../../services/book_recap_client_api.dart';
import '../../services/book_recap_client_contract.dart';
import '../../services/book_recap_display_contract.dart';
import '../../services/book_recap_display_repository.dart';
import '../../services/book_recap_local_guard.dart';
import '../../services/book_recap_material_catalog.dart';
import '../../services/privacy_service.dart';
import 'widgets/book_recap_editorial.dart';

/// Deliberately has no app defaults, production endpoint or display-window policy.
/// Composition must provide the existing consent gate, connectivity signal and
/// the observer installed on its Navigator. No body is persisted by this feature.
class BookRecapWorkspace {
  final AuthSessionScope session;
  final BookRecapClientApi api;
  final BookRecapMaterialCatalog catalog;
  final BookRecapLocalGuard guard;
  final ValueListenable<bool> online;
  final Listenable localChanges;
  final Duration displayLifetime;
  final Set<String> approvedPolicies;
  final Future<bool> Function(BuildContext) consentGate;
  final RouteObserver<ModalRoute<void>> routeObserver;
  final Duration Function()? monotonic;
  BookRecapWorkspace({
    required this.session,
    required this.api,
    required this.catalog,
    required this.guard,
    required this.online,
    required this.localChanges,
    required this.displayLifetime,
    required Set<String> approvedPolicies,
    required this.consentGate,
    required this.routeObserver,
    this.monotonic,
  }) : approvedPolicies = Set.unmodifiable(approvedPolicies);

  BookRecapDisplayRepository get repository =>
      BookRecapDisplayRepository(api: api, session: session);

  BookRecapController controller(String bookId) => BookRecapController(
    api: api,
    localGuard: guard,
    bookId: bookId,
    session: session,
    localChanges: localChanges,
    displayLifetime: displayLifetime,
    approvedDisplayPolicies: approvedPolicies,
    monotonic: monotonic,
  )..setOnline(online.value);
}

/// Inject into XiaouHomeScreen only in an explicitly configured isolated host.
class BookRecapEntry extends StatelessWidget {
  final BookRecapWorkspace workspace;
  const BookRecapEntry({super.key, required this.workspace});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.auto_stories_outlined,
        color: context.appPalette.primaryDark,
      ),
      title: const Text('阅读回望'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BookRecapScreen(workspace: workspace),
        ),
      ),
    ),
  );
}

enum _Pane { books, materials, confirm, detail, evidence, discussion, history }

class BookRecapScreen extends StatefulWidget {
  final BookRecapWorkspace workspace;
  const BookRecapScreen({super.key, required this.workspace});
  @override
  State<BookRecapScreen> createState() => _BookRecapScreenState();
}

class _BookRecapScreenState extends State<BookRecapScreen>
    with WidgetsBindingObserver, RouteAware {
  BookRecapWorkspace get w => widget.workspace;
  BookRecapController? _controller;
  _Pane _pane = _Pane.books;
  List<RecapBookChoice> _books = [];
  List<RecapMaterialChoice> _materials = [];
  List<RecapHistoryItem> _history = [];
  Map<String, String> _bookNames = {};
  final _selected = <String>{};
  final _followModes = <String, RecapFollowScope>{};
  final _followIds = <String, Set<String>>{};
  final _collapsed = <String>{};
  final _question = TextEditingController();
  final _feedback = TextEditingController();
  final _scroll = ScrollController(keepScrollOffset: false);
  String? _bookId, _cursor, _notice, _error;
  String _filter = 'all', _feedbackCategory = 'inaccurate';
  bool _busy = false, _visible = true, _restore = false, _showFeedback = false;
  bool _showMore = false;
  bool _showContents = false;
  int? _positionPaintEpoch;
  ({
    String id,
    String book,
    String revision,
    String fingerprint,
    double offset,
  })?
  _evidenceReturn;
  final _sectionKeys = List.generate(3, (_) => GlobalKey());
  String? _deleteCandidate;
  int _epoch = 0;
  RecapRequestAbort? _abort;
  ModalRoute<void>? _route;

  bool get _current => mounted && w.session.isCurrent;
  bool get _available => _current && _visible && w.online.value;
  bool get _working => _busy || (_controller?.busy ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AuthSessionScope.changes.addListener(_authChanged);
    w.online.addListener(_networkChanged);
    w.localChanges.addListener(_sourcesChanged);
    PrivacyService.aiConsentChanges.addListener(_consentChanged);
    unawaited(_action(_loadBooks));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (_route != route) {
      if (_route != null) w.routeObserver.unsubscribe(this);
      _route = route;
      if (route != null) w.routeObserver.subscribe(this, route);
    }
  }

  void _controllerChanged() {
    if (_controller?.content == null) {
      if (!_working) _evidenceReturn = null;
      _showContents = false;
      _question.clear();
      _feedback.clear();
      _showFeedback = false;
    }
    if (mounted) setState(() {});
  }

  void _clearLocalText() {
    _positionPaintEpoch = null;
    _evidenceReturn = null;
    _books = [];
    _bookNames = {};
    _materials = [];
    _selected.clear();
    _followModes.clear();
    _followIds.clear();
    _collapsed.clear();
    _question.clear();
    _feedback.clear();
    _showFeedback = false;
    _showMore = false;
    _showContents = false;
    _deleteCandidate = null;
  }

  void _withdraw(String message, {bool hide = false}) {
    _epoch++;
    _abort?.cancel();
    _abort = null;
    _controller?.suspend();
    _clearLocalText();
    _busy = false;
    _error = message;
    _notice = null;
    if (hide) _visible = false;
    if (mounted) setState(() {});
  }

  void _authChanged() {
    if (!w.session.isCurrent) {
      _withdraw(const RecapClientException('AUTH_CHANGED').message);
      _history = [];
      _cursor = null;
    }
  }

  void _networkChanged() {
    _controller?.setOnline(w.online.value);
    _withdraw(w.online.value ? '网络已恢复，请重新核验后查看。' : '网络异常，暂时无法查看回望。');
  }

  void _sourcesChanged() => _withdraw('原始资料已发生变化，请重新选择并确认。');
  void _consentChanged() => _withdraw('云端 AI 授权状态已变化，请重新确认。');
  @override
  void didPushNext() => _withdraw('返回后请重新核验。', hide: true);
  @override
  void didPopNext() {
    if (mounted) setState(() => _visible = true);
  }

  @override
  void didPop() => _withdraw('已离开回望。', hide: true);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _withdraw('回到前台后请重新核验。', hide: true);
    } else if (mounted) {
      setState(() => _visible = _route?.isCurrent ?? true);
    }
  }

  void _check(int epoch) {
    if (!_available || epoch != _epoch) recapReject('CANCELLED');
    w.session.check();
  }

  Future<void> _action(Future<void> Function(int) action) async {
    if (_working) return;
    if (!_available) {
      if (mounted) {
        setState(() => _error = const RecapClientException('OFFLINE').message);
      }
      return;
    }
    final epoch = ++_epoch;
    _busy = true;
    _error = null;
    _notice = null;
    setState(() {});
    try {
      await action(epoch);
      _check(epoch);
    } catch (e) {
      if (mounted && epoch == _epoch) {
        _error = e is RecapClientException
            ? e.message
            : const RecapClientException('NETWORK').message;
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  Future<void> _loadBooks(int epoch) async {
    _controller?.suspend();
    final books = await w.catalog.books(w.session);
    _check(epoch);
    _books = books;
    _pane = _Pane.books;
  }

  Future<void> _ensureConsent(int epoch) async {
    final accepted = await w.consentGate(context);
    // The real consent dialog covers this route and therefore revokes its old
    // context. Do not resume a captured selection after that privacy boundary.
    if (accepted && epoch != _epoch && _available) {
      setState(() {
        _error = null;
        _notice = '授权已确认，请重新选择并核验本次材料。';
      });
    }
    if (!accepted) recapReject('AI_CONSENT_REQUIRED');
    _check(epoch);
  }

  void _attachController(String bookId) {
    _controller?.removeListener(_controllerChanged);
    _controller?.dispose();
    _controller = w.controller(bookId)..addListener(_controllerChanged);
    _bookId = bookId;
  }

  Future<void> _chooseBook(String bookId, int epoch) async {
    final title =
        _bookNames[bookId] ??
        _books.where((b) => b.id == bookId).firstOrNull?.title;
    _controller?.suspend();
    _clearLocalText();
    final materials = await w.catalog.materials(w.session, bookId);
    _check(epoch);
    _attachController(bookId);
    _materials = materials;
    if (title != null) _bookNames[bookId] = title;
    _collapsed.addAll(
      materials.where((m) => m.preview.length > 160).map((m) => m.localId),
    );
    _pane = _Pane.materials;
    _filter = 'all';
    _restore = false;
  }

  Future<void> _prepare(int epoch) async {
    final selections = _materials
        .where((m) => _selected.contains(m.localId))
        .map((m) {
          final mode = _followModes[m.localId] ?? RecapFollowScope.none;
          return RecapLocalSelection(
            m.localId,
            followScope: mode,
            followUpIds: mode == RecapFollowScope.selected
                ? (_followIds[m.localId] ?? {}).toList()
                : [],
          );
        })
        .toList();
    if (selections.isEmpty) recapReject('INVALID_SELECTION');
    await _ensureConsent(epoch);
    await _controller!.prepare(selections);
    _check(epoch);
    _pane = _Pane.confirm;
  }

  Future<void> _generate(int epoch) async {
    await _ensureConsent(epoch);
    final c = _controller!;
    final h = c.header!;
    await c.confirmScope(
      fingerprint: h.sourceFingerprint,
      revision: h.revision,
    );
    _check(epoch);
    _pane = _Pane.detail;
    setState(() {});
    await c.generate();
    _check(epoch);
    if (c.phase == RecapClientPhase.ready) await c.readForDisplay();
  }

  Future<void> _historyPage(int epoch, {bool next = false}) async {
    _controller?.suspend();
    _clearLocalText();
    _pane = _Pane.history;
    _abort = RecapRequestAbort();
    final page = await w.repository.history(
      cursor: next ? _cursor : null,
      abort: _abort,
    );
    _check(epoch);
    // Pagination is not snapshot-consistent. Upsert repeated IDs instead of
    // rendering duplicate rows after a concurrent save on another device.
    final items = {
      if (next)
        for (final item in _history) item.id: item,
    };
    for (final item in page.items) {
      items[item.id] = item;
    }
    _history = items.values.toList();
    _cursor = page.nextCursor;
    // Titles are a local display association by stable ID, not remote identity.
    // Missing or unqueryable local books do not prevent privacy deletion.
    try {
      final books = await w.catalog.books(w.session);
      _check(epoch);
      _bookNames = {for (final book in books) book.id: book.title};
    } on RecapClientException {
      _check(epoch);
    }
  }

  Future<void> _restoreHistory(RecapHistoryItem item, int epoch) async {
    if (item.state != RecapHistoryState.ready) recapReject('RECAP_UNAVAILABLE');
    final title = _bookNames[item.bookId];
    _controller?.suspend();
    _clearLocalText();
    _abort = RecapRequestAbort();
    final scope = await w.repository.scope(item.id, abort: _abort);
    _check(epoch);
    final selection = await w.catalog.restoreSelection(
      w.session,
      scope.header.bookId,
      scope.header.sources,
    );
    _check(epoch);
    _attachController(scope.header.bookId);
    if (title != null) _bookNames[scope.header.bookId] = title;
    await _controller!.open(
      item.id,
      selection,
      expectedRevision: scope.header.revision,
      expectedFingerprint: scope.header.sourceFingerprint,
    );
    _check(epoch);
    _restore = true;
    _pane = _Pane.confirm;
  }

  Future<void> _read(int epoch) async {
    final location = _evidenceReturn;
    _evidenceReturn = null;
    _pane = _Pane.detail;
    await _controller!.readForDisplay();
    _check(epoch);
    if (location == null) return;
    final header = _controller!.header;
    if (header?.id != location.id ||
        header?.bookId != location.book ||
        header?.revision != location.revision ||
        header?.sourceFingerprint != location.fingerprint) {
      _controller!.suspend();
      recapReject('RECAP_SOURCE_CHANGED');
    }
    // Only a fresh, same-version display grant can restore this numeric offset.
    _positionPaintEpoch = epoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_available &&
          epoch == _epoch &&
          _body() != null &&
          _scroll.hasClients) {
        _scroll.jumpTo(
          location.offset.clamp(0.0, _scroll.position.maxScrollExtent),
        );
      }
      if (mounted && _positionPaintEpoch == epoch) {
        setState(() => _positionPaintEpoch = null);
      }
    });
  }

  Future<void> _showEvidence(List<String> ids, int epoch) async {
    final header = _controller!.header;
    _evidenceReturn =
        _pane == _Pane.detail &&
            _body() != null &&
            header != null &&
            _scroll.hasClients
        ? (
            id: header.id,
            book: header.bookId,
            revision: header.revision,
            fingerprint: header.sourceFingerprint,
            offset: _scroll.offset,
          )
        : null;
    _pane = _Pane.evidence;
    try {
      await _controller!.evidenceForDisplay(ids);
      _check(epoch);
    } catch (_) {
      _evidenceReturn = null;
      rethrow;
    }
  }

  Future<void> _discussion(int epoch) async {
    _pane = _Pane.discussion;
    await _controller!.followUpsForDisplay();
    _check(epoch);
  }

  Future<void> _askItem(String itemId, int epoch) async {
    final body = _body();
    final header = _controller?.header;
    if (body == null || header == null || body['result'] == null) {
      recapReject('CONFIRM_REQUIRED');
    }
    final items = recapObject(body['result'])['nextQuestions'] as List;
    final item = items.map(recapObject).singleWhere((v) => v['id'] == itemId);
    final question = item['title'] as String;
    // A short-lived draft crosses the request only after the same source/revision
    // is verified again. It is never retained if the new display grant fails.
    await _discussion(epoch);
    _check(epoch);
    if (_body() == null ||
        _controller?.header?.revision != header.revision ||
        _controller?.header?.sourceFingerprint != header.sourceFingerprint) {
      recapReject('RECAP_REVISION_CONFLICT');
    }
    _question.text = question;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _body() != null && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _sendQuestion(int epoch) async {
    await _ensureConsent(epoch);
    final question = _question.text;
    await _controller!.followUp(question);
    _check(epoch);
    _question.clear();
    if (_controller!.phase == RecapClientPhase.ready) await _discussion(epoch);
  }

  Future<void> _delete(String id, int epoch) async {
    _controller?.suspend();
    _showFeedback = false;
    _abort = RecapRequestAbort();
    await w.repository.delete(id, abort: _abort);
    _check(epoch);
    await _historyPage(epoch);
    _notice = '回望已删除，原始阅读记录保持不变。';
  }

  Future<void> _cancel() async {
    final c = _controller;
    if (c == null) return;
    ++_epoch;
    _busy = false;
    try {
      await c.cancel();
    } catch (e) {
      if (_current) {
        _error = e is RecapClientException ? e.message : '暂时无法确认取消结果，请稍后重试。';
      }
    }
    if (mounted) setState(() {});
  }

  Map<String, dynamic>? _body() {
    if (!_available) return null;
    try {
      return _controller?.content?.toJson();
    } on RecapClientException {
      return null;
    }
  }

  Widget _command(
    String label,
    IconData icon,
    Future<void> Function(int) action, {
    bool enabled = true,
  }) => TextButton.icon(
    style: TextButton.styleFrom(
      foregroundColor: _accent,
      textStyle: _style(14, weight: FontWeight.w500),
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    onPressed: _working || !enabled || !_available
        ? null
        : () => _action(action),
    icon: Icon(icon, size: 18),
    label: Text(label),
  );

  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _paper =>
      _dark ? Theme.of(context).colorScheme.surface : const Color(0xFFFAFAF7);
  Color get _ink =>
      _dark ? Theme.of(context).colorScheme.onSurface : const Color(0xFF292D32);
  Color get _muted => _dark
      ? Theme.of(context).colorScheme.onSurfaceVariant
      : const Color(0xFF666E77);
  Color get _accent =>
      _dark ? const Color(0xFF89CFF0) : context.appPalette.primaryDeep;
  Color get _line => _ink.withValues(alpha: .12);
  Color get _soft => _dark
      ? Theme.of(context).colorScheme.surfaceContainer
      : const Color(0xFFF0F5F7);

  void _revealControls(VoidCallback update) {
    setState(update);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  TextStyle _style(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    double height = 1.6,
  }) => Theme.of(context).textTheme.bodyMedium!.copyWith(
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: 0,
    color: color ?? _ink,
  );

  Widget _primary(
    String label,
    Future<void> Function(int) action, {
    bool enabled = true,
  }) => FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: const Color(0xFF89CFF0),
      foregroundColor: const Color(0xFF243C4A),
      minimumSize: const Size.fromHeight(48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: _style(15, weight: FontWeight.w600),
    ),
    onPressed: _working || !_available || !enabled
        ? null
        : () => _action(action),
    child: Text(label, textAlign: TextAlign.center),
  );

  Widget _caption(String text) => Text(text, style: _style(13, color: _muted));

  Widget _status(String text, {bool error = false}) => Semantics(
    liveRegion: error,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.info_outline : Icons.auto_stories_outlined,
            size: 18,
            color: _muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              key: error ? const Key('recap-notice') : null,
              style: _style(13, color: _muted),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _bookHeader({String? subtitle}) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 48,
          decoration: BoxDecoration(
            color: _soft,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(Icons.menu_book_outlined, color: _accent, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _bookNames[_bookId] ?? '所选书籍',
                style: _style(17, weight: FontWeight.w600),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                _caption(subtitle),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _bottomActions() {
    if (!_available) return const SizedBox.shrink();
    Widget? action;
    if (_pane == _Pane.materials) {
      action = _primary('确认所选材料', _prepare, enabled: _selected.isNotEmpty);
    } else if (_pane == _Pane.confirm && _controller?.header != null) {
      action = _primary(
        _restore ? '核验并查看回望' : '生成回望',
        _restore ? _read : _generate,
      );
    } else if (_pane == _Pane.detail && _body() != null) {
      final c = _controller!;
      final save = _command(
        c.header?.isSaved == true ? '已保存' : '保存回望',
        Icons.bookmark_border,
        (e) async {
          await c.save();
          _check(e);
          await _read(e);
        },
        enabled: c.header?.isSaved != true,
      );
      final ask = FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: _dark
              ? const Color(0xFF244451)
              : const Color(0xFFE0EFF5),
          foregroundColor: _dark
              ? const Color(0xFFB9E5F7)
              : const Color(0xFF345C6B),
          minimumSize: const Size.fromHeight(46),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: _style(14),
        ),
        onPressed: _working ? null : () => _action(_discussion),
        child: const Text('继续追问'),
      );
      action = MediaQuery.textScalerOf(context).scale(14) > 20
          ? Column(mainAxisSize: MainAxisSize.min, children: [save, ask])
          : Row(
              children: [
                Expanded(child: save),
                const SizedBox(width: 12),
                Expanded(child: ask),
              ],
            );
    }
    if (action == null) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _paper,
        border: Border(top: BorderSide(color: _line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: action,
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 12),
    child: Text(text, style: _style(20, weight: FontWeight.w600, height: 1.4)),
  );
  Widget _text(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: _style(15)),
  );

  @override
  Widget build(BuildContext context) {
    final editorial = _pane == _Pane.detail;
    return PopScope<Object?>(
      canPop: !_showContents,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _controller?.suspend();
        if (!didPop && _showContents) setState(() => _showContents = false);
      },
      child: _editorialLayers(
        Scaffold(
          backgroundColor: _paper,
          appBar: AppBar(
            leading: BackButton(
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
            centerTitle: false,
            titleSpacing: 20,
            elevation: 0,
            scrolledUnderElevation: 0,
            foregroundColor: _ink,
            titleTextStyle: _style(
              editorial ? 14 : 22,
              weight: FontWeight.w600,
              height: 1.3,
            ),
            title: Text(
              switch (_pane) {
                _Pane.materials => '选择阅读材料',
                _Pane.confirm => '确认阅读范围',
                _Pane.history => '我的回望',
                _Pane.evidence => '阅读回望',
                _Pane.discussion => '继续追问',
                _ => '阅读回望',
              },
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: _paper,
            actions: [
              if (editorial && _body() != null)
                IconButton(
                  tooltip: '章节目录',
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _working
                      ? null
                      : () => setState(() => _showContents = true),
                  icon: const Icon(Icons.format_list_bulleted, size: 20),
                ),
              if (_pane != _Pane.history && !editorial)
                IconButton(
                  tooltip: '我的回望',
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _working || !_available
                      ? null
                      : () => _action(_historyPage),
                  icon: const Icon(Icons.history),
                ),
              if (_pane == _Pane.detail ||
                  _pane == _Pane.evidence ||
                  _pane == _Pane.discussion)
                IconButton(
                  tooltip: '更多操作',
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  icon: const Icon(Icons.more_horiz),
                  onPressed: _available && !_working
                      ? () => _revealControls(() => _showMore = !_showMore)
                      : null,
                ),
            ],
          ),
          bottomNavigationBar: _bottomActions(),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  controller: _scroll,
                  key: ValueKey('recap-scroll-${_pane.name}'),
                  padding: editorial
                      ? const EdgeInsets.fromLTRB(0, 8, 0, 24)
                      : const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    if (_working) ...[
                      const LinearProgressIndicator(minHeight: 2),
                      const SizedBox(height: 12),
                      _caption('正在核验与处理所选材料…'),
                    ],
                    if (_error != null) _status(_error!, error: true),
                    if (_notice != null) _text(_notice!),
                    if (_deleteCandidate != null && _available) ...[
                      _heading('删除这份回望？'),
                      _text('回望、专属追问与反馈将被删除，原始阅读记录保持不变。'),
                      Wrap(
                        spacing: 8,
                        children: [
                          _command(
                            '确认删除',
                            Icons.delete_outline,
                            (e) => _delete(_deleteCandidate!, e),
                          ),
                          TextButton(
                            onPressed: _working
                                ? null
                                : () => setState(() => _deleteCandidate = null),
                            child: Text(
                              '保留回望',
                              style: _style(14, color: _accent),
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                    ],
                    if (!_current)
                      const Text('登录状态已变化，请返回后重新进入。')
                    else if (!_available)
                      const Text('暂不展示私人内容。联网并返回页面后，请重新核验。')
                    else
                      ..._content(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content() => switch (_pane) {
    _Pane.books => _bookList(),
    _Pane.materials => _materialList(),
    _Pane.confirm => _confirmation(),
    _Pane.history => _historyList(),
    _ => _privateContent(),
  };

  List<Widget> _bookList() => [
    _heading('从一本书开始'),
    if (_books.isEmpty && !_working) _status('还没有可选择的阅读材料。'),
    for (final book in _books)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.menu_book_outlined),
        title: Text(book.title),
        trailing: const Icon(Icons.chevron_right),
        onTap: _working ? null : () => _action((e) => _chooseBook(book.id, e)),
      ),
    _command('刷新书籍', Icons.refresh, _loadBooks),
  ];

  static const _kinds = {
    'highlight': '划线',
    'thought': '想法',
    'manual': '想法',
    'ai_explanation': 'AI 解读',
    'ai_question': '提问',
  };
  List<Widget> _materialList() => [
    _bookHeader(
      subtitle:
          '已选择 ${_selected.length} 条 · 可用 ${_materials.where((m) => m.unavailableReason == null).length} 条',
    ),
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in [
            'all',
            'highlight',
            'thought',
            'ai_explanation',
            'ai_question',
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(filter == 'all' ? '全部' : _kinds[filter]!),
                showCheckmark: false,
                labelStyle: _style(
                  13,
                  weight: _filter == filter ? FontWeight.w600 : FontWeight.w400,
                  color: _filter == filter ? _accent : _muted,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                selectedColor: _soft,
                backgroundColor: _paper,
                side: BorderSide(
                  color: _filter == filter
                      ? _accent.withValues(alpha: .4)
                      : _line,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                selected: _filter == filter,
                onSelected: _working
                    ? null
                    : (_) => setState(() => _filter = filter),
              ),
            ),
        ],
      ),
    ),
    const SizedBox(height: 8),
    if (_materials.isEmpty && !_working) _status('暂无可核验材料，请刷新或选择其他书籍。'),
    for (final m in _materials.where(
      (m) =>
          _filter == 'all' ||
          m.kind == _filter ||
          (_filter == 'thought' && m.kind == 'manual'),
    ))
      ..._material(m),
    Wrap(
      spacing: 8,
      children: [
        _command('刷新材料', Icons.refresh, (e) => _chooseBook(_bookId!, e)),
        _command('选择其他书籍', Icons.menu_book_outlined, _loadBooks),
      ],
    ),
  ];

  List<Widget> _material(RecapMaterialChoice m) => [
    Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: _selected.contains(m.localId) ? _soft : _paper,
        border: Border.all(
          color: _selected.contains(m.localId)
              ? _accent.withValues(alpha: .4)
              : _line,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            key: ValueKey('material-${m.localId}'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            activeColor: _accent,
            checkColor: _dark ? const Color(0xFF243C4A) : Colors.white,
            title: Text(
              _kinds[m.kind] ?? '阅读记录',
              style: _style(13, weight: FontWeight.w600, color: _accent),
            ),
            value: _selected.contains(m.localId),
            subtitle: m.unavailableReason == null
                ? null
                : _caption(m.unavailableReason!),
            onChanged: _working || m.unavailableReason != null
                ? null
                : (v) => setState(() {
                    if (v == true) {
                      _selected.add(m.localId);
                    } else {
                      _selected.remove(m.localId);
                    }
                  }),
          ),
          if (m.preview.isNotEmpty)
            Text(
              m.preview,
              style: _style(14, color: _muted),
              maxLines: _collapsed.contains(m.localId) ? 6 : null,
              overflow: _collapsed.contains(m.localId)
                  ? TextOverflow.ellipsis
                  : TextOverflow.visible,
            ),
          if (m.preview.isNotEmpty)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: _accent,
                textStyle: _style(12),
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
              ),
              onPressed: () => setState(() {
                if (!_collapsed.add(m.localId)) _collapsed.remove(m.localId);
              }),
              child: Text(_collapsed.contains(m.localId) ? '展开原文' : '收起原文'),
            ),
          if (m.userText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              m.kind == 'ai_question' ? '我的问题' : '我的表达',
              style: _style(12, color: _muted),
            ),
            const SizedBox(height: 4),
            _text(m.userText),
          ],
          if (_selected.contains(m.localId) && m.followUps.isNotEmpty) ...[
            DropdownButtonFormField<RecapFollowScope>(
              isExpanded: true,
              style: _style(14),
              initialValue: _followModes[m.localId] ?? RecapFollowScope.none,
              decoration: InputDecoration(
                labelText: '追问范围',
                labelStyle: _style(13, color: _muted),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              items: const [
                DropdownMenuItem(
                  value: RecapFollowScope.none,
                  child: Text('不含追问'),
                ),
                DropdownMenuItem(
                  value: RecapFollowScope.all,
                  child: Text('全部已同步追问'),
                ),
                DropdownMenuItem(
                  value: RecapFollowScope.selected,
                  child: Text('选择部分追问'),
                ),
              ],
              onChanged: _working
                  ? null
                  : (v) => setState(() => _followModes[m.localId] = v!),
            ),
            if (_followModes[m.localId] == RecapFollowScope.selected)
              for (final f in m.followUps)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(f.question, style: _style(14)),
                  value: (_followIds[m.localId] ?? {}).contains(f.remoteId),
                  onChanged: f.remoteId == null || _working
                      ? null
                      : (v) => setState(() {
                          final ids = _followIds.putIfAbsent(
                            m.localId,
                            () => <String>{},
                          );
                          if (v == true) {
                            ids.add(f.remoteId!);
                          } else {
                            ids.remove(f.remoteId);
                          }
                        }),
                ),
          ],
        ],
      ),
    ),
  ];

  List<Widget> _confirmation() {
    final h = _controller?.header;
    return [
      if (h != null) ...[
        _bookHeader(subtitle: '本次回望 · 已确认的阅读材料'),
        _heading('仅依据这次选择'),
        _text(
          '已核验 ${h.coverage['includedEntries']} 条阅读记录、${h.coverage['includedFollowUps']} 条追问。',
        ),
        if (_materials.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final kind in _kinds.keys.where((k) => k != 'manual'))
                  if (_materials.any(
                    (m) =>
                        _selected.contains(m.localId) &&
                        (m.kind == kind ||
                            kind == 'thought' && m.kind == 'manual'),
                  ))
                    _caption(
                      '${_kinds[kind]} ${_materials.where((m) => _selected.contains(m.localId) && (m.kind == kind || kind == 'thought' && m.kind == 'manual')).length}',
                    ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Divider(color: _line, height: 24),
        _text('本次回望仅依据已确认的阅读记录，不代表整本书。'),
        _caption('生成时会将所选片段、个人表达和历史 AI 内容交给云端 AI 分析；随心记不在范围内。'),
        const SizedBox(height: 16),
      ],
      _command('重新选择材料', Icons.checklist, (e) => _chooseBook(_bookId!, e)),
    ];
  }

  List<Widget> _historyList() => [
    _caption('保存的思考，随时回来继续。'),
    const SizedBox(height: 16),
    if (_history.isEmpty && !_working) _status('还没有回望。'),
    for (final item in _history) ...[
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.auto_stories_outlined, size: 22, color: _accent),
        title: Text(
          _bookNames[item.bookId] ?? '阅读回望',
          style: _style(16, weight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.state == RecapHistoryState.ready
                  ? (item.isSaved ? '已保存' : '临时预览')
                  : switch (item.state) {
                      RecapHistoryState.stale => '原始资料已变化',
                      RecapHistoryState.invalidated => '依据已失效',
                      RecapHistoryState.deleted => '已删除',
                      RecapHistoryState.expired => '预览已过期',
                      RecapHistoryState.generating => '正在生成',
                      RecapHistoryState.prepared => '等待范围确认',
                      RecapHistoryState.cancelled => '已取消',
                      _ => '未生成成功',
                    },
              style: _style(13, color: _muted),
            ),
            Text(
              '${item.updatedAt.toLocal().year}.${item.updatedAt.toLocal().month.toString().padLeft(2, '0')}.${item.updatedAt.toLocal().day.toString().padLeft(2, '0')}',
              style: _style(12, color: _muted),
            ),
          ],
        ),
        onTap: _working || item.state != RecapHistoryState.ready
            ? null
            : () => _action((e) => _restoreHistory(item, e)),
        trailing: IconButton(
          tooltip: '删除回望',
          icon: const Icon(Icons.delete_outline),
          onPressed: _working
              ? null
              : () => _revealControls(() => _deleteCandidate = item.id),
        ),
      ),
      const Divider(height: 1),
    ],
    if (_cursor != null)
      _command('加载更多', Icons.expand_more, (e) => _historyPage(e, next: true)),
    Wrap(
      spacing: 8,
      children: [
        _command('刷新历史', Icons.refresh, _historyPage),
        _command('选择书籍', Icons.menu_book_outlined, _loadBooks),
      ],
    ),
  ];

  List<Widget> _privateContent() {
    // The widget keeps no JSON/answer snapshot. Every rebuild reads the revocable
    // handle; lifecycle/source events rebuild this entire private subtree.
    final body = _body();
    final c = _controller!;
    return [
      if (_showMore) ...[
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            Tooltip(
              message: '我的回望',
              child: _command('我的回望', Icons.history, _historyPage),
            ),
            if (body != null) ...[
              _command('继续查看', Icons.refresh, (_) async {
                await c.renewDisplay();
              }),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: _accent,
                  textStyle: _style(14),
                ),
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('反馈'),
                onPressed: _working
                    ? null
                    : () => setState(() => _showFeedback = !_showFeedback),
              ),
            ],
            if (c.recapIdValue != null)
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  textStyle: _style(14),
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('删除回望'),
                onPressed: _working
                    ? null
                    : () => _revealControls(
                        () => _deleteCandidate = c.recapIdValue,
                      ),
              ),
            _command(
              '重新选择材料',
              Icons.checklist,
              (e) => _chooseBook(_bookId!, e),
            ),
          ],
        ),
        Divider(color: _line),
      ],
      if (body == null && !_working)
        _text(
          c.message ??
              switch (c.phase) {
                RecapClientPhase.running => '正在生成，可稍后查询结果。',
                RecapClientPhase.cancelled => '本次生成已取消。',
                RecapClientPhase.failed => '这次未能生成完整回望。',
                _ => '内容已遮蔽，请重新在线核验。',
              },
        ),
      if (_showFeedback && body != null) ...[
        DropdownButtonFormField<String>(
          initialValue: _feedbackCategory,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'inaccurate', child: Text('内容不准确')),
            DropdownMenuItem(value: 'low_value', child: Text('没有帮助')),
            DropdownMenuItem(value: 'wrong_relation', child: Text('关联有误')),
          ],
          onChanged: (v) => setState(() => _feedbackCategory = v!),
        ),
        TextField(
          controller: _feedback,
          maxLength: 1000,
          maxLines: 3,
          decoration: const InputDecoration(labelText: '补充说明（可选）'),
        ),
        _command('提交私有反馈', Icons.check, (e) async {
          await c.feedback(_feedbackCategory, comment: _feedback.text);
          _check(e);
          _feedback.clear();
          _showFeedback = false;
          await _read(e);
          _notice = '反馈已保存，仅对当前账号可见。';
        }),
      ],
      if (body != null && _pane == _Pane.detail)
        ..._result(recapObject(body['result'])),
      // Evidence is rendered only in the in-page sheet, never in two subtrees.
      if (body != null && _pane == _Pane.discussion) ..._turns(body),
      if (c.busy || c.phase == RecapClientPhase.running)
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: context.appPalette.primaryDark,
          ),
          onPressed: _cancel,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('取消生成'),
        ),
      if (body == null && c.replayRequestId != null)
        _command('查询上次请求', Icons.sync, (e) async {
          await c.replay();
          _check(e);
          if (c.phase == RecapClientPhase.ready) await _read(e);
          if (c.phase == RecapClientPhase.confirmation) _pane = _Pane.confirm;
        }),
      if (body == null && c.header?.state == RecapServerState.ready)
        _command(
          '重新核验正文',
          Icons.refresh,
          _pane == _Pane.discussion ? _discussion : _read,
        ),
      if (_pane != _Pane.detail && !(_pane == _Pane.evidence && body != null))
        _command('返回回望', Icons.arrow_back, _read),
      if (body == null)
        _command('重新选择材料', Icons.checklist, (e) => _chooseBook(_bookId!, e)),
    ];
  }

  List<Widget> _result(Map<String, dynamic> result) {
    final s = RecapEditorialStyle(context);
    final numbers = <String, int>{};
    for (final group in [
      'knowledge',
      'relations',
      'myThinking',
      'openQuestions',
      'nextQuestions',
    ]) {
      for (final item in result[group] as List) {
        for (final id in item['evidenceRefs'] as List) {
          numbers.putIfAbsent(id as String, () => numbers.length + 1);
        }
      }
    }
    return [
      _positionedArticle(
        RepaintBoundary(
          key: const ValueKey('recap-editorial-article'),
          child: ColoredBox(
            color: _paper,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.sizeOf(context).width < 360 ? 20 : 26,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 18),
                  Divider(height: 1, color: s.ink),
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 22),
                    child: Text('阅读手记', style: s.label(color: s.link)),
                  ),
                  Semantics(
                    header: true,
                    child: Text(
                      _bookNames[_bookId] ?? '阅读回望',
                      style: s.text(29, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('基于本次授权的阅读痕迹，不代表整本书。', style: s.label()),
                  const SizedBox(height: 20),
                  for (final group in [
                    ('knowledge', '知识整理', '01', '理解所选材料中的关系', 0),
                    ('myThinking', '我的思考', '02', '原话与整理，各有出处', 1),
                    ('openQuestions', '待解决的问题', '', '', -1),
                    ('nextQuestions', '继续思考', '03', '让问题保持开放', 2),
                  ])
                    if ((result[group.$1] as List).isNotEmpty ||
                        group.$1 == 'knowledge' ||
                        group.$1 == 'myThinking') ...[
                      if (group.$5 < 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 20, bottom: 14),
                          child: Text(group.$2, style: s.text(17)),
                        )
                      else
                        RecapEditorialSection(
                          key: _sectionKeys[group.$5],
                          number: group.$3,
                          title: group.$2,
                          subtitle: group.$4,
                        ),
                      if ((result[group.$1] as List).isEmpty)
                        _articleParagraph('当前材料不足以形成可靠整理。'),
                      for (final item in result[group.$1] as List)
                        ..._editorialItem(
                          recapObject(item),
                          numbers,
                          question: group.$1 == 'nextQuestions',
                          thinking: group.$1 == 'myThinking',
                        ),
                      if (group.$1 == 'knowledge')
                        for (final raw in result['relations'] as List) ...[
                          Text(
                            raw['basis'] == 'ai_inference'
                                ? '小U的推测，仍需核实'
                                : '小U整理 · 关系分析',
                            style: s.label(),
                          ),
                          const SizedBox(height: 8),
                          _articleParagraph(raw['explanation'] as String),
                          _refs(recapObject(raw), numbers: numbers),
                          const SizedBox(height: 18),
                        ],
                    ],
                  const SizedBox(height: 24),
                  Divider(color: s.line),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  // Lay out the freshly authorized article before painting its restored position.
  Widget _positionedArticle(Widget child) => Visibility(
    visible: _positionPaintEpoch == null,
    maintainState: true,
    maintainAnimation: true,
    maintainSize: true,
    child: child,
  );

  Widget _articleParagraph(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Text(text, style: RecapEditorialStyle(context).text(16)),
  );

  List<Widget> _editorialItem(
    Map<String, dynamic> item,
    Map<String, int> numbers, {
    required bool question,
    required bool thinking,
  }) {
    final s = RecapEditorialStyle(context);
    return [
      if (question)
        TextButton(
          key: ValueKey('recap-ask-${item['id']}'),
          onPressed: _working
              ? null
              : () => _action((e) => _askItem(item['id'] as String, e)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            minimumSize: const Size(44, 44),
            alignment: Alignment.centerLeft,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(item['title'] as String, style: s.text(17))),
              const SizedBox(width: 12),
              Icon(Icons.north_east, size: 18, color: s.link),
            ],
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(item['title'] as String, style: s.text(17)),
        ),
      if (thinking)
        for (final quote in item['quotes'] as List)
          _sourceQuote(recapObject(quote)),
      if (thinking || item['basis'] == 'ai_inference') ...[
        Text(
          item['basis'] == 'ai_inference' ? '小U的推测，仍需核实' : '小U整理 · 依据用户表达',
          style: s.label(),
        ),
        const SizedBox(height: 8),
      ],
      _articleParagraph(item['summary'] as String),
      if (!thinking)
        for (final quote in item['quotes'] as List)
          _sourceQuote(recapObject(quote)),
      _refs(item, numbers: numbers),
      const SizedBox(height: 18),
    ];
  }

  Widget _sourceQuote(Map<String, dynamic> quote) => RecapEditorialQuote(
    text: quote['text'] as String,
    label: switch (quote['voice']) {
      'user' => '用户原话 · 引用',
      'historical_ai' => '历史 AI 回答 · 引用',
      _ => '阅读记录中的片段 · 引用',
    },
    userVoice: quote['voice'] == 'user',
    historicalAi: quote['voice'] == 'historical_ai',
  );

  Widget _refs(Map<String, dynamic> item, {Map<String, int>? numbers}) {
    final ids = List<String>.from(item['evidenceRefs'] as List);
    final s = RecapEditorialStyle(context);
    return Wrap(
      spacing: 12,
      children: [
        for (var index = 0; index < ids.length; index++)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: s.link,
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              minimumSize: const Size(44, 44),
              textStyle: s.label(color: s.link),
            ),
            onPressed: _working || !_available
                ? null
                : () => _action((e) => _showEvidence([ids[index]], e)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  (numbers?[ids[index]] ?? index + 1).toString().padLeft(
                    2,
                    '0',
                  ),
                  style: s.text(13, color: s.link),
                ),
                const SizedBox(width: 7),
                const Text('查看依据'),
              ],
            ),
          ),
      ],
    );
  }

  Widget _editorialLayers(Widget page) {
    final body = _body();
    final evidence = _pane == _Pane.evidence && body != null;
    final contents =
        _showContents && _pane == _Pane.detail && body?['result'] != null;
    void close() {
      if (contents) {
        setState(() => _showContents = false);
      } else if (!_working) {
        _action(_read);
      }
    }

    final s = RecapEditorialStyle(context);
    return Stack(
      children: [
        ExcludeSemantics(
          excluding: contents || evidence,
          child: IgnorePointer(ignoring: contents || evidence, child: page),
        ),
        if (contents || evidence)
          ModalBarrier(
            color: Colors.black.withValues(alpha: .16),
            dismissible: true,
            onDismiss: close,
            semanticsLabel: '关闭弹层',
          ),
        if (contents || evidence)
          Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .78,
                maxWidth: 640,
              ),
              child: Semantics(
                scopesRoute: true,
                explicitChildNodes: true,
                namesRoute: true,
                label: contents ? '章节目录' : '阅读依据',
                child: FocusScope(
                  autofocus: true,
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape): close,
                    },
                    child: Material(
                      color: _paper,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: SafeArea(
                        top: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 12, 12, 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      contents ? '章节目录' : '阅读依据',
                                      style: s.text(22, height: 1.5),
                                    ),
                                  ),
                                  if (contents)
                                    IconButton(
                                      autofocus: true,
                                      color: s.muted,
                                      onPressed: close,
                                      tooltip: contents ? '关闭目录' : '关闭依据',
                                      icon: const Icon(Icons.close, size: 20),
                                    ),
                                  if (evidence)
                                    Tooltip(
                                      message: '关闭依据',
                                      child: TextButton.icon(
                                        style: TextButton.styleFrom(
                                          foregroundColor: s.link,
                                          minimumSize: const Size(48, 48),
                                        ),
                                        autofocus: true,
                                        onPressed: _working ? null : close,
                                        icon: const Icon(
                                          Icons.arrow_back,
                                          size: 18,
                                        ),
                                        label: const Text('返回回望'),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Flexible(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  0,
                                  24,
                                  24,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (contents)
                                      for (var i = 0; i < 3; i++)
                                        if (i < 2 ||
                                            (body!['result']['nextQuestions']
                                                    as List)
                                                .isNotEmpty)
                                          TextButton(
                                            key: ValueKey('recap-toc-$i'),
                                            style: TextButton.styleFrom(
                                              alignment: Alignment.centerLeft,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 18,
                                                  ),
                                            ),
                                            onPressed: () {
                                              setState(
                                                () => _showContents = false,
                                              );
                                              WidgetsBinding.instance
                                                  .addPostFrameCallback((_) {
                                                    final target =
                                                        _sectionKeys[i]
                                                            .currentContext;
                                                    if (mounted &&
                                                        _body() != null &&
                                                        target != null) {
                                                      Scrollable.ensureVisible(
                                                        target,
                                                      );
                                                    }
                                                  });
                                            },
                                            child: Text(
                                              '0${i + 1}  ${['知识整理', '我的思考', '继续思考'][i]}',
                                              style: s.text(18),
                                            ),
                                          ),
                                    if (evidence) ...[
                                      for (final item
                                          in body['evidence'] as List)
                                        ..._evidence(recapObject(item)),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _evidence(Map<String, dynamic> item) => [
    _heading(switch (item['kind']) {
      'book_excerpt' => '原文上下文',
      'highlight' => '用户划线',
      'user_note' => '个人想法',
      'user_question' => '用户问题',
      'historical_ai' => '历史 AI 回答',
      _ => 'AI 提示',
    }),
    if ((item['location']['chapter_title'] as String).isNotEmpty)
      _text(item['location']['chapter_title']),
    RecapEditorialQuote(
      text: item['text'],
      label: item['kind'] == 'user_note'
          ? '你的批注'
          : item['kind'] == 'user_question'
          ? '你提出的问题'
          : '已授权的阅读记录',
      userVoice: item['kind'] == 'user_note' || item['kind'] == 'user_question',
      historicalAi: item['kind'] == 'historical_ai',
    ),
    _caption('当前只能核对已保存的片段，无法保证精确跳转到原书。'),
    if (item['kind'] == 'book_excerpt') ...[
      const SizedBox(height: 8),
      _caption('这是阅读记录中的上下文，不代表服务端已核实原书逐字内容。'),
    ],
  ];
  List<Widget> _turns(Map<String, dynamic> body) => [
    if ((body['turns'] as List).isEmpty) _text('这份回望还没有追问。'),
    for (final raw in body['turns'] as List) ...[
      const SizedBox(height: 16),
      Text(
        '我的问题',
        style: _style(13, color: _muted, weight: FontWeight.w500),
      ),
      const SizedBox(height: 8),
      _text(raw['question']),
      const SizedBox(height: 12),
      Text(
        '小U',
        style: _style(14, color: _accent, weight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      for (final part in raw['answer']['parts'] as List) ...[
        _text(part['text']),
        if (part['basis'] == 'ai_inference') _caption('小U的推测，仍需核实'),
        _refs(recapObject(part)),
      ],
    ],
    const SizedBox(height: 20),
    TextField(
      key: const Key('recap-question'),
      controller: _question,
      style: _style(15),
      maxLength: 4000,
      minLines: 2,
      maxLines: 6,
      decoration: InputDecoration(
        labelText: '继续问小U',
        labelStyle: _style(14, color: _muted),
        filled: true,
        fillColor: _soft,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _line),
        ),
      ),
    ),
    _command('发送追问', Icons.send_outlined, _sendQuestion),
  ];

  @override
  void dispose() {
    _epoch++;
    _abort?.cancel();
    w.routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    AuthSessionScope.changes.removeListener(_authChanged);
    w.online.removeListener(_networkChanged);
    w.localChanges.removeListener(_sourcesChanged);
    PrivacyService.aiConsentChanges.removeListener(_consentChanged);
    _controller?.removeListener(_controllerChanged);
    _controller?.dispose();
    _question.dispose();
    _feedback.dispose();
    _scroll.dispose();
    super.dispose();
  }
}
