import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../l10n/l10n.dart';
import '../../models/user_entry.dart';
import '../../services/book_service.dart';
import '../../services/share_service.dart';
import '../../utils/latest_request_guard.dart';

class NotesFreeScreen extends StatefulWidget {
  final int refreshSignal;

  const NotesFreeScreen({super.key, this.refreshSignal = 0});

  @override
  State<NotesFreeScreen> createState() => _NotesFreeScreenState();
}

class _NotesFreeScreenState extends State<NotesFreeScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _notes = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _hasResolvedLoad = false;
  String? _loadError;
  final LatestRequestGuard _loadGuard = LatestRequestGuard();
  String _query = '';

  List<Map<String, dynamic>> get _visibleNotes {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _notes;
    return _notes.where((note) {
      final title = note['title']?.toString().toLowerCase() ?? '';
      final content = note['content']?.toString().toLowerCase() ?? '';
      return title.contains(query) || content.contains(query);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  @override
  void didUpdateWidget(covariant NotesFreeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshSignal != oldWidget.refreshSignal) {
      _loadNotes();
    }
  }

  @override
  void dispose() {
    _loadGuard.invalidate();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    final requestVersion = _loadGuard.begin();
    setState(() {
      _loading = _notes.isEmpty && !_hasResolvedLoad;
      _refreshing = _notes.isNotEmpty || _hasResolvedLoad;
      _loadError = null;
    });
    debugPrint(
      '[FreeNotesLoad] start version=$requestVersion retained=${_notes.length}',
    );
    try {
      final localNotes = await BookService.getFreeNotes(syncRemote: false);
      if (!mounted || !_loadGuard.isCurrent(requestVersion)) {
        debugPrint(
          '[FreeNotesLoad] stale local result ignored version=$requestVersion',
        );
        return;
      }
      setState(() {
        _notes = localNotes;
        _loading = false;
        _hasResolvedLoad = true;
      });
      debugPrint(
        '[FreeNotesLoad] local cache version=$requestVersion '
        'items=${localNotes.length}',
      );

      final synced = await BookService.syncFreeNotes(throwOnFailure: true);
      if (!mounted || !_loadGuard.isCurrent(requestVersion)) return;
      if (synced) {
        final refreshed = await BookService.getFreeNotes(syncRemote: false);
        if (!mounted || !_loadGuard.isCurrent(requestVersion)) return;
        setState(() => _notes = refreshed);
        debugPrint(
          '[FreeNotesLoad] server sync version=$requestVersion '
          'items=${refreshed.length} empty=${refreshed.isEmpty}',
        );
      } else {
        debugPrint('[FreeNotesLoad] local-only version=$requestVersion');
      }
    } catch (error) {
      if (!mounted || !_loadGuard.isCurrent(requestVersion)) return;
      debugPrint('[FreeNotesLoad] failed version=$requestVersion: $error');
      setState(() {
        _loadError = context.l10n.syncFailedLocalRetained;
        _loading = false;
      });
    } finally {
      if (mounted && _loadGuard.isCurrent(requestVersion)) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
  }

  Future<void> _openEditor([Map<String, dynamic>? note]) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FreeNoteEditor(note: note),
    );
    if (mounted) {
      await _loadNotes();
    }
  }

  Future<void> _deleteNote(Map<String, dynamic> note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.deleteRecord),
        content: Text(context.l10n.deleteRecordConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await BookService.deleteFreeNote(note['id']?.toString() ?? '');
    if (mounted) await _loadNotes();
  }

  void _openEchoDay(_TodayEcho echo) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => _EchoDayScreen(day: echo.day)));
  }

  @override
  Widget build(BuildContext context) {
    final notes = _visibleNotes;
    final todayEcho = _todayEcho(_notes);
    final groups = _groupNotes(context, notes);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 82,
        centerTitle: false,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.freeNotesTitle),
            const SizedBox(height: 5),
            Text(
              context.l10n.freeNotesSubtitle,
              style: const TextStyle(
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w400,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        tooltip: context.l10n.newFreeNote,
        icon: const Icon(Icons.edit_outlined, size: 20),
        label: Text(context.l10n.writeNote),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: RefreshIndicator(
        onRefresh: _loadNotes,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            if (_refreshing)
              const SliverToBoxAdapter(
                child: LinearProgressIndicator(minHeight: 2),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              sliver: SliverToBoxAdapter(
                child: _FreeNotesSearch(
                  controller: _searchController,
                  query: _query,
                  onChanged: _onSearchChanged,
                  onClear: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                ),
              ),
            ),
            if (todayEcho != null && _query.trim().isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 24, 18, 2),
                sliver: SliverToBoxAdapter(
                  child: _TodayEchoCard(
                    echo: todayEcho,
                    onTap: () => _openEchoDay(todayEcho),
                  ),
                ),
              ),
            if (_loadError != null && _notes.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                sliver: SliverToBoxAdapter(
                  child: _FreeNotesLoadNotice(
                    message: _loadError!,
                    onRetry: _loadNotes,
                  ),
                ),
              ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_loadError != null && _notes.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _FreeNotesLoadFailure(onRetry: _loadNotes),
              )
            else if (notes.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _FreeNotesEmpty(hasQuery: _query.trim().isNotEmpty),
              )
            else
              ..._buildTimeline(groups),
            const SliverToBoxAdapter(child: SizedBox(height: 104)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTimeline(List<_NoteGroup> groups) {
    return [
      for (final group in groups) ...[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 26, 18, 10),
          sliver: SliverToBoxAdapter(
            child: Text(
              group.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((_, index) {
              final note = group.notes[index];
              return _FreeNoteCard(
                note: note,
                onTap: () => _openEditor(note),
                onDelete: () => _deleteNote(note),
              );
            }, childCount: group.notes.length),
          ),
        ),
      ],
    ];
  }
}

class _FreeNotesLoadNotice extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _FreeNotesLoadNotice({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: palette.card.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.divider.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: palette.icon),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: palette.textSecondary, fontSize: 13),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
        ],
      ),
    );
  }
}

