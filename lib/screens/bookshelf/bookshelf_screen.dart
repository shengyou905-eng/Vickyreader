import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../models/book.dart';
import '../../providers/bookshelf_provider.dart';
import '../../providers/reader_provider.dart';
import '../../services/auth_service.dart';
import '../../services/book_service.dart';
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

  void _openBook(Book book) {
    if (book.format == 'public') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('这是明台借阅书，请在明台书籍详情页查看公开批注'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final readerProvider = context.read<ReaderProvider>();
    unawaited(readerProvider.openBook(book));
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

  Future<void> _showBookActions(Book book) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.public_outlined),
              title: const Text('发布到明台'),
              subtitle: const Text('只公开书籍信息，不默认公开私密笔记'),
              enabled: book.format != 'public',
              onTap: () => Navigator.pop(ctx, 'publish'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除书籍'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'publish') {
      _confirmPublishBook(book);
    } else if (action == 'delete') {
      _confirmDelete(book);
    }
  }

  Future<void> _confirmPublishBook(Book book) async {
    var copyrightStatus = 'public_domain';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('发布到明台'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('是否公开《${book.title}》？'),
              const SizedBox(height: 10),
              const Text(
                '公开后：\n- 其他用户可浏览此书\n- 可查看公共划线与讨论\n- 不会公开你的私密笔记',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: copyrightStatus,
                decoration: const InputDecoration(labelText: '版权状态'),
                items: const [
                  DropdownMenuItem(
                    value: 'public_domain',
                    child: Text('公版书 public_domain'),
                  ),
                  DropdownMenuItem(
                    value: 'original',
                    child: Text('原创内容 original'),
                  ),
                  DropdownMenuItem(
                    value: 'authorized',
                    child: Text('已获授权 authorized'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => copyrightStatus = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认公开'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    try {
      await BookService.publishBookToMingtai(
        book: book,
        copyrightStatus: copyrightStatus,
        entryIds: const [],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已发布到明台'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('发布失败：$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
                    onLongPress: () => _showBookActions(book),
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
