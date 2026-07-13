import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../services/book_service.dart';
import '../../../utils/ai_consent_gate.dart';
import '../../../utils/markdown_sanitizer.dart';

class XiaouCard extends StatefulWidget {
  final String source;
  final String originalText;
  final String? userNote;
  final String? aiTags;
  final String? aiUnderstanding;
  final String? bookTitle;
  final String? chapterTitle;
  final String? createdAt;
  final VoidCallback? onDelete;
  final ValueChanged<String>? onTagTap;

  const XiaouCard({
    super.key,
    required this.source,
    required this.originalText,
    this.userNote,
    this.aiTags,
    this.aiUnderstanding,
    this.bookTitle,
    this.chapterTitle,
    this.createdAt,
    this.onDelete,
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
    final isExplanation = widget.source == 'ai_explanation';
    final cleanedUnderstanding = stripMarkdownMarkers(
      widget.aiUnderstanding ?? '',
    ).trim();
    final expandable =
        !isExplanation &&
        _isExpandable(
          widget.originalText,
          widget.userNote,
          cleanedUnderstanding,
        );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isExplanation && cleanedUnderstanding.isNotEmpty
            ? () => _showExplanationDetail(
                context,
                explanation: cleanedUnderstanding,
                tags: tags,
              )
            : null,
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
                  maxLines: isExplanation ? 3 : (_expanded ? null : 4),
                  overflow: !isExplanation && _expanded
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
              if (cleanedUnderstanding.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2, right: 7),
                      child: Icon(
                        Icons.auto_awesome_outlined,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        cleanedUnderstanding,
                        maxLines: isExplanation ? 4 : (_expanded ? null : 4),
                        overflow: !isExplanation && _expanded
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
                const AiGeneratedNotice(compact: true),
              ],
              if (isExplanation && cleanedUnderstanding.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '展开完整解读',
                      style: TextStyle(
                        color: context.appPalette.primaryDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.open_in_full_rounded,
                      size: 14,
                      color: context.appPalette.primaryDark,
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
                    final label = Text(
                      tag,
                      style: const TextStyle(fontSize: 11),
                    );
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
      ),
    );
  }

  Future<void> _showExplanationDetail(
    BuildContext context, {
    required String explanation,
    required List<String> tags,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _XiaouExplanationSheet(
        originalText: widget.originalText,
        explanation: explanation,
        bookTitle: widget.bookTitle ?? '',
        chapterTitle: widget.chapterTitle ?? '',
        createdAt: widget.createdAt ?? '',
        tags: tags,
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

class _XiaouExplanationSheet extends StatelessWidget {
  final String originalText;
  final String explanation;
  final String bookTitle;
  final String chapterTitle;
  final String createdAt;
  final List<String> tags;

  const _XiaouExplanationSheet({
    required this.originalText,
    required this.explanation,
    required this.bookTitle,
    required this.chapterTitle,
    required this.createdAt,
    required this.tags,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.52,
      maxChildSize: 0.96,
      expand: false,
      snap: true,
      snapSizes: const [0.78, 0.96],
      builder: (context, scrollController) {
        return Material(
          color: palette.background,
          elevation: 0,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.divider,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '小U解读',
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (_sourceLine.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              _sourceLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: palette.divider.withAlpha(130)),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  children: [
                    if (originalText.trim().isNotEmpty) ...[
                      Text(
                        '选中的原文',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
                        decoration: BoxDecoration(
                          color: palette.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: palette.divider.withAlpha(105),
                          ),
                        ),
                        child: SelectionArea(
                          child: Text(
                            originalText.trim(),
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 14,
                              height: 1.7,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    Text(
                      '小U的解读',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SelectionArea(
                      child: Text(
                        explanation,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 16,
                          height: 1.78,
                        ),
                      ),
                    ),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: tags
                            .map(
                              (tag) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.primaryLight.withAlpha(70),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  tag,
                                  style: TextStyle(
                                    color: palette.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const AiGeneratedNotice(compact: false),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String get _sourceLine {
    final parts = <String>[];
    if (bookTitle.trim().isNotEmpty) parts.add('《${bookTitle.trim()}》');
    if (chapterTitle.trim().isNotEmpty) parts.add(chapterTitle.trim());
    final date = DateTime.tryParse(createdAt)?.toLocal();
    if (date != null) {
      parts.add(
        '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
      );
    }
    return parts.join(' · ');
  }
}
