import 'dart:io';
import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../models/book.dart';

class BookGridTile extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const BookGridTile({
    super.key,
    required this.book,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: book.coverPath != null
                    ? Image.file(
                        File(book.coverPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _defaultCover(palette),
                      )
                    : _defaultCover(palette),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
          ),
          if (book.readingProgress > 0 && book.readingProgress < 1)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: LinearProgressIndicator(
                value: book.readingProgress,
                backgroundColor: palette.divider,
                valueColor: AlwaysStoppedAnimation<Color>(palette.primaryLight),
                minHeight: 2,
              ),
            ),
        ],
      ),
    );
  }

  Widget _defaultCover(AppPalette palette) {
    final (icon, color1, color2) = _formatStyle(palette);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color1, color2],
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 32, color: color2),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: color2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Format badge
          Positioned(
            bottom: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: palette.card.withAlpha(205),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                _formatLabel(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: color2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatLabel() {
    if (book.format == 'public' ||
        book.id.startsWith('mingtai_') ||
        book.id.startsWith('mingtai:')) {
      return '明台';
    }
    return book.format.toUpperCase();
  }

  (IconData, Color, Color) _formatStyle(AppPalette palette) {
    if (book.id.startsWith('mingtai_') || book.id.startsWith('mingtai:')) {
      return (
        Icons.auto_stories_rounded,
        palette.illustration.withAlpha(86),
        palette.icon.withAlpha(105),
      );
    }
    switch (book.format) {
      case 'txt':
        return (
          Icons.article_rounded,
          Colors.grey.shade300,
          Colors.grey.shade600,
        );
      case 'pdf':
        return (
          Icons.picture_as_pdf_rounded,
          Colors.red.shade100,
          Colors.red.shade700,
        );
      case 'public':
        return (
          Icons.auto_stories_rounded,
          palette.illustration.withAlpha(86),
          palette.icon.withAlpha(105),
        );
      default: // epub
        return (
          Icons.menu_book_rounded,
          palette.illustration.withAlpha(96),
          palette.icon.withAlpha(95),
        );
    }
  }
}
