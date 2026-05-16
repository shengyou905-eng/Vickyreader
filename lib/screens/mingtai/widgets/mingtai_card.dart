import 'package:flutter/material.dart';
import '../../../config/theme.dart';

class MingtaiCard extends StatelessWidget {
  final String originalText;
  final String? userNote;
  final String? aiTags;
  final String? aiUnderstanding;
  final String? bookTitle;
  final VoidCallback? onDelete;

  const MingtaiCard({
    super.key,
    required this.originalText,
    this.userNote,
    this.aiTags,
    this.aiUnderstanding,
    this.bookTitle,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tags = (_parseTags(aiTags));
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Original text
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withAlpha(18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(originalText,
                style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, height: 1.5)),
            ),
            // User note
            if (userNote != null && userNote!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('💬 ', style: TextStyle(fontSize: 13)),
                Expanded(child: Text(userNote!,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary))),
              ]),
            ],
            // AI understanding
            if (aiUnderstanding != null && aiUnderstanding!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('🤖 ', style: TextStyle(fontSize: 13)),
                Expanded(child: Text(aiUnderstanding!,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary))),
              ]),
            ],
            // Tags
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, children: tags.map((t) => Chip(
                label: Text(t, style: const TextStyle(fontSize: 11)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                backgroundColor: AppTheme.primaryLight.withAlpha(25),
                side: BorderSide.none,
              )).toList()),
            ],
            // Source
            if (bookTitle != null && bookTitle!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.menu_book, size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(bookTitle!,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                const Spacer(),
                if (onDelete != null)
                  GestureDetector(
                    onTap: onDelete,
                    child: const Icon(Icons.delete_outline, size: 18, color: AppTheme.textSecondary),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  List<String> _parseTags(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    return raw
        .split(',')
        .map((t) => t.trim().replaceAll('"', '').replaceAll('[', '').replaceAll(']', ''))
        .where((t) => t.isNotEmpty)
        .toList();
  }
}
