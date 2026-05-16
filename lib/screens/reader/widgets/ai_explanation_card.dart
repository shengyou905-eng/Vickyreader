import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../providers/reader_provider.dart';
import '../../../providers/ai_provider.dart';

class AiExplanationCard extends StatefulWidget {
  const AiExplanationCard({super.key});

  @override
  State<AiExplanationCard> createState() => _AiExplanationCardState();
}

class _AiExplanationCardState extends State<AiExplanationCard> {
  final TextEditingController _followUpController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _initialized = false;

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
    final chapter = reader.currentChapter;
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
    final text = _followUpController.text.trim();
    if (text.isEmpty) return;
    _followUpController.clear();
    context.read<AiProvider>().sendFollowUp(text);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.dividerColor),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'AI 解释',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    context.read<ReaderProvider>().clearSelection();
                    context.read<AiProvider>().clearMessages();
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
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          color: AppTheme.primary,
                        ),
                        SizedBox(height: 12),
                        Text(
                          '正在搜索解释...',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
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
                        Icon(Icons.error_outline,
                            size: 36, color: Colors.red.shade300),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            ai.error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppTheme.textSecondary),
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

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: ai.messages.length + (ai.isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= ai.messages.length) {
                      return const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final msg = ai.messages[index];
                    final isUser = msg.role == 'user';
                    return Align(
                      alignment:
                          isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.8,
                        ),
                        decoration: BoxDecoration(
                          color: isUser
                              ? AppTheme.primaryLight.withAlpha(25)
                              : AppTheme.background,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          msg.content,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.textPrimary,
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
          // Follow-up input
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppTheme.dividerColor),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _followUpController,
                    decoration: const InputDecoration(
                      hintText: '继续追问...',
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 14),
                    onSubmitted: (_) => _sendFollowUp(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send_rounded, color: AppTheme.primary),
                  onPressed: _sendFollowUp,
                ),
              ],
            ),
          ),
        ],
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
