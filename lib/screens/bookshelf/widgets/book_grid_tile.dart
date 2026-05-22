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
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
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
                        errorBuilder: (_, _, _) => _defaultCover(),
                      )
                    : _defaultCover(),
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
                backgroundColor: AppTheme.dividerColor,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.primaryLight),
                minHeight: 2,
              ),
            ),
        ],
      ),
    );
  }

  Widget _defaultCover() {
    final (icon, color1, color2) = _formatStyle();
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
                color: Colors.white.withAlpha(180),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                book.format.toUpperCase(),
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

  (IconData, Color, Color) _formatStyle() {
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
      default: // epub
        return (
          Icons.menu_book_rounded,
          AppTheme.primaryLight.withAlpha(80),
          AppTheme.primaryDark.withAlpha(60),
        );
    }
  }
}
