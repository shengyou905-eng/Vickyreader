import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../models/ai_conversation.dart';
import '../../../models/user_entry_follow_up.dart';
import '../../../services/ai_service.dart';
import '../../../services/book_service.dart';
import '../../../utils/ai_consent_gate.dart';
import '../../../utils/markdown_sanitizer.dart';

class XiaouCard extends StatefulWidget {
  final String source;
  final String entryId;
  final String originalText;
  final String? userNote;
  final String? aiTags;
  final String? aiUnderstanding;
  final String? bookTitle;
  final String? chapterIndex;
  final String? chapterTitle;
  final String? createdAt;
  final bool isImportant;
  final int followUpCount;
  final String? latestFollowUpQuestion;
  final VoidCallback? onBookTap;
  final ValueChanged<String>? onTagTap;

  const XiaouCard({
    super.key,
    required this.source,
    this.entryId = '',
    required this.originalText,
    this.userNote,
    this.aiTags,
    this.aiUnderstanding,
    this.bookTitle,
    this.chapterIndex,
    this.chapterTitle,
    this.createdAt,
    this.isImportant = false,
    this.followUpCount = 0,
    this.latestFollowUpQuestion,
    this.onBookTap,
    this.onTagTap,
  });

  @override
  State<XiaouCard> createState() => _XiaouCardState();
}

class _XiaouCardState extends State<XiaouCard> {
  bool _expanded = false;
  late int _followUpCount;
  late String _latestFollowUpQuestion;

  @override
  void initState() {
    super.initState();
    _followUpCount = widget.followUpCount;
    _latestFollowUpQuestion = widget.latestFollowUpQuestion?.trim() ?? '';
  }

