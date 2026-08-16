import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../l10n/l10n.dart';
import '../../models/book.dart';
import '../../providers/bookshelf_provider.dart';
import '../../providers/reader_provider.dart';
import '../reader/reader_screen.dart';

class BookDetailScreen extends StatelessWidget {
  final Book initialBook;

  const BookDetailScreen({super.key, required this.initialBook});

  Book _currentBook(BuildContext context) {
    final books = context.watch<BookshelfProvider>().books;
    for (final book in books) {
      if (book.id == initialBook.id) return book;
    }
    return initialBook;
  }

  Future<void> _openReader(BuildContext context, Book book) async {
    final reader = context.read<ReaderProvider>();
    unawaited(reader.openBook(book));
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ReaderScreen()));
    if (context.mounted) {
      unawaited(context.read<BookshelfProvider>().loadBooks());
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = _currentBook(context);
    final palette = context.appPalette;
    final visuals = context.appVisuals;
    final progress = book.readingProgress.clamp(0.0, 1.0);
    final progressPercent = (progress * 100).round();
    final description = book.description?.trim() ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.bookDetails), centerTitle: true),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            visuals.pagePadding,
            20,
            visuals.pagePadding,
            32,
          ),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BookDetailCover(book: book),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: visuals.ink,
                          fontSize: 23,
                          height: 1.28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        book.author,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: visuals.inkMuted,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        context.l10n.readingProgressLabel,
                        style: TextStyle(color: visuals.inkMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          color: palette.primary,
                          backgroundColor: palette.primarySoft,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$progressPercent%',
                        style: TextStyle(
                          color: palette.primaryDeep,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: const ValueKey('book-detail-read-button'),
                onPressed: () => _openReader(context, book),
                icon: const Icon(Icons.menu_book_rounded, size: 20),
                label: Text(
                  progress > 0
                      ? context.l10n.continueReadingPercent(progressPercent)
                      : context.l10n.startReading,
                ),
              ),
            ),
            SizedBox(height: visuals.sectionSpacing),
            Text(
              context.l10n.bookDescription,
              style: TextStyle(
                color: visuals.ink,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(minHeight: 112),
              padding: EdgeInsets.all(visuals.cardPadding),
              decoration: BoxDecoration(
                color: visuals.surface,
                borderRadius: BorderRadius.circular(visuals.cardRadius),
                border: Border.all(color: visuals.divider),
              ),
              child: Text(
                description.isEmpty
                    ? context.l10n.bookDescriptionUnavailable
                    : description,
                style: TextStyle(
                  color: description.isEmpty ? visuals.inkMuted : visuals.ink,
                  fontSize: 14,
                  height: 1.75,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookDetailCover extends StatelessWidget {
  final Book book;

  const _BookDetailCover({required this.book});

  @override
  Widget build(BuildContext context) {
    final visuals = context.appVisuals;
    final path = book.coverPath?.trim() ?? '';
    return SizedBox(
      width: 116,
      height: 168,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: path.isEmpty
            ? _CoverPlaceholder(book: book)
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _CoverPlaceholder(book: book),
                frameBuilder: (context, child, frame, _) => AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: frame == null
                      ? ColoredBox(
                          key: const ValueKey('book-cover-loading'),
                          color: visuals.surfaceSoft,
                        )
                      : child,
                ),
              ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  final Book book;

  const _CoverPlaceholder({required this.book});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.primarySoft,
        border: Border.all(color: palette.primary.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book_rounded, color: palette.primary, size: 30),
            const SizedBox(height: 10),
            Text(
              book.format.toUpperCase(),
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.primaryDeep,
                fontSize: 10,
                height: 1.35,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
