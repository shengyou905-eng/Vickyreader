import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/xiaou_chat_provider.dart';

class XiaouChatScreen extends StatefulWidget {
  const XiaouChatScreen({super.key});

  @override
  State<XiaouChatScreen> createState() => _XiaouChatScreenState();
}

class _XiaouChatScreenState extends State<XiaouChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final provider = context.read<XiaouChatProvider>();
    provider.addWelcomeMessage();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    context.read<XiaouChatProvider>().sendMessage(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('小U'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<XiaouChatProvider>(
        builder: (_, provider, __) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

          return Column(
            children: [
              Expanded(
                child: provider.messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: provider.messages.length,
                        itemBuilder: (_, i) => _buildBubble(provider.messages[i]),
                      ),
              ),
              if (provider.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    provider.error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              _buildInputBar(provider.isLoading),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 56, color: AppTheme.primaryLight),
          const SizedBox(height: 16),
          const Text('小U 阅读伙伴', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('基于你的阅读记录，随时和我聊聊',
              style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildBubble(ChatMessage msg) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.primary : AppTheme.primaryLight.withAlpha(25),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: isUser ? const Radius.circular(18) : const Radius.circular(6),
            bottomRight: isUser ? const Radius.circular(6) : const Radius.circular(18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.content.isEmpty ? '...' : msg.content,
              style: TextStyle(
                color: isUser ? Colors.white : AppTheme.textPrimary,
                fontSize: 15,
                height: 1.55,
              ),
            ),
            if (msg.isStreaming)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.primary.withAlpha(150),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(bool loading) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: AppTheme.dividerColor.withAlpha(80)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: '和小U聊聊你的阅读...',
                  filled: true,
                  fillColor: AppTheme.primaryLight.withAlpha(18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                maxLines: null,
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton.filled(
                      onPressed: _send,
                      icon: const Icon(Icons.send_rounded, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
