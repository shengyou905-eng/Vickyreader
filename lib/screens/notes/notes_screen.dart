import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/reader_provider.dart';
import '../../screens/reader/reader_screen.dart';
import '../../services/book_service.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<Map<String, dynamic>> _notes = [];
  List<Map<String, dynamic>> _highlights = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _highlights = (await BookService.getAllHighlights())
        .map((h) => h.toMap())
        .toList();
    _notes = await BookService.getAllNotes();
    setState(() => _isLoading = false);
  }

  Future<void> _openHighlight(Map<String, dynamic> h) async {
    final bookId = h['bookId'] as String;
    final chapterIdx = int.tryParse(h['chapterIndex'] as String) ?? 0;
    final text = h['selectedText'] as String;

    final book = await BookService.getBook(bookId);
    if (book == null || !mounted) return;

    final readerProvider = context.read<ReaderProvider>();
    await readerProvider.openBook(book);
    readerProvider.goToChapter(chapterIdx);
    readerProvider.setScrollTarget(text);

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ReaderScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    labelColor: AppTheme.primary,
                    unselectedLabelColor: AppTheme.textSecondary,
                    indicatorColor: AppTheme.primary,
                    tabs: const [
                      Tab(text: '划线'),
                      Tab(text: '想法'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildHighlightsList(),
                        _buildNotesList(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHighlightsList() {
    if (_highlights.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.format_quote, size: 48, color: AppTheme.dividerColor),
            SizedBox(height: 12),
            Text('还没有划线', style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _highlights.length,
      itemBuilder: (_, i) {
        final h = _highlights[i];
        return GestureDetector(
          onTap: () => _openHighlight(h),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(
                  color: Color(
                    int.tryParse(
                            (h['color'] as String).replaceFirst('#', '0xFF')) ??
                        0xFFB39DDB,
                  ),
                  width: 3,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h['selectedText'] as String,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
                if (h['note'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        h['note'] as String,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNotesList() {
    if (_notes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.edit_note, size: 48, color: AppTheme.dividerColor),
            SizedBox(height: 12),
            Text('还没有想法', style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _notes.length,
      itemBuilder: (_, i) {
        final n = _notes[i];
        return GestureDetector(
          onTap: () => _openNote(n),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: const Border(
                left: BorderSide(
                  color: Color(0xFFFFB74D),
                  width: 3,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (n['selectedText'] != null)
                  Text(
                    n['selectedText'] as String,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  ),
                if (n['selectedText'] != null) const SizedBox(height: 6),
                Text(
                  n['content'] as String,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 4),
                Text(
                  n['updatedAt'] as String,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openNote(Map<String, dynamic> n) async {
    final bookId = n['bookId'] as String;
    final chapterIdx = int.tryParse(n['chapterIndex'] as String? ?? '0') ?? 0;
    final text = n['selectedText'] as String?;

    final book = await BookService.getBook(bookId);
    if (book == null || !mounted) return;

    final readerProvider = context.read<ReaderProvider>();
    await readerProvider.openBook(book);
    readerProvider.goToChapter(chapterIdx);
    if (text != null) readerProvider.setScrollTarget(text);

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ReaderScreen()),
      );
    }
  }
}
