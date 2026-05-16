import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../models/book.dart';
import '../../providers/bookshelf_provider.dart';
import '../../providers/reader_provider.dart';
import '../../services/auth_service.dart';
import '../../services/sync_service.dart';
import '../reader/reader_screen.dart';
import 'widgets/book_grid_tile.dart';
import 'widgets/empty_bookshelf.dart';
import 'widgets/import_dialog.dart';

class BookshelfScreen extends StatefulWidget {
  const BookshelfScreen({super.key});

  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends State<BookshelfScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BookshelfProvider>().loadBooks();
      _autoSync();
    });
  }

  Future<void> _autoSync() async {
    try {
      final userId = AuthService.userId;
      if (userId != null && userId.isNotEmpty) {
        SyncService.instance.setUserId(userId);
        await SyncService.instance.pullAll();
      }
    } catch (_) {}
  }

  Future<void> _showImportDialog() async {
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ImportDialog(),
    );

    if (result != null && mounted) {
      final provider = context.read<BookshelfProvider>();
      if (result is String) {
        // Local file path
        final book = await provider.importFromFile(result);
        if (book != null && mounted) {
          _openBook(book);
        } else if (provider.error != null && mounted) {
          _showError(provider.error!);
        }
      } else if (result is Map && result['url'] != null) {
        // URL import (P1)
        final book = await provider.importFromUrl(result['url'] as String);
        if (book != null && mounted) {
          _openBook(book);
        }
      }
    }
  }

  void _openBook(Book book) async {
    final readerProvider = context.read<ReaderProvider>();
    await readerProvider.openBook(book);
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const ReaderScreen(),
        ),
      );
    }
  }

  void _showError(String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: Colors.red.shade400,
        behavior: SnackBarBehavior.floating,
      ),
    );
    context.read<BookshelfProvider>().clearError();
  }

  void _confirmDelete(Book book) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除书籍'),
        content: Text('确定要删除《${book.title}》吗？\n相关的笔记和标注也会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<BookshelfProvider>().deleteBook(book.id);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories, color: AppTheme.primary, size: 24),
            SizedBox(width: 8),
            Text(AppConstants.appName),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.note_alt_outlined),
            tooltip: '笔记',
            onPressed: () {
              Navigator.of(context).pushNamed('/notes');
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () {
              Navigator.of(context).pushNamed('/settings');
            },
          ),
        ],
      ),
      body: Consumer<BookshelfProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.isEmpty) {
            return EmptyBookshelf(onImport: _showImportDialog);
          }

          return RefreshIndicator(
            onRefresh: provider.loadBooks,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: AppConstants.bookshelfColumns,
                  childAspectRatio: 0.65,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 16,
                ),
                itemCount: provider.books.length + 1, // +1 for add button
                itemBuilder: (context, index) {
                  if (index == provider.books.length) {
                    return _AddBookTile(onTap: _showImportDialog);
                  }
                  final book = provider.books[index];
                  return BookGridTile(
                    book: book,
                    onTap: () => _openBook(book),
                    onLongPress: () => _confirmDelete(book),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AddBookTile extends StatelessWidget {
  final VoidCallback onTap;

  const _AddBookTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.dividerColor,
                  width: 1.5,
                  strokeAlign: BorderSide.strokeAlignInside,
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.add_rounded,
                  size: 36,
                  color: AppTheme.primaryLight,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '导入书籍',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
