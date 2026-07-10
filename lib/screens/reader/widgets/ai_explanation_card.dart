import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/theme.dart';
import '../../../models/ai_conversation.dart';
import '../../../providers/ai_provider.dart';
import '../../../providers/reader_provider.dart';
import '../../../services/book_service.dart';
import '../../../utils/markdown_sanitizer.dart';

class AiExplanationCard extends StatefulWidget {
  final VoidCallback onClose;

  const AiExplanationCard({super.key, required this.onClose});

  @override
  State<AiExplanationCard> createState() => _AiExplanationCardState();
}

class _AiExplanationCardState extends State<AiExplanationCard> {
  final TextEditingController _followUpController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _initialized = false;
  bool _preparing = true;
  bool _publishing = false;
  bool _published = false;
  int _sessionStartIndex = 0;
  String? _setupError;

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
      _sessionStartIndex = ai.messages.length;
      final chapter = await reader.ensureChapterLoaded();
      if (!mounted) return;
      setState(() => _preparing = false);
      await ai.explain(
        selectedText: selectedText,
        bookTitle: book.title,
        bookAuthor: book.author,
        chapterContent: chapter?.content ?? '',
        chapterIndex: reader.currentChapterIndex.toString(),
        chapterTitle: chapter?.title ?? '',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _setupError = '这一段暂时没能打开，请稍后重试。';
      });
    }
  }

  void _retry() {
    context.read<AiProvider>().clearError();
    _initialized = false;
    _sessionStartIndex = 0;
    _loadExplanation();
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

  Future<void> _publishExplanation() async {
    if (_publishing || _published) return;
    final reader = context.read<ReaderProvider>();
    final ai = context.read<AiProvider>();
    final book = reader.book;
    final selectedText = reader.selectedText ?? '';
    String? answer;
    for (final message in ai.messages.reversed) {
      if (message.role == 'assistant' && message.content.trim().isNotEmpty) {
        answer = message.content.trim();
        break;
      }
    }
    if (book == null ||
        !BookService.isMingtaiShelfBook(book) ||
        selectedText.isEmpty ||
        answer == null) {
      return;
    }

    setState(() => _publishing = true);
    try {
      await BookService.createPublicAnnotationForCurrentBook(
        book: book,
        chapterIndex: reader.currentChapterIndex,
        chapterTitle: reader.currentChapter?.title ?? '',
        source: 'ai_explanation',
        originalText: selectedText,
        annotationText: answer,
      );
      if (!mounted) return;
      setState(() => _published = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('小U解读已公开到明台')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('公开失败：$error')));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
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
                        palette: palette,
                        primary: primary,
                      ),
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
    required AppPalette palette,
    required Color primary,
  }) {
    final title = _preparing
        ? '小U正在读这一段'
        : ai.isLoading
        ? ai.loadingText ?? '小U正在组织语言'
        : '小U解读';
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
            child: Text(
              content,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w400,
                height: 1.72,
                color: palette.textPrimary,
              ),
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
    final reader = context.read<ReaderProvider>();
    final book = reader.book;
    final canPublish =
        book != null &&
        BookService.isMingtaiShelfBook(book) &&
        ai.error == null;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 7, 10, 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withAlpha(120), width: 0.5),
        ),
      ),
      child: Row(
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
            icon: Icon(Icons.arrow_upward_rounded, size: 20, color: primary),
          ),
          if (canPublish)
            PopupMenuButton<String>(
              tooltip: '更多',
              icon: Icon(
                Icons.more_horiz_rounded,
                size: 20,
                color: palette.textSecondary,
              ),
              onSelected: (value) {
                if (value == 'publish') _publishExplanation();
              },
              itemBuilder: (_) => [
                PopupMenuItem<String>(
                  value: 'publish',
                  enabled: !_publishing && !_published,
                  child: Row(
                    children: [
                      Icon(
                        _published
                            ? Icons.check_circle_outline_rounded
                            : Icons.public_outlined,
                        size: 18,
                      ),
                      const SizedBox(width: 9),
                      Text(
                        _published
                            ? '已公开到明台'
                            : _publishing
                            ? '正在公开…'
                            : '公开到明台',
                      ),
                    ],
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