class _FreeNotesLoadFailure extends StatelessWidget {
  final VoidCallback onRetry;

  const _FreeNotesLoadFailure({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 34, color: palette.icon),
            const SizedBox(height: 14),
            Text(
              context.l10n.freeNotesSyncUnavailable,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.freeNotesSyncRetained,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 10),
            TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
          ],
        ),
      ),
    );
  }
}

class _FreeNotesSearch extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _FreeNotesSearch({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: context.l10n.searchFreeNotes,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                tooltip: context.l10n.clearSearch,
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClear,
              ),
        fillColor: palette.card.withAlpha(224),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: palette.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: palette.primaryLight),
        ),
      ),
    );
  }
}

class _TodayEchoCard extends StatelessWidget {
  final _TodayEcho echo;
  final VoidCallback onTap;

  const _TodayEchoCard({required this.echo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: palette.card.withAlpha(224),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '✦',
                style: TextStyle(
                  color: palette.primaryDark,
                  fontSize: 17,
                  height: 1,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                context.l10n.todayEcho,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            _formatEchoDate(context, echo.day),
            style: TextStyle(color: palette.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Text(
            echo.excerpt,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 15,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 13),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                '${context.l10n.backToThatDay}  →',
                style: TextStyle(
                  color: palette.primaryDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EchoDayScreen extends StatefulWidget {
  final DateTime day;

  const _EchoDayScreen({required this.day});

  @override
  State<_EchoDayScreen> createState() => _EchoDayScreenState();
}

class _EchoDayScreenState extends State<_EchoDayScreen> {
  late final Future<_EchoDayData> _data = _loadData();

  Future<_EchoDayData> _loadData() async {
    final day = _dateOnly(widget.day);
    final nextDay = day.add(const Duration(days: 1));
    final results = await Future.wait([
      BookService.getFreeNotes(),
      BookService.getUserEntries(
        createdAtFrom: day.toUtc(),
        createdAtTo: nextDay.subtract(const Duration(microseconds: 1)).toUtc(),
      ),
    ]);
    final notes = (results[0] as List<Map<String, dynamic>>)
        .where((note) => _isSameDay(_freeNoteDate(note), day))
        .toList();
    final entries = (results[1] as List<UserEntry>)
        .where((entry) => _isSameDay(entry.createdAt.toLocal(), day))
        .toList();
    return _EchoDayData(notes: notes, entries: entries);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.thatDay)),
      body: FutureBuilder<_EchoDayData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _EchoDayEmpty(message: context.l10n.thatDayUnavailable);
          }
          final data = snapshot.data!;
          final highlights = data.entries
              .where((entry) => entry.source == 'highlight')
              .toList();
          final thoughts = data.entries
              .where((entry) => entry.source == 'thought')
              .toList();
          final readingTraces = data.entries
              .where(
                (entry) =>
                    entry.source != 'highlight' && entry.source != 'thought',
              )
              .toList();
          final isEmpty =
              data.notes.isEmpty &&
              highlights.isEmpty &&
              thoughts.isEmpty &&
              readingTraces.isEmpty;
          if (isEmpty) {
            return _EchoDayEmpty(message: context.l10n.thatDayEmpty);
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
            children: [
              Text(
                _formatEchoDate(context, widget.day),
                style: TextStyle(color: palette.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 7),
              Text(
                context.l10n.backToThatDay,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              if (data.notes.isNotEmpty)
                _EchoSection(
                  title: context.l10n.freeNotesTitle,
                  children: [
                    for (final note in data.notes)
                      _EchoTextCard(
                        text: note['content']?.toString() ?? '',
                        time: _formatClock(_freeNoteDate(note)),
                      ),
                  ],
                ),
              if (highlights.isNotEmpty)
                _EchoSection(
                  title: context.l10n.highlights,
                  children: [
                    for (final entry in highlights)
                      _EchoEntryCard(entry: entry),
                  ],
                ),
              if (thoughts.isNotEmpty)
                _EchoSection(
                  title: context.l10n.thoughts,
                  children: [
                    for (final entry in thoughts) _EchoEntryCard(entry: entry),
                  ],
                ),
              if (readingTraces.isNotEmpty)
                _EchoSection(
                  title: context.l10n.readingRecords,
                  children: [
                    for (final entry in readingTraces)
                      _EchoEntryCard(entry: entry),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EchoSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _EchoSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 9),
          ...children,
        ],
      ),
    );
  }
}

class _EchoTextCard extends StatelessWidget {
  final String text;
  final String time;
  final String? source;

  const _EchoTextCard({required this.text, required this.time, this.source});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: palette.card.withAlpha(224),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (source?.isNotEmpty == true) ...[
            Text(
              source!,
              style: TextStyle(color: palette.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 7),
          ],
          Text(
            text,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 14,
              height: 1.65,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            time,
            style: TextStyle(color: palette.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _EchoEntryCard extends StatelessWidget {
  final UserEntry entry;

  const _EchoEntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final text = entry.source == 'thought'
        ? entry.userInput
        : entry.originalText.isNotEmpty
        ? entry.originalText
        : entry.aiExplanation;
    return _EchoTextCard(
      text: text,
      time: _formatClock(entry.createdAt),
      source: entry.bookTitle.isEmpty ? null : '《${entry.bookTitle}》',
    );
  }
}

class _EchoDayEmpty extends StatelessWidget {
  final String message;

  const _EchoDayEmpty({required this.message});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Center(
      child: Text(
        message,
        style: TextStyle(color: palette.textSecondary, fontSize: 14),
      ),
    );
  }
}

class _FreeNoteEditor extends StatefulWidget {
  final Map<String, dynamic>? note;

  const _FreeNoteEditor({this.note});

  @override
  State<_FreeNoteEditor> createState() => _FreeNoteEditorState();
}

class _FreeNoteEditorState extends State<_FreeNoteEditor> {
  late final TextEditingController _controller;
  late final TextEditingController _titleController;
  late final String _noteId;
  String _lastSavedContent = '';
  String _lastSavedTitle = '';
  Timer? _autosaveTimer;
  bool _saving = false;
  bool _autosaving = false;
  bool _changingAuthorization = false;
  late bool _xiaouAuthorized;

  @override
  void initState() {
    super.initState();
    final existingId = widget.note?['id']?.toString() ?? '';
    _noteId = existingId.isNotEmpty
        ? existingId
        : 'free_${DateTime.now().microsecondsSinceEpoch}';
    _lastSavedContent = widget.note?['content']?.toString() ?? '';
    _lastSavedTitle = widget.note?['title']?.toString() ?? '';
    _controller = TextEditingController(text: _lastSavedContent)
      ..addListener(_scheduleAutosave);
    _titleController = TextEditingController(text: _lastSavedTitle)
      ..addListener(_scheduleAutosave);
    _xiaouAuthorized =
        widget.note?['xiaou_authorized'] == true ||
        widget.note?['xiaou_authorized'] == 1;
  }

  @override
  void dispose() {
    if (_hasUnsavedChanges) {
      unawaited(_autosave());
    }
    _autosaveTimer?.cancel();
    _controller.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _scheduleAutosave() {
    if (!_hasUnsavedChanges) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 700), _autosave);
  }

  bool get _hasUnsavedChanges {
    return _controller.text != _lastSavedContent ||
        _titleController.text != _lastSavedTitle;
  }

  Future<void> _autosave() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _saving || _autosaving || !_hasUnsavedChanges) {
      return;
    }
    if (mounted) setState(() => _autosaving = true);
    final title = _titleController.text;
    try {
      await BookService.saveFreeNote(
        id: _noteId,
        title: title,
        content: content,
      );
      _lastSavedContent = content;
      _lastSavedTitle = title;
    } finally {
      _autosaving = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _save() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _saving) return;
    _autosaveTimer?.cancel();
    setState(() => _saving = true);
    try {
      final title = _titleController.text;
      await BookService.saveFreeNote(
        id: _noteId,
        title: title,
        content: content,
      );
      _lastSavedContent = content;
      _lastSavedTitle = title;
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setXiaouAuthorization() async {
    final content = _controller.text.trim();
    if (_changingAuthorization) return;
    final messenger = ScaffoldMessenger.of(context);
    if (content.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.l10n.writeBeforeXiaou),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final authorized = !_xiaouAuthorized;
    setState(() => _changingAuthorization = true);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(minutes: 1),
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              authorized
                  ? context.l10n.authorizingXiaou
                  : context.l10n.revokingXiaou,
            ),
          ],
        ),
      ),
    );
    try {
      final title = _titleController.text;
      await BookService.saveFreeNote(
        id: _noteId,
        title: title,
        content: content,
        waitForRemote: true,
      );
      _lastSavedContent = content;
      _lastSavedTitle = title;
      await BookService.setFreeNoteXiaouAuthorization(
        _noteId,
        authorized: authorized,
      );
      if (!mounted) return;
      setState(() => _xiaouAuthorized = authorized);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            authorized
                ? context.l10n.authorizedXiaouMessage
                : context.l10n.revokedXiaouMessage,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.l10n.operationFailed(error.toString())),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _changingAuthorization = false);
    }
  }

  String _shareText() {
    final title = _shareTitle();
    return '${title == null ? '' : '$title\n\n'}'
        '${_controller.text.trim()}\n\n${_shareDate()}\n\n${context.l10n.appName}';
  }

  String? _shareTitle() {
    final title = _titleController.text.trim();
    final content = _controller.text.trim();
    if (title.isEmpty) return null;
    final firstLine = content
        .split(RegExp(r'[\r\n]'))
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    return firstLine == title ? null : title;
  }

  String _shareDate() {
    final value = widget.note?['updated_at']?.toString() ?? '';
    final time = DateTime.tryParse(value)?.toLocal() ?? DateTime.now();
    return DateFormat.yMMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(time);
  }

  Future<void> _shareImage() async {
    await ShareService.shareCard(
      context,
      fileName: 'zhidu_free_note_${DateTime.now().millisecondsSinceEpoch}',
      text: _shareText(),
      backgroundColor: FreeNoteShareCard.backgroundColor,
      card: FreeNoteShareCard(
        title: _shareTitle(),
        body: _controller.text.trim(),
        date: _shareDate(),
      ),
    );
  }

  Future<void> _onMenuSelected(String action) async {
    try {
      if (action == 'xiaou') {
        await _setXiaouAuthorization();
      } else if (action == 'share_text') {
        await ShareService.shareText(context, _shareText());
      } else if (action == 'share_image') {
        await _shareImage();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.shareFailed(error.toString())),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final screenHeight = MediaQuery.of(context).size.height;
    final palette = context.appPalette;

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: SizedBox(
          height: screenHeight * 0.92,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 10, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: context.l10n.close,
                        icon: const Icon(Icons.close),
                        onPressed: () async {
                          await _autosave();
                          if (context.mounted) Navigator.pop(context, true);
                        },
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.note == null
                                  ? context.l10n.writeThisMoment
                                  : context.l10n.returnToThisPage,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              context.l10n.privatePageSubtitle,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: context.l10n.more,
                        enabled: !_changingAuthorization,
                        onSelected: _onMenuSelected,
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'xiaou',
                            child: Text(
                              _xiaouAuthorized
                                  ? context.l10n.revokeXiaou
                                  : context.l10n.authorizeXiaou,
                            ),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'share_text',
                            child: Text(context.l10n.shareText),
                          ),
                          PopupMenuItem(
                            value: 'share_image',
                            child: Text(context.l10n.shareImage),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: _saving ? null : _save,
                        child: Text(
                          _saving ? context.l10n.saving : context.l10n.save,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 13, 20, 0),
                  child: Divider(height: 1, color: palette.divider),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                  child: TextField(
                    controller: _titleController,
                    maxLines: 1,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      hintText: context.l10n.titleOptional,
                      hintStyle: TextStyle(color: palette.textSecondary),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      minLines: 18,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.85,
                        color: AppTheme.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: context.l10n.noteBodyHint,
                        hintStyle: TextStyle(
                          height: 1.75,
                          color: palette.textSecondary,
                        ),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
                  child: Row(
                    children: [
                      if (_changingAuthorization)
                        const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          _xiaouAuthorized
                              ? Icons.auto_awesome
                              : Icons.lock_outline,
                          size: 15,
                          color: _xiaouAuthorized
                              ? palette.primary
                              : palette.textSecondary,
                        ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _changingAuthorization
                              ? _xiaouAuthorized
                                    ? context.l10n.revokingXiaou
                                    : context.l10n.authorizingXiaou
                              : _autosaving
                              ? context.l10n.autosaving
                              : _xiaouAuthorized
                              ? context.l10n.authorizedToXiaou
                              : context.l10n.privateOnlyNote,
                          style: TextStyle(
                            fontSize: 12,
                            color: _xiaouAuthorized
                                ? palette.primaryDark
                                : palette.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FreeNoteCard extends StatelessWidget {
  final Map<String, dynamic> note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _FreeNoteCard({
    required this.note,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final content = note['content']?.toString().trim() ?? '';
    final savedTitle = note['title']?.toString().trim() ?? '';
    final title = savedTitle.isEmpty
        ? _noteTitle(context, content)
        : savedTitle;
    final preview = _notePreview(content, title);
    final createdAtRaw = note['created_at']?.toString() ?? '';
    final updatedAtRaw = note['updated_at']?.toString() ?? '';
    final createdAt = _formatTime(context, createdAtRaw);
    final updatedAt = _formatTime(context, updatedAtRaw);
    final edited = _isMeaningfullyEdited(createdAtRaw, updatedAtRaw);
    final timeLabel = edited
        ? context.l10n.createdOnEditedOn(createdAt, updatedAt)
        : createdAt.isNotEmpty
        ? context.l10n.createdOn(createdAt)
        : updatedAt;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: palette.card.withAlpha(238),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: palette.divider),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 8, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 42,
                  decoration: BoxDecoration(
                    color: palette.illustration,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.55,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          preview,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.6,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 11),
                      Text(
                        timeLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9892A2),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: context.l10n.more,
                  color: palette.card,
                  icon: const Icon(
                    Icons.more_horiz,
                    size: 20,
                    color: AppTheme.textSecondary,
                  ),
                  onSelected: (value) {
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete_outline, size: 18),
                          const SizedBox(width: 8),
                          Text(context.l10n.delete),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FreeNotesEmpty extends StatelessWidget {
  final bool hasQuery;

  const _FreeNotesEmpty({required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    if (!hasQuery) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 96),
          child: Text(
            context.l10n.writeWhatYouThink,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 15,
              height: 1.6,
            ),
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 96),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 54, color: palette.illustration),
            const SizedBox(height: 18),
            Text(
              context.l10n.noSearchResultTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              context.l10n.noSearchResultBody,
              textAlign: TextAlign.center,
              style: const TextStyle(
                height: 1.6,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteGroup {
  final String label;
  final List<Map<String, dynamic>> notes;

  const _NoteGroup(this.label, this.notes);
}

class _TodayEcho {
  final DateTime day;
  final String excerpt;

  const _TodayEcho({required this.day, required this.excerpt});
}

class _EchoDayData {
  final List<Map<String, dynamic>> notes;
  final List<UserEntry> entries;

  const _EchoDayData({required this.notes, required this.entries});
}

List<_NoteGroup> _groupNotes(
  BuildContext context,
  List<Map<String, dynamic>> notes,
) {
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final note in notes) {
    final label = _timeGroup(context, note['updated_at']?.toString() ?? '');
    groups.putIfAbsent(label, () => []).add(note);
  }
  return groups.entries
      .map((entry) => _NoteGroup(entry.key, entry.value))
      .toList();
}

String _timeGroup(BuildContext context, String value) {
  final time = DateTime.tryParse(value)?.toLocal();
  if (time == null) return context.l10n.earlier;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final difference = today.difference(day).inDays;
  if (difference <= 0) return context.l10n.today;
  if (difference == 1) return context.l10n.yesterday;
  if (difference < 7) return context.l10n.thisWeek;
  if (time.year == now.year && time.month == now.month) {
    return context.l10n.thisMonth;
  }
  return context.l10n.earlier;
}

String _noteTitle(BuildContext context, String content) {
  final firstLine = content
      .split(RegExp(r'[\r\n。！？!?]'))
      .map((line) => line.trim())
      .firstWhere(
        (line) => line.isNotEmpty,
        orElse: () => context.l10n.untitledMoment,
      );
  return firstLine;
}

String _notePreview(String content, String title) {
  final normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized == title || normalized.isEmpty) return '';
  return normalized;
}

String _formatTime(BuildContext context, String value) {
  final time = DateTime.tryParse(value)?.toLocal();
  if (time == null) return '';
  return DateFormat.MMMd(
    Localizations.localeOf(context).toLanguageTag(),
  ).add_Hm().format(time);
}

bool _isMeaningfullyEdited(String createdAt, String updatedAt) {
  final created = DateTime.tryParse(createdAt)?.toLocal();
  final updated = DateTime.tryParse(updatedAt)?.toLocal();
  if (created == null || updated == null) return false;
  return updated.difference(created).abs() > const Duration(minutes: 1);
}

_TodayEcho? _todayEcho(List<Map<String, dynamic>> notes) {
  final today = _dateOnly(DateTime.now());
  final candidates = <Map<String, dynamic>>[];
  final seenExcerpts = <String>{};
  for (final note in notes) {
    final noteDate = _freeNoteDate(note);
    if (noteDate == null) continue;
    final day = _dateOnly(noteDate);
    if (today.difference(day).inDays < 6) continue;
    final excerpt = _echoExcerpt(note['content']?.toString() ?? '');
    if (excerpt.isEmpty || !seenExcerpts.add(excerpt)) continue;
    candidates.add({...note, '_echo_day': day, '_echo_excerpt': excerpt});
  }
  if (candidates.isEmpty) return null;

  final seed = today.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  final random = Random(seed);
  const weightedTargets = [7, 7, 7, 30, 30, 90, 180];
  final target = weightedTargets[random.nextInt(weightedTargets.length)];
  candidates.sort((a, b) {
    final aAge = today.difference(a['_echo_day'] as DateTime).inDays;
    final bAge = today.difference(b['_echo_day'] as DateTime).inDays;
    final byTarget = (aAge - target).abs().compareTo((bAge - target).abs());
    if (byTarget != 0) return byTarget;
    return aAge.compareTo(bAge);
  });

  final nearestDistance =
      (today.difference(candidates.first['_echo_day'] as DateTime).inDays -
              target)
          .abs();
  final nearest = candidates.where((note) {
    final age = today.difference(note['_echo_day'] as DateTime).inDays;
    return (age - target).abs() == nearestDistance;
  }).toList();
  final selected = nearest[random.nextInt(nearest.length)];
  return _TodayEcho(
    day: selected['_echo_day'] as DateTime,
    excerpt: selected['_echo_excerpt'] as String,
  );
}

DateTime? _freeNoteDate(Map<String, dynamic> note) {
  final raw = note['created_at']?.toString() ?? '';
  return DateTime.tryParse(raw)?.toLocal();
}

DateTime _dateOnly(DateTime date) {
  final local = date.toLocal();
  return DateTime(local.year, local.month, local.day);
}

bool _isSameDay(DateTime? left, DateTime right) {
  if (left == null) return false;
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String _echoExcerpt(String content) {
  final normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return '';
  final sentence = normalized
      .split(RegExp(r'[。！？!?]+'))
      .firstWhere((part) => part.trim().isNotEmpty, orElse: () => normalized)
      .trim();
  if (sentence.length <= 72) return sentence;
  return '${sentence.substring(0, 72)}…';
}

String _formatEchoDate(BuildContext context, DateTime value) {
  final time = value.toLocal();
  return DateFormat.yMMMMd(
    Localizations.localeOf(context).toLanguageTag(),
  ).format(time);
}

String _formatClock(DateTime? value) {
  if (value == null) return '';
  final time = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}';
}
