import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/bookmark.dart';
import '../../providers/reader_provider.dart';
import '../../services/book_service.dart';
import '../reader/reader_screen.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  List<Bookmark> _bookmarks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    setState(() => _isLoading = true);
    _bookmarks = await BookService.getAllBookmarks();
    setState(() => _isLoading = false);
  }

  Future<void> _openBookmark(Bookmark bm) async {
    final book = await BookService.getBook(bm.bookId);
    if (book == null || !mounted) return;

    final readerProvider = context.read<ReaderProvider>();
    await readerProvider.openBook(book);
    readerProvider.goToChapter(int.tryParse(bm.chapterIndex) ?? 0);

    // Restore scroll position from stored offset
    readerProvider.setScrollOffset(bm.scrollOffset);

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ReaderScreen()),
      );
    }
  }

  Future<void> _deleteBookmark(Bookmark bm) async {
    await BookService.deleteBookmark(bm.id);
    _loadBookmarks();
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('书签')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _bookmarks.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bookmark_border,
                          size: 48, color: AppTheme.dividerColor),
                      SizedBox(height: 12),
                      Text('还没有书签',
                          style: TextStyle(color: AppTheme.textSecondary)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _bookmarks.length,
                  itemBuilder: (_, i) {
                    final bm = _bookmarks[i];
                    return Dismissible(
                      key: Key(bm.id),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) async {
                        return await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('删除书签'),
                            content: const Text('确定要删除这个书签吗？'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('取消'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade400,
                                ),
                                child: const Text('删除'),
                              ),
                            ],
                          ),
                        ) ?? false;
                      },
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: Colors.red.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => _deleteBookmark(bm),
                      child: GestureDetector(
                        onTap: () => _openBookmark(bm),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: const Border(
                              left:
                                  BorderSide(color: AppTheme.primary, width: 3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bm.chapterTitle,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                bm.snippet,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatDate(bm.createdAt),
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
