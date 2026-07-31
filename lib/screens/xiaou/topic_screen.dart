import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/book_service.dart';
import '../../widgets/app_paper_surface.dart';

class XiaouTopicScreen extends StatelessWidget {
  final String tag;
  final List<Map<String, dynamic>> items;

  const XiaouTopicScreen({super.key, required this.tag, required this.items});

  @override
  Widget build(BuildContext context) {
    final visuals = context.appVisuals;
    final topicItems = _topicItems();
    final groups = _groupByBook(topicItems);
    final recentAt = topicItems.isEmpty
        ? null
        : BookService.mingtaiItemCreatedAt(topicItems.first);

    return Scaffold(
      appBar: AppBar(title: const Text('主题')),
      body: AppPaperSurface(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            visuals.pagePadding,
            12,
            visuals.pagePadding,
            32,
          ),
          children: [
            _TopicHeader(
              tag: tag,
              count: topicItems.length,
              recentAt: recentAt,
            ),
            SizedBox(height: visuals.sectionSpacing),
            if (topicItems.isEmpty)
              const _TopicEmpty()
            else
              ...groups.map((group) => _BookEntryGroup(group: group)),
            const SizedBox(height: 4),
            _TopicSummary(tag: tag, items: topicItems),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _topicItems() {
    final result = items.where((item) {
      return BookService.mingtaiItemTags(item).contains(tag);
    }).toList();
    result.sort((a, b) {
      final aDate = BookService.mingtaiItemCreatedAt(a);
      final bDate = BookService.mingtaiItemCreatedAt(b);
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return result;
  }

  List<_BookGroup> _groupByBook(List<Map<String, dynamic>> topicItems) {
    final byBook = <String, List<Map<String, dynamic>>>{};
    for (final item in topicItems) {
      final title = ((item['book_title'] as String?) ?? '').trim();
      final key = title.isEmpty ? '未命名书籍' : title;
      byBook.putIfAbsent(key, () => []).add(item);
    }

    final groups = byBook.entries.map((entry) {
      final entries = entry.value;
      entries.sort((a, b) {
        final aDate = BookService.mingtaiItemCreatedAt(a);
        final bDate = BookService.mingtaiItemCreatedAt(b);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });
      return _BookGroup(bookTitle: entry.key, items: entries);
    }).toList();

    groups.sort((a, b) {
      final aDate = a.latestAt;
      final bDate = b.latestAt;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return groups;
  }
}

class _TopicHeader extends StatelessWidget {
  final String tag;
  final int count;
  final DateTime? recentAt;

  const _TopicHeader({
    required this.tag,
    required this.count,
    required this.recentAt,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final visuals = context.appVisuals;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        visuals.cardPadding + 4,
        20,
        visuals.cardPadding + 4,
        22,
      ),
      decoration: BoxDecoration(
        color: palette.primarySoft.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(visuals.cardRadius),
        border: Border.all(color: palette.primary.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '回望',
            style: TextStyle(
              color: palette.primaryDeep,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            tag,
            style: TextStyle(
              color: visuals.ink,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$count 条摘录 · 最近记录 ${_formatDate(recentAt)}',
            style: TextStyle(color: visuals.inkMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _BookEntryGroup extends StatelessWidget {
  final _BookGroup group;

  const _BookEntryGroup({required this.group});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final visuals = context.appVisuals;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.fromLTRB(
        visuals.cardPadding,
        15,
        visuals.cardPadding,
        8,
      ),
      decoration: BoxDecoration(
        color: visuals.surface,
        borderRadius: BorderRadius.circular(visuals.cardRadius),
        border: Border.all(color: visuals.divider.withValues(alpha: 0.72)),
        boxShadow: visuals.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_outlined, size: 16, color: palette.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  group.bookTitle,
                  style: TextStyle(
                    color: visuals.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${group.items.length} 条',
                style: TextStyle(color: visuals.inkMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...group.items.map((item) => _TopicEntryTile(item: item)),
        ],
      ),
    );
  }
}

class _TopicEntryTile extends StatelessWidget {
  final Map<String, dynamic> item;

  const _TopicEntryTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final visuals = context.appVisuals;
    final originalText = (item['original_text'] as String?)?.trim() ?? '';
    final userNote = (item['user_note'] as String?)?.trim() ?? '';
    final createdAt = BookService.mingtaiItemCreatedAt(item);

    return Container(
      padding: const EdgeInsets.only(left: 12, bottom: 14),
      margin: const EdgeInsets.only(left: 3),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: palette.primary.withValues(alpha: 0.24),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatDate(createdAt),
            style: TextStyle(color: visuals.inkMuted, fontSize: 11),
          ),
          const SizedBox(height: 7),
          if (originalText.isNotEmpty)
            Text(
              originalText,
              style: TextStyle(
                color: visuals.ink,
                fontSize: 14,
                height: 1.55,
                fontStyle: FontStyle.italic,
              ),
            ),
          if (userNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              userNote,
              style: TextStyle(
                color: visuals.inkMuted,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TopicSummary extends StatelessWidget {
  final String tag;
  final List<Map<String, dynamic>> items;

  const _TopicSummary({required this.tag, required this.items});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final visuals = context.appVisuals;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: EdgeInsets.all(visuals.cardPadding),
      decoration: BoxDecoration(
        color: visuals.surfaceSoft,
        borderRadius: BorderRadius.circular(visuals.cardRadius),
        border: Border(left: BorderSide(color: palette.primary, width: 2)),
      ),
      child: Text(
        _summaryText(),
        style: TextStyle(color: visuals.inkMuted, fontSize: 13, height: 1.55),
      ),
    );
  }

  String _summaryText() {
    final related = <String, int>{};
    final books = <String, int>{};
    for (final item in items) {
      for (final itemTag in BookService.mingtaiItemTags(item)) {
        if (itemTag == tag || !BookService.isMingtaiTopicTag(itemTag)) continue;
        related[itemTag] = (related[itemTag] ?? 0) + 1;
      }
      final bookTitle = ((item['book_title'] as String?) ?? '').trim();
      if (bookTitle.isNotEmpty) {
        books[bookTitle] = (books[bookTitle] ?? 0) + 1;
      }
    }

    final topRelated = _topKeys(related, 3);
    if (topRelated.isNotEmpty) {
      return '小U轻轻看了一眼：你常在这个主题下关注：${topRelated.join('、')}。';
    }

    final topBooks = _topKeys(books, 2);
    if (topBooks.isNotEmpty) {
      return '小U轻轻看了一眼：你常在这个主题下回到：${topBooks.map((b) => '《$b》').join('、')}。';
    }

    return '小U轻轻看了一眼：这个主题还很安静，更多摘录会慢慢显出线索。';
  }
}

class _TopicEmpty extends StatelessWidget {
  const _TopicEmpty();

  @override
  Widget build(BuildContext context) {
    final visuals = context.appVisuals;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Center(
        child: Text('这个主题下还没有条目', style: TextStyle(color: visuals.inkMuted)),
      ),
    );
  }
}

class _BookGroup {
  final String bookTitle;
  final List<Map<String, dynamic>> items;

  const _BookGroup({required this.bookTitle, required this.items});

  DateTime? get latestAt {
    if (items.isEmpty) return null;
    return BookService.mingtaiItemCreatedAt(items.first);
  }
}

List<String> _topKeys(Map<String, int> counts, int limit) {
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final countCompare = b.value.compareTo(a.value);
      if (countCompare != 0) return countCompare;
      return a.key.compareTo(b.key);
    });
  return entries.take(limit).map((entry) => entry.key).toList();
}

String _formatDate(DateTime? date) {
  if (date == null) return '暂无';
  final local = date.toLocal();
  return '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
}
