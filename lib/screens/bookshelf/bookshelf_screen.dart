import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../models/book.dart';
import '../../l10n/l10n.dart';
import '../../providers/bookshelf_provider.dart';
import '../../providers/reader_provider.dart';
import '../../services/auth_service.dart';
import '../../services/book_service.dart';
import '../../services/sync_service.dart';
import '../mingtai/community_mingtai_screen.dart';
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
    if (BookService.isMingtaiShelfBook(book) || book.format == 'public') {
      _showError(context.l10n.legacyPublicBookDisabled);
      return;
    }
    final readerProvider = context.read<ReaderProvider>();
    unawaited(readerProvider.openBook(book));
    if (mounted) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ReaderScreen()));
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
        title: Text(context.l10n.deleteBook),
        content: Text(context.l10n.deleteBookConfirm(book.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<BookshelfProvider>().deleteBook(book.id);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
            ),
            child: Text(context.l10n.delete),
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
              leading: const Icon(Icons.edit_note_rounded),
              title: Text(context.l10n.shareReadingThought),
              subtitle: Text(context.l10n.shareReadingThoughtSubtitle),
              enabled: !BookService.isMingtaiShelfBook(book),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(context.l10n.deleteBook),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'share') {
      final created = await showCommunityPostComposer(context, localBook: book);
      if (created == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.publishedToMingtai)),
        );
      }
    } else if (action == 'delete') {
      _confirmDelete(book);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories, color: palette.icon, size: 24),
            const SizedBox(width: 8),
            Text(context.l10n.appName),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: context.l10n.settingsTooltip,
            onPressed: () {
              Navigator.of(context).pushNamed('/settings');
            },
          ),
        ],
      ),
      body: Consumer<BookshelfProvider>(
        builder: (context, provider, _) {
          if (provider.isInitialLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null && provider.books.isEmpty) {
            return _BookshelfLoadFailure(
              message: provider.error!,
              onRetry: provider.loadBooks,
            );
          }

          if (provider.isEmpty) {
            return EmptyBookshelf(onImport: _showImportDialog);
          }

          return Column(
            children: [
              if (provider.isRefreshing)
                const LinearProgressIndicator(minHeight: 2),
              if (provider.error != null)
                _BookshelfLoadNotice(onRetry: provider.loadBooks),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: provider.loadBooks,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: GridView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: AppConstants.bookshelfColumns,
                            childAspectRatio: 0.65,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 16,
                          ),
                      itemCount: provider.books.length + 1,
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
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BookshelfLoadNotice extends StatelessWidget {
  final VoidCallback onRetry;

  const _BookshelfLoadNotice({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: palette.icon),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.refreshFailedRetained,
              style: TextStyle(color: palette.textSecondary, fontSize: 13),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
        ],
      ),
    );
  }
}

class _BookshelfLoadFailure extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _BookshelfLoadFailure({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 34, color: palette.icon),
            const SizedBox(height: 14),
            Text(
              context.l10n.bookshelfUnavailable,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
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

class _AddBookTile extends StatelessWidget {
  final VoidCallback onTap;

  const _AddBookTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: palette.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: palette.divider,
                  width: 1.5,
                  strokeAlign: BorderSide.strokeAlignInside,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.add_rounded,
                  size: 36,
                  color: palette.illustration,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.importBook,
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
