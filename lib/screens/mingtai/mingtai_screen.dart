import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/book_service.dart';

class MingtaiScreen extends StatefulWidget {
  const MingtaiScreen({super.key});

  @override
  State<MingtaiScreen> createState() => _MingtaiScreenState();
}

class _MingtaiScreenState extends State<MingtaiScreen> {
  List<MingtaiFeedItem> _items = [];
  final Set<String> _expandedIds = {};
  final Set<String> _quotingIds = {};
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final firstLoad = _items.isEmpty;
    setState(() {
      _loading = firstLoad;
      _refreshing = !firstLoad;
      _error = null;
    });

    try {
      final items = await BookService.getMingtaiFeed(limit: 50);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _quoteItem(MingtaiFeedItem item) async {
    if (_quotingIds.contains(item.id)) return;
    setState(() => _quotingIds.add(item.id));
    try {
      await BookService.quoteMingtaiItemToXiaou(item);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已引用到我的小U'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('引用失败：$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _quotingIds.remove(item.id));
    }
  }

  void _toggleContext(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  void _showResonanceHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('共鸣会在下一步开放：需要写一句真诚回应'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('明台'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_refreshing) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
                      children: [
                        const _MingtaiIntroCard(),
                        const SizedBox(height: 20),
                        if (_error != null)
                          _QuietError(message: _error!, onRetry: _load)
                        else if (_items.isEmpty)
                          const _QuietEmpty()
                        else ...[
                          const _SectionTitle(title: '书页流'),
                          const SizedBox(height: 10),
                          ..._items.map(
                            (item) => _FeedItemCard(
                              item: item,
                              expanded: _expandedIds.contains(item.id),
                              quoting: _quotingIds.contains(item.id),
                              onResonance: _showResonanceHint,
                              onQuote: () => _quoteItem(item),
                              onToggleContext: () => _toggleContext(item.id),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const _QuietHint(),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _MingtaiIntroCard extends StatelessWidget {
  const _MingtaiIntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFBF6), Color(0xFFF1ECFF)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withAlpha(180)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryDark.withAlpha(14),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '公共书斋',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 12),
          Text(
            '书页流不是社交 feed。\n这里只放公开的页边笔记。',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w700,
              height: 1.45,
            ),
          ),
          SizedBox(height: 14),
          Text(
            '没有热榜、关注流、推荐语。你看到的是书、原文，以及一条安静的批注。',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _FeedItemCard extends StatelessWidget {
  final MingtaiFeedItem item;
  final bool expanded;
  final bool quoting;
  final VoidCallback onResonance;
  final VoidCallback onQuote;
  final VoidCallback onToggleContext;

  const _FeedItemCard({
    required this.item,
    required this.expanded,
    required this.quoting,
    required this.onResonance,
    required this.onQuote,
    required this.onToggleContext,
  });

  @override
  Widget build(BuildContext context) {
    final contextBefore = item.metadata['contextBefore']?.toString() ?? '';
    final contextAfter = item.metadata['contextAfter']?.toString() ?? '';
    final annotation = item.annotationText.trim().isNotEmpty
        ? item.annotationText.trim()
        : _fallbackAnnotation(item.source);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(238),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.dividerColor.withAlpha(120)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BookCover(imageUrl: item.bookCover),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.bookTitle.isEmpty ? '未知书名' : '《${item.bookTitle}》',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.bookAuthor.isEmpty ? '未知作者' : item.bookAuthor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if (item.chapterTitle.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        item.chapterTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (expanded && contextBefore.isNotEmpty) ...[
            _ContextLine(text: contextBefore),
            const SizedBox(height: 8),
          ],
          Text(
            item.originalText,
            maxLines: expanded ? null : 4,
            overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              height: 1.7,
            ),
          ),
          if (expanded && contextAfter.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ContextLine(text: contextAfter),
          ],
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBF6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8DED3)),
            ),
            child: Text(
              annotation,
              maxLines: expanded ? null : 2,
              overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _QuietAction(
                icon: Icons.favorite_border,
                label: '共鸣',
                onTap: onResonance,
              ),
              _QuietAction(
                icon: Icons.add_link,
                label: quoting ? '引用中' : '引用到我的小U',
                onTap: quoting ? null : onQuote,
              ),
              _QuietAction(
                icon: expanded ? Icons.expand_less : Icons.notes_outlined,
                label: expanded ? '收起上下文' : '展开上下文',
                onTap: onToggleContext,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fallbackAnnotation(String source) {
    if (source == 'highlight') return '有人在这里划下了这句话。';
    if (source == 'ai_explanation') return '有人把这段交给 AI 解释过。';
    if (source == 'thought') return '有人在这里留下了一句想法。';
    return '有人在这里留下了一条页边笔记。';
  }
}

class _BookCover extends StatelessWidget {
  final String imageUrl;

  const _BookCover({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final canLoadNetwork =
        imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 48,
        height: 66,
        color: AppTheme.primaryLight.withAlpha(34),
        child: canLoadNetwork
            ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _BookCoverFallback(),
              )
            : const _BookCoverFallback(),
      ),
    );
  }
}

class _BookCoverFallback extends StatelessWidget {
  const _BookCoverFallback();

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.menu_book_outlined,
      color: AppTheme.primary,
      size: 22,
    );
  }
}

class _ContextLine extends StatelessWidget {
  final String text;

  const _ContextLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 13,
        height: 1.6,
      ),
    );
  }
}

class _QuietAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _QuietAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.primaryLight.withAlpha(20),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppTheme.primaryLight.withAlpha(55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppTheme.primaryDark),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.primaryDark,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuietEmpty extends StatelessWidget {
  const _QuietEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      alignment: Alignment.center,
      child: const Text(
        '明台还很安静。\n在小U里选择一条阅读记录，公开到明台后会出现在这里。',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 14,
          height: 1.7,
        ),
      ),
    );
  }
}

class _QuietError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _QuietError({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(235),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        children: [
          const Text(
            '明台暂时没有打开',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('再试一次')),
        ],
      ),
    );
  }
}

class _QuietHint extends StatelessWidget {
  const _QuietHint();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '明台只按公开时间安静排列，不做热榜、推荐语和用户主页。',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 12,
        height: 1.6,
      ),
    );
  }
}
