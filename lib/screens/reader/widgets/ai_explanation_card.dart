import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/theme.dart';
import '../../../models/ai_conversation.dart';
import '../../../models/ai_explain_mode.dart';
import '../../../providers/ai_provider.dart';
import '../../../providers/reader_provider.dart';
import '../../../utils/markdown_sanitizer.dart';
import '../../../utils/ai_consent_gate.dart';

class AiExplanationCard extends StatefulWidget {
  final VoidCallback onClose;
  final VoidCallback onToggleExpanded;
  final bool isExpanded;

  const AiExplanationCard({
    super.key,
    required this.onClose,
    required this.onToggleExpanded,
    required this.isExpanded,
  });

  @override
  State<AiExplanationCard> createState() => _AiExplanationCardState();
}

class _AiExplanationCardState extends State<AiExplanationCard> {
  final TextEditingController _followUpController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _initialized = false;
  bool _preparing = true;
  int _sessionStartIndex = 0;
  String? _setupError;
  AiExplainMode _activeMode = AiExplainMode.auto;
  String _selectedText = '';
  String _bookTitle = '';
  String _bookAuthor = '';
  String _chapterContent = '';
  String _chapterIndex = '';
  String _chapterTitle = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExplanation());
  }

  Future<void> _loadExplanation() async {
    if (_initialized) return;
    _initialized = true;
    if (mounted) {
      setState(() {
        _preparing = true;
        _setupError = null;
      });
    }

    final reader = context.read<ReaderProvider>();
    final ai = context.read<AiProvider>();
    final selectedText = reader.selectedText;
    final book = reader.book;
    if (selectedText == null || book == null) {
      if (mounted) setState(() => _preparing = false);
      return;
    }

    try {
      await ai.loadHistory(book.id);
      if (!mounted) return;
      final chapter = await reader.ensureChapterLoaded();
      if (!mounted) return;
      _selectedText = selectedText;
      _bookTitle = book.title;
      _bookAuthor = book.author;
      _chapterContent = chapter?.content ?? '';
      _chapterIndex = reader.currentChapterIndex.toString();
      _chapterTitle = chapter?.title ?? '';
      setState(() => _preparing = false);
      await _runExplanation(ai);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _setupError = '这一段暂时没能打开，请稍后重试。';
      });
    }
  }

  void _retry() {
    final ai = context.read<AiProvider>();
    ai.clearError();
    if (_selectedText.isEmpty) {
      _initialized = false;
      _loadExplanation();
      return;
    }
    _runExplanation(ai);
  }

  Future<void> _runExplanation(AiProvider ai) async {
    if (_selectedText.isEmpty) return;
    _sessionStartIndex = ai.messages.length;
    if (mounted) {
      setState(() => _setupError = null);
    }
    await ai.explain(
      selectedText: _selectedText,
      bookTitle: _bookTitle,
      bookAuthor: _bookAuthor,
      chapterContent: _chapterContent,
      chapterIndex: _chapterIndex,
      chapterTitle: _chapterTitle,
      mode: _activeMode,
    );
  }

  Future<void> _selectMode(AiExplainMode mode) async {
    if (_activeMode == mode) return;
    setState(() {
      _activeMode = mode;
      _setupError = null;
    });
    final ai = context.read<AiProvider>();
    await ai.cancelGeneration();
    if (!mounted || _preparing) return;
    await _runExplanation(ai);
  }

  void _sendFollowUp() {
    final ai = context.read<AiProvider>();
    if (ai.isLoading) return;
    final text = _followUpController.text.trim();
    if (text.isEmpty) return;
    _followUpController.clear();
    ai.sendFollowUp(text);
  }

  void _close() {
    context.read<AiProvider>().clearMessages();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final primary = Theme.of(context).colorScheme.primary;
    final glassColor = Color.alphaBlend(
      primary.withAlpha(10),
      Colors.white.withAlpha(188),
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: primary.withAlpha(20),
            blurRadius: 34,
            spreadRadius: 1,
            offset: const Offset(0, -7),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: glassColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
              border: Border.all(
                color: Colors.white.withAlpha(180),
                width: 0.5,
              ),
            ),
            child: SafeArea(
              top: false,
              child: Consumer<AiProvider>(
                builder: (context, ai, _) {
                  final sessionMessages = _sessionMessages(ai);
                  final visibleMessages = _preparing
                      ? const <AiMessage>[]
                      : _visibleMessages(sessionMessages);
                  final error = _setupError ?? ai.error;
                  final isWorking = _preparing || ai.isLoading;
                  final hasAnswer = sessionMessages.any(
                    (message) =>
                        message.role == 'assistant' &&
                        message.content.trim().isNotEmpty,
                  );

                  _scheduleAutoScroll();
                  return Column(
                    children: [
                      _buildHandle(primary),
                      _buildHeader(
                        ai: ai,
                        isWorking: isWorking,
                        isExpanded: widget.isExpanded,
                        palette: palette,
                        primary: primary,
                      ),
                      if (_selectedText.isNotEmpty)
                        _buildSelectedText(
                          palette,
                          primary,
                          expanded: widget.isExpanded,
                        ),
                      _buildModeSelector(palette, primary),
                      Expanded(
                        child: error != null
                            ? _buildError(error, palette, primary)
                            : _buildMessages(
                                messages: visibleMessages,
                                isWorking: isWorking,
                                loadingText: ai.loadingText,
                                palette: palette,
                                primary: primary,
                              ),
                      ),
                      if (!isWorking && error == null && hasAnswer)
                        _buildCompletedActions(ai, palette, primary),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<AiMessage> _sessionMessages(AiProvider ai) {
    final start = math.min(_sessionStartIndex, ai.messages.length);
    return ai.messages.skip(start).toList(growable: false);
  }

  List<AiMessage> _visibleMessages(List<AiMessage> messages) {
    if (messages.isNotEmpty && messages.first.role == 'user') {
      return messages.skip(1).toList(growable: false);
    }
    return messages;
  }

  Widget _buildHandle(Color primary) {
    return Padding(
      padding: const EdgeInsets.only(top: 9, bottom: 2),
      child: Container(
        width: 30,
        height: 3,
        decoration: BoxDecoration(
          color: primary.withAlpha(34),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _buildHeader({
    required AiProvider ai,
    required bool isWorking,
    required bool isExpanded,
    required AppPalette palette,
    required Color primary,
  }) {
    final title = _preparing
        ? '小U正在读这一段'
        : ai.isLoading
        ? ai.loadingText ?? '小U正在组织语言'
        : _activeMode.fullLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 5, 10, 8),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isWorking ? primary.withAlpha(190) : primary.withAlpha(90),
              boxShadow: isWorking
                  ? [
                      BoxShadow(
                        color: primary.withAlpha(55),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
          ),
          if (ai.isLoading)
            TextButton(
              onPressed: ai.cancelGeneration,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: palette.textSecondary,
              ),
              child: const Text('停止'),
            ),
          TextButton.icon(
            onPressed: widget.onToggleExpanded,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: primary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            icon: Icon(
              isExpanded
                  ? Icons.close_fullscreen_rounded
                  : Icons.open_in_full_rounded,
              size: 16,
            ),
            label: Text(isExpanded ? '收起' : '展开'),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: _close,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close_rounded,
              size: 19,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedText(
    AppPalette palette,
    Color primary, {
    required bool expanded,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '“',
            style: TextStyle(
              fontSize: 18,
              height: 1.1,
              color: primary.withAlpha(115),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _selectedText.replaceAll(RegExp(r'\s+'), ' ').trim(),
              maxLines: expanded ? 5 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector(AppPalette palette, Color primary) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 7),
        itemCount: AiExplainMode.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 5),
        itemBuilder: (context, index) {
          final mode = AiExplainMode.values[index];
          final selected = mode == _activeMode;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _selectMode(mode),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                constraints: const BoxConstraints(minWidth: 52),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 11),
                decoration: BoxDecoration(
                  color: selected
                      ? primary.withAlpha(24)
                      : Colors.white.withAlpha(52),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? primary.withAlpha(48)
                        : Colors.white.withAlpha(80),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  mode.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? primary : palette.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMessages({
    required List<AiMessage> messages,
    required bool isWorking,
    required String? loadingText,
    required AppPalette palette,
    required Color primary,
  }) {
    final nonEmptyMessages = messages
        .where((message) => message.content.trim().isNotEmpty)
        .toList(growable: false);
    final showWaiting =
        isWorking &&
        (messages.isEmpty ||
            messages.last.role != 'assistant' ||
            messages.last.content.trim().isEmpty);

    if (nonEmptyMessages.isEmpty) {
      return _ReadingStatus(
        text: loadingText ?? '小U正在读这一段…',
        color: palette.textSecondary,
        accent: primary,
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      itemCount: nonEmptyMessages.length + (showWaiting ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= nonEmptyMessages.length) {
          return _InlineThinking(
            text: loadingText ?? '正在组织语言…',
            color: palette.textSecondary,
            accent: primary,
          );
        }
        final message = nonEmptyMessages[index];
        final isUser = message.role == 'user';
        final content = stripMarkdownMarkers(message.content);
        if (!isUser) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _StructuredExplanationText(
              content: content,
              textColor: palette.textPrimary,
              accent: primary,
            ),
          );
        }
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(bottom: 14, left: 42),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: primary.withAlpha(20),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              content,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: palette.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildError(String error, AppPalette palette, Color primary) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline_rounded, size: 25, color: primary),
            const SizedBox(height: 10),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _retry, child: const Text('再试一次')),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedActions(
    AiProvider ai,
    AppPalette palette,
    Color primary,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 7, 10, 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withAlpha(120), width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: 6),
            child: AiGeneratedNotice(compact: true),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _followUpController,
                  decoration: InputDecoration(
                    hintText: '继续问一句…',
                    filled: true,
                    fillColor: Colors.white.withAlpha(88),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 9,
                    ),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: const TextStyle(fontSize: 13.5),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendFollowUp(),
                ),
              ),
              IconButton(
                tooltip: '发送',
                onPressed: _sendFollowUp,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.arrow_upward_rounded,
                  size: 20,
                  color: primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _scheduleAutoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.maxScrollExtent - position.pixels > 96) return;
      _scrollController.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _followUpController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _StructuredExplanationText extends StatelessWidget {
  static const _headings = {
    '难点在哪里',
    '核心解释',
    '文本依据',
    '核心意思',
    '换成日常语言',
    '需要留意',
    '核心命题',
    '句法骨架',
    '修饰与指代',
    '逻辑关系',
    '论证位置',
    '通俗改写',
    '关键概念',
    '本文中的含义',
    '容易混淆',
    '概念之间的关系',
    '放回原句',
    '这段的作用',
    '作者的主张',
    '前提与依据',
    '推理链条',
    '限定与潜在异议',
    '结论边界',
  };

  final String content;
  final Color textColor;
  final Color accent;

  const _StructuredExplanationText({
    required this.content,
    required this.textColor,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final lines = content.split('\n');
    return Text.rich(
      TextSpan(
        children: [
          for (var index = 0; index < lines.length; index++) ...[
            TextSpan(
              text: lines[index],
              style: _isHeading(lines[index])
                  ? TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: index == 0 ? 1.5 : 2.25,
                      color: Color.lerp(textColor, accent, 0.24),
                    )
                  : TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w400,
                      height: 1.72,
                      color: textColor,
                    ),
            ),
            if (index < lines.length - 1) const TextSpan(text: '\n'),
          ],
        ],
      ),
    );
  }

  bool _isHeading(String line) {
    final normalized = line.trim().replaceFirst(RegExp(r'[：:]$'), '');
    return _headings.contains(normalized);
  }
}

class _ReadingStatus extends StatelessWidget {
  final String text;
  final Color color;
  final Color accent;

  const _ReadingStatus({
    required this.text,
    required this.color,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: _InlineThinking(text: text, color: color, accent: accent),
      ),
    );
  }
}

class _InlineThinking extends StatelessWidget {
  final String text;
  final Color color;
  final Color accent;

  const _InlineThinking({
    required this.text,
    required this.color,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 1.7,
              color: accent.withAlpha(170),
            ),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, height: 1.5, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