  @override
  void didUpdateWidget(covariant XiaouCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.followUpCount != widget.followUpCount) {
      _followUpCount = widget.followUpCount;
    }
    if (oldWidget.latestFollowUpQuestion != widget.latestFollowUpQuestion) {
      _latestFollowUpQuestion = widget.latestFollowUpQuestion?.trim() ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tags = _parseTags(widget.aiTags, source: widget.source);
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
                  const Spacer(),
                  if (widget.isImportant)
                    Icon(
                      Icons.star_rounded,
                      size: 17,
                      color: context.appPalette.primaryDark,
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
                if (_followUpCount > 0) ...[
                  const SizedBox(height: 7),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _latestFollowUpQuestion.isEmpty
                          ? '已继续追问 $_followUpCount 次'
                          : '$_followUpCount 次追问 · $_latestFollowUpQuestion',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appPalette.textSecondary,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
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
              const SizedBox(height: 10),
              _buildSourceContext(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceContext(BuildContext context) {
    final book = widget.bookTitle?.trim() ?? '';
    final chapterTitle = widget.chapterTitle?.trim() ?? '';
    final chapterIndex = widget.chapterIndex?.trim() ?? '';
    final chapter = chapterTitle.isNotEmpty
        ? chapterTitle
        : chapterIndex.isNotEmpty
        ? '第 $chapterIndex 章'
        : '章节未记录';
    final palette = context.appPalette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.menu_book_outlined, size: 14, color: palette.icon),
        const SizedBox(width: 5),
        Expanded(
          child: InkWell(
            onTap: book.isEmpty ? null : widget.onBookTap,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${book.isEmpty ? '未记录书名' : book} · $chapter',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: book.isEmpty
                      ? palette.textSecondary
                      : palette.primaryDark,
                  fontWeight: book.isEmpty ? FontWeight.w400 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showExplanationDetail(
    BuildContext context, {
    required String explanation,
    required List<String> tags,
  }) {
    return showModalBottomSheet<_FollowUpSheetResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _XiaouExplanationSheet(
        entryId: widget.entryId,
        originalText: widget.originalText,
        explanation: explanation,
        bookTitle: widget.bookTitle ?? '',
        chapterTitle: widget.chapterTitle ?? '',
        createdAt: widget.createdAt ?? '',
        tags: tags,
      ),
    ).then((result) {
      if (!mounted || result == null) return;
      setState(() {
        _followUpCount = result.count;
        _latestFollowUpQuestion = result.latestQuestion;
      });
    });
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

  List<String> _parseTags(String? raw, {required String source}) {
    if (raw == null || raw.isEmpty) return [];
    final result = <String>[];
    final seen = <String>{};
    for (final value in raw.split(',')) {
      final tag = value
          .trim()
          .replaceAll('"', '')
          .replaceAll('[', '')
          .replaceAll(']', '');
      final key = tag.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (tag.isEmpty || _isSourceTag(key, source) || !seen.add(key)) {
        continue;
      }
      result.add(tag);
    }
    return result;
  }

  bool _isSourceTag(String tag, String source) {
    return switch (source) {
      'ai_explanation' => const {'小u解释', '小u解读', 'ai解释', 'ai解读'}.contains(tag),
      'thought' || 'manual' => const {'想法', '阅读想法', 'thought'}.contains(tag),
      'highlight' => const {'划线', 'highlight'}.contains(tag),
      _ => false,
    };
  }
}

class _FollowUpSheetResult {
  final int count;
  final String latestQuestion;

  const _FollowUpSheetResult({
    required this.count,
    required this.latestQuestion,
  });
}

class _XiaouExplanationSheet extends StatefulWidget {
  final String entryId;
  final String originalText;
  final String explanation;
  final String bookTitle;
  final String chapterTitle;
  final String createdAt;
  final List<String> tags;

  const _XiaouExplanationSheet({
    required this.entryId,
    required this.originalText,
    required this.explanation,
    required this.bookTitle,
    required this.chapterTitle,
    required this.createdAt,
    required this.tags,
  });

  @override
  State<_XiaouExplanationSheet> createState() => _XiaouExplanationSheetState();
}

class _XiaouExplanationSheetState extends State<_XiaouExplanationSheet> {
  final TextEditingController _followUpController = TextEditingController();
  List<UserEntryFollowUp> _followUps = const [];
  bool _loadingFollowUps = true;
  bool _sending = false;
  String _streamingQuestion = '';
  String _streamingAnswer = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFollowUps();
  }

  Future<void> _loadFollowUps() async {
    if (widget.entryId.isEmpty) {
      if (mounted) setState(() => _loadingFollowUps = false);
      return;
    }
    try {
      final rows = await BookService.getUserEntryFollowUps(widget.entryId);
      if (!mounted) return;
      setState(() {
        _followUps = rows;
        _loadingFollowUps = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingFollowUps = false;
        _error = '追问记录暂时没有同步，请稍后再试。';
      });
    }
  }

  Future<void> _sendFollowUp() async {
    if (_sending || widget.entryId.isEmpty) return;
    final question = _followUpController.text.trim();
    if (question.isEmpty) return;
    if (!await AiConsentGate.ensure(context) || !mounted) return;
    _followUpController.clear();
    setState(() {
      _sending = true;
      _streamingQuestion = question;
      _streamingAnswer = '';
      _error = null;
    });

    try {
      final history = <AiMessage>[
        AiMessage(
          role: 'user',
          content: widget.originalText,
          timestamp: DateTime.now(),
        ),
        AiMessage(
          role: 'assistant',
          content: widget.explanation,
          timestamp: DateTime.now(),
        ),
        for (final item in _followUps) ...[
          AiMessage(
            role: 'user',
            content: item.question,
            timestamp: item.createdAt,
          ),
          AiMessage(
            role: 'assistant',
            content: item.answer,
            timestamp: item.createdAt,
          ),
        ],
      ];
      final buffer = StringBuffer();
      await for (final chunk in AiService.chatStream(
        message: question,
        conversationHistory: history,
      )) {
        buffer.write(chunk);
        if (mounted) setState(() => _streamingAnswer = buffer.toString());
      }
      final answer = buffer.toString().trim();
      if (answer.isEmpty) throw Exception('empty answer');
      final saved = await BookService.insertUserEntryFollowUp(
        entryId: widget.entryId,
        question: question,
        answer: answer,
      );
      if (!mounted) return;
      setState(() {
        _followUps = [..._followUps, saved];
        _sending = false;
        _streamingQuestion = '';
        _streamingAnswer = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = AiService.friendlyError(e);
      });
    }
  }

  void _close() {
    Navigator.pop(
      context,
      _FollowUpSheetResult(
        count: _followUps.length,
        latestQuestion: _followUps.isEmpty ? '' : _followUps.last.question,
      ),
    );
  }

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
                      onPressed: _close,
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
                    if (widget.originalText.trim().isNotEmpty) ...[
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
                            widget.originalText.trim(),
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
                        widget.explanation,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 16,
                          height: 1.78,
                        ),
                      ),
                    ),
                    if (widget.tags.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: widget.tags
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
                    if (_loadingFollowUps) ...[
                      const SizedBox(height: 24),
                      const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ] else if (_followUps.isNotEmpty || _sending) ...[
                      const SizedBox(height: 28),
                      Text(
                        '继续追问',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final followUp in _followUps)
                        _FollowUpPair(followUp: followUp),
                      if (_sending)
                        _FollowUpPair(
                          followUp: UserEntryFollowUp(
                            id: 'streaming',
                            entryId: widget.entryId,
                            question: _streamingQuestion,
                            answer: _streamingAnswer.isEmpty
                                ? '小U正在想这一句…'
                                : stripMarkdownMarkers(_streamingAnswer),
                            createdAt: DateTime.now(),
                          ),
                        ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.entryId.isNotEmpty)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 10, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _followUpController,
                            enabled: !_sending,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendFollowUp(),
                            decoration: InputDecoration(
                              hintText: '继续问这一段…',
                              filled: true,
                              fillColor: palette.card,
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '发送',
                          onPressed: _sending ? null : _sendFollowUp,
                          icon: Icon(
                            Icons.arrow_upward_rounded,
                            color: palette.primary,
                          ),
                        ),
                      ],
                    ),
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
    if (widget.bookTitle.trim().isNotEmpty) {
      parts.add('《${widget.bookTitle.trim()}》');
    }
    if (widget.chapterTitle.trim().isNotEmpty) {
      parts.add(widget.chapterTitle.trim());
    }
    final date = DateTime.tryParse(widget.createdAt)?.toLocal();
    if (date != null) {
      parts.add(
        '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
      );
    }
    return parts.join(' · ');
  }

  @override
  void dispose() {
    _followUpController.dispose();
    super.dispose();
  }
}

class _FollowUpPair extends StatelessWidget {
  final UserEntryFollowUp followUp;

  const _FollowUpPair({required this.followUp});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: palette.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                followUp.question,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 13.5,
                  height: 1.55,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SelectionArea(
            child: Text(
              stripMarkdownMarkers(followUp.answer),
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14.5,
                height: 1.72,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
