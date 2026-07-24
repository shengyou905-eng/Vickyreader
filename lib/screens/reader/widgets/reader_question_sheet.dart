import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../models/ai_conversation.dart';
import '../../../services/ai_service.dart';
import '../../../utils/markdown_sanitizer.dart';

enum ReaderQuestionScope { selection, page, chapter }

extension ReaderQuestionScopeLabel on ReaderQuestionScope {
  String get apiValue => switch (this) {
    ReaderQuestionScope.selection => 'selection',
    ReaderQuestionScope.page => 'page',
    ReaderQuestionScope.chapter => 'chapter',
  };

  String get label => switch (this) {
    ReaderQuestionScope.selection => '所选文字',
    ReaderQuestionScope.page => '当前页',
    ReaderQuestionScope.chapter => '本章',
  };
}

class ReaderQuestionContext {
  final String bookTitle;
  final String bookAuthor;
  final String chapterTitle;
  final String selectedText;
  final String pageText;
  final String chapterText;
  final String contextBefore;
  final String contextAfter;

  const ReaderQuestionContext({
    required this.bookTitle,
    required this.bookAuthor,
    required this.chapterTitle,
    required this.selectedText,
    required this.pageText,
    required this.chapterText,
    required this.contextBefore,
    required this.contextAfter,
  });

  bool supports(ReaderQuestionScope scope) => switch (scope) {
    ReaderQuestionScope.selection => selectedText.trim().isNotEmpty,
    ReaderQuestionScope.page => pageText.trim().isNotEmpty,
    ReaderQuestionScope.chapter => chapterText.trim().isNotEmpty,
  };

  String previewFor(ReaderQuestionScope scope) => switch (scope) {
    ReaderQuestionScope.selection => selectedText,
    ReaderQuestionScope.page => pageText,
    ReaderQuestionScope.chapter => chapterText,
  };
}

class ReaderQuestionSheet extends StatefulWidget {
  final ReaderQuestionContext readerContext;
  final ReaderQuestionScope initialScope;
  final Future<String?> Function(
    String question,
    String answer,
    ReaderQuestionScope scope,
  )
  onSaveFirstAnswer;
  final Future<void> Function(String entryId, String question, String answer)
  onSaveFollowUp;

  const ReaderQuestionSheet({
    super.key,
    required this.readerContext,
    required this.initialScope,
    required this.onSaveFirstAnswer,
    required this.onSaveFollowUp,
  });

  @override
  State<ReaderQuestionSheet> createState() => _ReaderQuestionSheetState();
}

