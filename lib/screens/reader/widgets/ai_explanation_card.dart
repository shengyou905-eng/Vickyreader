import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../providers/reader_provider.dart';
import '../../../providers/ai_provider.dart';
import '../../../services/book_service.dart';

class AiExplanationCard extends StatefulWidget {
  const AiExplanationCard({super.key});

  @override
  State<AiExplanationCard> createState() => _AiExplanationCardState();
}

class _AiExplanationCardState extends State<AiExplanationCard> {
  final TextEditingController _followUpController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _initialized = false;
  bool _publishing = false;
  bool _published = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExplanation());
  }

  Future<void> _loadExplanation() async {
    if (_initialized) return;
    _initialized = true;

    final reader = context.read<ReaderProvider>();
    final ai = context.read<AiProvider>();

    if (reader.selectedText == null || reader.book == null) return;

    await ai.loadHistory(reader.book!.id);
    final chapter = await reader.ensureChapterLoaded();
    if (!mounted) return;
    await ai.explain(
      selectedText: reader.selectedText!,
      bookTitle: reader.book!.title,
      bookAuthor: reader.book!.author,
      chapterContent: chapter?.content ?? '',
      chapterIndex: reader.currentChapterIndex.toString(),
      chapterTitle: chapter?.title ?? '',
    );
  }

  void _sendFollowUp() {
    if (context.read<AiProvider>().isLoading) return;
    final text = _followUpController.text.trim();
    if (text.isEmpty) return;
    _followUpController.clear();
    context.read<AiProvider>().sendFollowUp(text);
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
      ).showSnackBar(const SnackBar(content: Text('小U解释已公开到明台')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('公开失败：$e')));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final primary = Theme.of(context).colorScheme.primary;
    final glassColor = Color.alphaBlend(
      primary.withAlpha(18),
      Colors.white.withAlpha(172),
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: primary.withAlpha(28),
            blurRadius: 38,
            spreadRadius: 3,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              color: glassColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(
                color: Colors.white.withAlpha(176),
                width: 0.5,
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 2),
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: primary.withAlpha(42),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withAlpha(132),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, color: primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '小U解释',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Consumer<AiProvider>(
                        builder: (context, ai, _) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (ai.isLoading)
                                TextButton(
                                  onPressed: ai.cancelGeneration,
                                  child: const Text('停止'),
                                ),
                              IconButton(
                                icon: Icon(
                                  Icons.close,
                                  size: 18,
                                  color: palette.textSecondary,
                                ),
                                onPressed: () {
                                  ai.clearMessages();
                                  context
                                      .read<ReaderProvider>()
                                      .clearSelection();
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                // Messages
                Expanded(
                  child: Consumer<AiProvider>(
                    builder: (context, ai, _) {
                      if (ai.isLoading && ai.messages.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: primary),
                              const SizedBox(height: 12),
                              Text(
                                ai.loadingText ?? '小U正在阅读这一段…',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: palette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      if (ai.error != null) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 36,
                                color: Colors.red.shade300,
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Text(
                                  ai.error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () {
                                  ai.clearError();
                                  _initialized = false;
                                  _loadExplanation();
                                },
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        );
                      }

                      // Auto-scroll when new messages arrive
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_scrollController.hasClients) {
                          _scrollController.animateTo(
                            _scrollController.position.maxScrollExtent,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        }
                      });

                      final hasEmptyAssistant =
                          ai.messages.isNotEmpty &&
                          ai.messages.last.role == 'assistant' &&
                          ai.messages.last.content.isEmpty;

                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount:
                            ai.messages.length +
                            (ai.isLoading && !hasEmptyAssistant ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= ai.messages.length) {
                            return _LoadingBubble(
                              text: ai.loadingText ?? '正在组织语言…',
                              onCancel: ai.cancelGeneration,
                            );
                          }
                          final msg = ai.messages[index];
                          final isUser = msg.role == 'user';
                          final isWaitingAssistant =
                              !isUser && msg.content.trim().isEmpty;
                          return Align(
                            alignment: isUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.8,
                              ),
                              decoration: BoxDecoration(
                                color: isUser
                                    ? primary.withAlpha(28)
                                    : Colors.white.withAlpha(112),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: isWaitingAssistant
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: primary,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            ai.loadingText ?? '小U正在阅读这一段…',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: palette.textSecondary,
                                              height: 1.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Text(
                                      msg.content,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: palette.textPrimary,
                                        height: 1.5,
                                      ),
                                    ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Consumer2<ReaderProvider, AiProvider>(
                  builder: (context, reader, ai, _) {
                    final book = reader.book;
                    final canPublish =
                        book != null &&
                        BookService.isMingtaiShelfBook(book) &&
                        !ai.isLoading &&
                        ai.error == null &&
                        ai.messages.any(
                          (message) =>
                              message.role == 'assistant' &&
                              message.content.trim().isNotEmpty,
                        );
                    if (!canPublish) return const SizedBox.shrink();
                    return Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: TextButton.icon(
                          onPressed: _publishing || _published
                              ? null
                              : _publishExplanation,
                          icon: Icon(
                            _published
                                ? Icons.check_circle_outline
                                : Icons.public_outlined,
                            size: 18,
                          ),
                          label: Text(
                            _published
                                ? '已公开到明台'
                                : _publishing
                                ? '公开中...'
                                : '公开到明台',
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // Follow-up input
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withAlpha(132),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _followUpController,
                          decoration: InputDecoration(
                            hintText: '继续追问...',
                            filled: true,
                            fillColor: Colors.white.withAlpha(105),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 14),
                          onSubmitted: (_) => _sendFollowUp(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Consumer<AiProvider>(
                        builder: (context, ai, _) {
                          return IconButton(
                            icon: Icon(
                              Icons.send_rounded,
                              color: ai.isLoading
                                  ? palette.textSecondary
                                  : primary,
                            ),
                            onPressed: ai.isLoading ? null : _sendFollowUp,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _followUpController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _LoadingBubble extends StatelessWidget {
  final String text;
  final VoidCallback onCancel;

  const _LoadingBubble({required this.text, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final primary = Theme.of(context).colorScheme.primary;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(112),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: primary),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }
}
