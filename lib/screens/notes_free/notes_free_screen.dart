import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../services/book_service.dart';
import '../../services/share_service.dart';

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
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    setState(() => _loading = true);
    try {
      final notes = await BookService.getFreeNotes();
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('随心记加载失败：$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
        title: const Text('删除记录'),
        content: const Text('这条随心记会从你的私密记录中删除，删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await BookService.deleteFreeNote(note['id']?.toString() ?? '');
    if (mounted) await _loadNotes();
  }

  @override
  Widget build(BuildContext context) {
    final notes = _visibleNotes;
    final keywords = _recentKeywords(_notes);
    final groups = _groupNotes(notes);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 82,
        centerTitle: false,
        titleSpacing: 20,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('随心记'),
            SizedBox(height: 5),
            Text(
              '留一处安静的地方，写下此刻经过心里的事',
              style: TextStyle(
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
        tooltip: '新建记录',
        icon: const Icon(Icons.edit_outlined, size: 20),
        label: const Text('写一笔'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: RefreshIndicator(
        onRefresh: _loadNotes,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
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
            if (keywords.isNotEmpty && _query.trim().isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 24, 18, 2),
                sliver: SliverToBoxAdapter(
                  child: _RecentWords(words: keywords),
                ),
              ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
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
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: '找一找曾经写下的句子',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                tooltip: '清空搜索',
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClear,
              ),
        fillColor: Colors.white.withOpacity(0.82),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFECE7F4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppTheme.primaryLight),
        ),
      ),
    );
  }
}

class _RecentWords extends StatelessWidget {
  final List<String> words;

