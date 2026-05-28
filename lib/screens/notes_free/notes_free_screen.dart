import 'dart:async';

import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/book_service.dart';

class NotesFreeScreen extends StatefulWidget {
  const NotesFreeScreen({super.key});

  @override
  State<NotesFreeScreen> createState() => _NotesFreeScreenState();
}

class _NotesFreeScreenState extends State<NotesFreeScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _notes = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    setState(() => _loading = true);
    try {
      final notes = await BookService.getFreeNotes(query: _query);
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
    _query = value;
    _loadNotes();
  }

  Future<void> _openEditor([Map<String, dynamic>? note]) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('随心记'),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        tooltip: '新建记录',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索随心记',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空搜索',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _notes.isEmpty
                    ? _FreeNotesEmpty(hasQuery: _query.trim().isNotEmpty)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
                        itemCount: _notes.length,
                        itemBuilder: (_, index) {
                          final note = _notes[index];
                          return _FreeNoteCard(
                            note: note,
                            onTap: () => _openEditor(note),
                            onDelete: () => _deleteNote(note),
                          );
                        },
                      ),
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
  late final String _noteId;
  Timer? _autosaveTimer;
  bool _saving = false;
  bool _autosaving = false;

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
  }

  @override
  void dispose() {
    unawaited(_autosave());
    _autosaveTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 700), () {
      _autosave();
    });
  }

  Future<void> _autosave() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _saving || _autosaving) return;
    _autosaving = true;
    try {
      await BookService.saveFreeNote(id: _noteId, content: content);
    } finally {
      _autosaving = false;
    }
  }

  Future<void> _save() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _saving) return;
    _autosaveTimer?.cancel();
    setState(() => _saving = true);
    await BookService.saveFreeNote(
      id: _noteId,
      content: content,
      waitForRemote: true,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final screenHeight = MediaQuery.of(context).size.height;
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: SizedBox(
          height: screenHeight * 0.86,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 10, 4),
                child: Row(
                  children: [
                    Text(
                      widget.note == null ? '新建随心记' : '编辑随心记',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      await _autosave();
                      if (context.mounted) Navigator.pop(context, true);
                    },
                  ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    minLines: 10,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: '写点只属于自己的东西...',
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_saving ? '保存中...' : '保存'),
                  ),
                ),
              ),
            ],
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
    final content = note['content']?.toString() ?? '';
    final updatedAt = _formatTime(note['updated_at']?.toString() ?? '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        content,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.55,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        updatedAt,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '删除',
                  icon: const Icon(Icons.delete_outline),
                  color: AppTheme.textSecondary,
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatTime(String value) {
    final time = DateTime.tryParse(value)?.toLocal();
    if (time == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
  }
}

class _FreeNotesEmpty extends StatelessWidget {
  final bool hasQuery;

  const _FreeNotesEmpty({required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasQuery ? Icons.search_off : Icons.edit_note,
              size: 58,
              color: AppTheme.primaryLight,
            ),
            const SizedBox(height: 16),
            Text(
              hasQuery ? '没有找到相关记录' : '自由记录，随心所想',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasQuery ? '换个关键词试试' : '灵感、随笔、日记，都只留在这里',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