class _ReaderQuestionSheetState extends State<ReaderQuestionSheet> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<AiMessage> _messages = [];
  StreamSubscription<String>? _subscription;
  late ReaderQuestionScope _scope;
  bool _loading = false;
  bool _savingTurn = false;
  String? _error;
  String? _entryId;

  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _loading || _savingTurn) return;
    await _subscription?.cancel();
    final history = _messages
        .where((message) => message.content.trim().isNotEmpty)
        .toList(growable: false);
    final userMessage = AiMessage(
      role: 'user',
      content: question,
      timestamp: DateTime.now(),
    );
    final assistantTime = DateTime.now().add(const Duration(milliseconds: 1));
    setState(() {
      _controller.clear();
      _error = null;
      _loading = true;
      _messages.add(userMessage);
      _messages.add(
        AiMessage(role: 'assistant', content: '', timestamp: assistantTime),
      );
    });
    _scrollToBottom();

    final buffer = StringBuffer();
    _subscription =
        AiService.readerQuestionStream(
          message: question,
          scope: _scope.apiValue,
          selectedText: widget.readerContext.selectedText,
          pageText: widget.readerContext.pageText,
          chapterText: widget.readerContext.chapterText,
          contextBefore: widget.readerContext.contextBefore,
          contextAfter: widget.readerContext.contextAfter,
          bookTitle: widget.readerContext.bookTitle,
          bookAuthor: widget.readerContext.bookAuthor,
          chapterTitle: widget.readerContext.chapterTitle,
          conversationHistory: history,
        ).listen(
          (chunk) {
            if (!mounted) return;
            buffer.write(chunk);
            setState(() {
              _messages[_messages.length - 1] = AiMessage(
                role: 'assistant',
                content: stripMarkdownMarkers(buffer.toString()),
                timestamp: assistantTime,
              );
            });
            _scrollToBottom();
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _error = AiService.friendlyError(error);
              _removeEmptyAssistantTail();
            });
          },
          onDone: () {
            final answer = stripMarkdownMarkers(buffer.toString()).trim();
            if (answer.isEmpty) {
              if (!mounted) return;
              setState(() {
                _loading = false;
                _error = '小U暂时没有看清，可以换一种问法再试一次。';
                _removeEmptyAssistantTail();
              });
              return;
            }
            unawaited(_finishTurn(question, answer));
          },
          cancelOnError: true,
        );
  }

  Future<void> _finishTurn(String question, String answer) async {
    if (mounted) setState(() => _savingTurn = true);
    await _saveTurn(question, answer);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _savingTurn = false;
    });
  }

  Future<void> _saveTurn(String question, String answer) async {
    try {
      if (_entryId == null || _entryId!.isEmpty) {
        _entryId = await widget.onSaveFirstAnswer(question, answer, _scope);
      } else {
        await widget.onSaveFollowUp(_entryId!, question, answer);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '回答已经生成，但这次记录暂时没有同步成功。');
    }
  }

  Future<void> _cancel() async {
    await _subscription?.cancel();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _removeEmptyAssistantTail();
    });
  }

  void _removeEmptyAssistantTail() {
    if (_messages.isNotEmpty &&
        _messages.last.role == 'assistant' &&
        _messages.last.content.trim().isEmpty) {
      _messages.removeLast();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return FractionallySizedBox(
      heightFactor: 0.88,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: Material(
          color: palette.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const SizedBox(height: 9),
              Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.divider.withAlpha(150),
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
                            '问小U',
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.readerContext.chapterTitle.isEmpty
                                ? widget.readerContext.bookTitle
                                : '${widget.readerContext.bookTitle} · ${widget.readerContext.chapterTitle}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_loading)
                      TextButton(onPressed: _cancel, child: const Text('停止')),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _buildScopeSelector(palette),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
                  decoration: BoxDecoration(
                    color: palette.card.withAlpha(190),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.divider.withAlpha(100)),
                  ),
                  child: Text(
                    widget.readerContext
                        .previewFor(_scope)
                        .replaceAll(RegExp(r'\s+'), ' ')
                        .trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 34),
                          child: Text(
                            '可以问一个具体的问题。\n小U会把回答放回你眼前的文字里。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 13,
                              height: 1.7,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                        itemCount: _messages.length,
                        itemBuilder: (_, index) => _QuestionBubble(
                          message: _messages[index],
                          loading:
                              _loading &&
                              index == _messages.length - 1 &&
                              _messages[index].role == 'assistant' &&
                              _messages[index].content.trim().isEmpty,
                        ),
                      ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 7),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade400, fontSize: 12),
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          enabled: !_loading && !_savingTurn,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: '就眼前的文字问小U…',
                            filled: true,
                            fillColor: palette.card.withAlpha(235),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide(color: palette.divider),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide(color: palette.divider),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide(color: palette.primary),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: '发送',
                        onPressed: _loading || _savingTurn ? null : _send,
                        icon: const Icon(Icons.arrow_upward_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: palette.primary,
                          foregroundColor: palette.buttonForeground,
                          disabledBackgroundColor: palette.primaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScopeSelector(AppPalette palette) {
    final options = ReaderQuestionScope.values
        .where(widget.readerContext.supports)
        .toList(growable: false);
    return Row(
      children: options
          .map((scope) {
            final selected = scope == _scope;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: scope == options.last ? 0 : 7),
                child: ChoiceChip(
                  label: SizedBox(
                    width: double.infinity,
                    child: Text(scope.label, textAlign: TextAlign.center),
                  ),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: _messages.isNotEmpty
                      ? null
                      : (_) => setState(() => _scope = scope),
                  selectedColor: palette.primaryLight.withAlpha(105),
                  backgroundColor: palette.card.withAlpha(180),
                  side: BorderSide(
                    color: selected
                        ? palette.primary.withAlpha(100)
                        : palette.divider.withAlpha(90),
                  ),
                  labelStyle: TextStyle(
                    color: selected
                        ? palette.primaryDark
                        : palette.textSecondary,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _QuestionBubble extends StatelessWidget {
  final AiMessage message;
  final bool loading;

  const _QuestionBubble({required this.message, required this.loading});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.84,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: isUser
              ? palette.primaryLight.withAlpha(105)
              : palette.card.withAlpha(230),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.divider.withAlpha(80)),
        ),
        child: loading
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: palette.primary,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    '小U正在读这一段…',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              )
            : Text(
                stripMarkdownMarkers(message.content),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 14,
                  height: 1.65,
                ),
              ),
      ),
    );
  }
}
