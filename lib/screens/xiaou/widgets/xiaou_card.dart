import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../services/book_service.dart';

class XiaouCard extends StatefulWidget {
  final String source;
  final String originalText;
  final String? userNote;
  final String? aiTags;
  final String? aiUnderstanding;
  final String? bookTitle;
  final VoidCallback? onDelete;
  final VoidCallback? onPublish;
  final ValueChanged<String>? onTagTap;

  const XiaouCard({
    super.key,
    required this.source,
    required this.originalText,
    this.userNote,
    this.aiTags,
    this.aiUnderstanding,
    this.bookTitle,
    this.onDelete,
    this.onPublish,
    this.onTagTap,
  });

  @override
  State<XiaouCard> createState() => _XiaouCardState();
}

class _XiaouCardState extends State<XiaouCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tags = _parseTags(widget.aiTags);
    final expandable = _isExpandable(
      widget.originalText,
      widget.userNote,
      widget.aiUnderstanding,
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _sourceIcon(widget.source),
                  size: 14,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  _sourceLabel(widget.source),
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withAlpha(18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.originalText,
                maxLines: _expanded ? null : 4,
                overflow: _expanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  height: 1.5,
                ),
              ),
            ),
            if (widget.userNote != null && widget.userNote!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💬 ', style: TextStyle(fontSize: 13)),
                  Expanded(
                    child: Text(
                      widget.userNote!,
                      maxLines: _expanded ? null : 3,
                      overflow: _expanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (widget.aiUnderstanding != null &&
                widget.aiUnderstanding!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🤖 ', style: TextStyle(fontSize: 13)),
                  Expanded(
                    child: Text(
                      widget.aiUnderstanding!,
                      maxLines: _expanded ? null : 4,
                      overflow: _expanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (expandable) ...[
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? '收起' : '展开'),
              ),
            ],
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                children: tags.map((tag) {
                  final label = Text(tag, style: const TextStyle(fontSize: 11));
                  final canOpenTopic =
                      widget.onTagTap != null &&
                      BookService.isMingtaiTopicTag(tag);
                  if (!canOpenTopic) {
                    return Chip(
                      label: label,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      backgroundColor: AppTheme.primaryLight.withAlpha(25),
                      side: BorderSide.none,
                    );
                  }
                  return ActionChip(
                    label: label,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppTheme.primaryLight.withAlpha(25),
                    side: BorderSide.none,
                    onPressed: () => widget.onTagTap!(tag),
                  );
                }).toList(),
              ),
            ],
            if (widget.bookTitle != null && widget.bookTitle!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.menu_book,
                    size: 14,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.bookTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (widget.onPublish != null)
                    Tooltip(
                      message: '公开到明台',
                      child: GestureDetector(
                        onTap: widget.onPublish,
                        child: const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: Icon(
                            Icons.public_outlined,
                            size: 18,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  if (widget.onDelete != null)
                    GestureDetector(
                      onTap: widget.onDelete,
                      child: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _sourceLabel(String source) {
    return switch (source) {
      'thought' || 'manual' => '想法',
      'highlight' => '划线',
      'ai_explanation' => '小U解读',
      _ => '阅读痕迹',
    };
  }

  IconData _sourceIcon(String source) {
    return switch (source) {
      'thought' || 'manual' => Icons.edit_note_outlined,
      'highlight' => Icons.format_quote_outlined,
      'ai_explanation' => Icons.auto_awesome_outlined,
      _ => Icons.menu_book_outlined,
    };
  }

  bool _isExpandable(String original, String? note, String? understanding) {
    final combined = [
      original,
      note ?? '',
      understanding ?? '',
    ].where((text) => text.trim().isNotEmpty).join('\n');
    return combined.length > 120 || combined.split('\n').length > 5;
  }

  List<String> _parseTags(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    return raw
        .split(',')
        .map(
          (tag) => tag
              .trim()
              .replaceAll('"', '')
              .replaceAll('[', '')
              .replaceAll(']', ''),
        )
        .where((tag) => tag.isNotEmpty)
        .toList();
  }
}