  const _RecentWords({required this.words});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF2EDF9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAE1F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 16,
                color: AppTheme.primary,
              ),
              SizedBox(width: 7),
              Text(
                '最近落下的词',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final word in words)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.62),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    word,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                ),
            ],
          ),
        ],
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
    _controller = TextEditingController(
      text: widget.note?['content']?.toString() ?? '',
    )..addListener(_scheduleAutosave);
    _titleController = TextEditingController(
      text: widget.note?['title']?.toString() ?? '',
    )..addListener(_scheduleAutosave);
    _xiaouAuthorized =
        widget.note?['xiaou_authorized'] == true ||
        widget.note?['xiaou_authorized'] == 1;
  }

  @override
  void dispose() {
    unawaited(_autosave());
    _autosaveTimer?.cancel();
    _controller.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 700), _autosave);
  }

  Future<void> _autosave() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _saving || _autosaving) return;
    if (mounted) setState(() => _autosaving = true);
    try {
      await BookService.saveFreeNote(
        id: _noteId,
        title: _titleController.text,
        content: content,
      );
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
      await BookService.saveFreeNote(
        id: _noteId,
        title: _titleController.text,
        content: content,
      );
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
        const SnackBar(
          content: Text('先写下一点内容，再交给小U观察'),
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
            Text(authorized ? '正在交给小U观察…' : '正在撤回小U授权…'),
          ],
        ),
      ),
    );
    try {
      await BookService.saveFreeNote(
        id: _noteId,
        title: _titleController.text,
        content: content,
        waitForRemote: true,
      );
      await BookService.setFreeNoteXiaouAuthorization(
        _noteId,
        authorized: authorized,
      );
      if (!mounted) return;
      setState(() => _xiaouAuthorized = authorized);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(authorized ? '已交给小U观察' : '已撤回小U授权'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('操作失败：$error'),
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
        '${_controller.text.trim()}\n\n${_shareDate()}\n\n知读';
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
    String two(int number) => number.toString().padLeft(2, '0');
    return '${time.year}年${two(time.month)}月${two(time.day)}日';
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
          content: Text('分享失败：$error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final screenHeight = MediaQuery.of(context).size.height;

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: SizedBox(
          height: screenHeight * 0.92,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Color(0xFFFCFBFE),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 10, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '关闭',
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
                              widget.note == null ? '写下此刻' : '回到这一页',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              '只属于你的私人书页',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: '更多',
                        enabled: !_changingAuthorization,
                        onSelected: _onMenuSelected,
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'xiaou',
                            child: Text(_xiaouAuthorized ? '撤回小U授权' : '交给小U思考'),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'share_text',
                            child: Text('分享文本'),
                          ),
                          const PopupMenuItem(
                            value: 'share_image',
                            child: Text('分享图片'),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? '保存中...' : '保存'),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 13, 20, 0),
                  child: Divider(height: 1, color: Color(0xFFEFEAF5)),
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
                    decoration: const InputDecoration(
                      hintText: '标题（可选）',
                      hintStyle: TextStyle(color: Color(0xFFAAA2B5)),
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
                      decoration: const InputDecoration(
                        hintText: '不必整理，也不必解释。\n写下此刻经过心里的东西...',
                        hintStyle: TextStyle(
                          height: 1.75,
                          color: Color(0xFFAAA2B5),
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
                              ? AppTheme.primary
                              : AppTheme.textSecondary,
                        ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _changingAuthorization
                              ? _xiaouAuthorized
                                    ? '正在撤回小U授权…'
                                    : '正在交给小U观察…'
                              : _autosaving
                              ? '正在安静保存...'
                              : _xiaouAuthorized
                              ? '✨ 已授权给小U · 可随时撤回'
                              : '仅自己可见',
                          style: TextStyle(
                            fontSize: 12,
                            color: _xiaouAuthorized
                                ? AppTheme.primaryDark
                                : AppTheme.textSecondary,
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
    final content = note['content']?.toString().trim() ?? '';
    final savedTitle = note['title']?.toString().trim() ?? '';
    final title = savedTitle.isEmpty ? _noteTitle(content) : savedTitle;
    final preview = _notePreview(content, title);
    final updatedAt = _formatTime(note['updated_at']?.toString() ?? '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white.withOpacity(0.92),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFEFEAF5)),
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
                    color: const Color(0xFFD8C9EE),
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
                        updatedAt,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9892A2),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '更多',
                  color: Colors.white,
                  icon: const Icon(
                    Icons.more_horiz,
                    size: 20,
                    color: AppTheme.textSecondary,
                  ),
                  onSelected: (value) {
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18),
                          SizedBox(width: 8),
                          Text('删除'),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 96),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasQuery ? Icons.search_off : Icons.local_florist_outlined,
              size: 54,
              color: AppTheme.primaryLight,
            ),
            const SizedBox(height: 18),
            Text(
              hasQuery ? '没有找到那句话' : '这里还很安静',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              hasQuery ? '换个词，再慢慢找找' : '随手写下一点什么，让它在这里安静生长',
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

List<_NoteGroup> _groupNotes(List<Map<String, dynamic>> notes) {
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final note in notes) {
    final label = _timeGroup(note['updated_at']?.toString() ?? '');
    groups.putIfAbsent(label, () => []).add(note);
  }
  return groups.entries
      .map((entry) => _NoteGroup(entry.key, entry.value))
      .toList();
}

String _timeGroup(String value) {
  final time = DateTime.tryParse(value)?.toLocal();
  if (time == null) return '更早以前';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final difference = today.difference(day).inDays;
  if (difference <= 0) return '今天';
  if (difference == 1) return '昨天';
  if (difference < 7) return '本周';
  if (time.year == now.year && time.month == now.month) return '本月';
  return '更早以前';
}

String _noteTitle(String content) {
  final firstLine = content
      .split(RegExp(r'[\r\n。！？!?]'))
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '未命名的片刻');
  return firstLine;
}

String _notePreview(String content, String title) {
  final normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized == title || normalized.isEmpty) return '';
  return normalized;
}

String _formatTime(String value) {
  final time = DateTime.tryParse(value)?.toLocal();
  if (time == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(time.month)}月${two(time.day)}日  ${two(time.hour)}:${two(time.minute)}';
}

List<String> _recentKeywords(List<Map<String, dynamic>> notes) {
  final counts = <String, int>{};
  final ignored = <String>{
    '这个',
    '那个',
    '一些',
    '一个',
    '一种',
    '什么',
    '自己',
    '因为',
    '所以',
    '但是',
    '还是',
    '不是',
    '没有',
    '可以',
    '已经',
    '觉得',
    '时候',
    '可能',
    '我们',
    '他们',
    '然后',
    '其实',
    '如果',
    '只是',
    'the',
    'and',
    'that',
    'with',
    'this',
    'have',
    'from',
  };

  for (final note in notes.take(24)) {
    final content = note['content']?.toString().toLowerCase() ?? '';
    for (final match in RegExp(
      r'[\u4e00-\u9fff]{2,4}|[a-z]{3,}',
    ).allMatches(content)) {
      final word = match.group(0) ?? '';
      if (word.isEmpty || ignored.contains(word)) continue;
      counts[word] = (counts[word] ?? 0) + 1;
    }
  }

  final entries = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      return b.key.length.compareTo(a.key.length);
    });
  return entries.take(6).map((entry) => entry.key).toList();
}
