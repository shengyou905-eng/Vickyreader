import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../services/book_service.dart';
import 'xiaou_entry_grouping.dart';
import 'widgets/xiaou_card.dart';
import 'widgets/xiaou_swipe_actions.dart';

class XiaouBookTracesScreen extends StatefulWidget {
  final String bookId;
  final String bookTitle;
  final List<Map<String, dynamic>> initialItems;

  const XiaouBookTracesScreen({
    super.key,
    required this.bookId,
    required this.bookTitle,
    required this.initialItems,
  });

  @override
  State<XiaouBookTracesScreen> createState() => _XiaouBookTracesScreenState();
}

class _XiaouBookTracesScreenState extends State<XiaouBookTracesScreen> {
  late List<Map<String, dynamic>> _items;
  String _sourceFilter = 'all';
  bool _refreshing = false;
  final Set<String> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _items = _itemsForBook(widget.initialItems);
  }

  List<Map<String, dynamic>> _itemsForBook(List<Map<String, dynamic>> source) {
    return source
        .where(
          (item) => xiaouEntryBelongsToBook(
            item,
            bookId: widget.bookId,
            bookTitle: widget.bookTitle,
          ),
        )
        .toList();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final overview = await BookService.getMingtaiOverview(forceRefresh: true);
      if (!mounted) return;
      setState(() => _items = _itemsForBook(overview.allItems));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  List<Map<String, dynamic>> get _visibleItems {
    return _items.where((item) {
      final source = item['source']?.toString() ?? '';
      return switch (_sourceFilter) {
        'thought' => source == 'thought' || source == 'manual',
        'highlight' => source == 'highlight',
        'ai_explanation' => source == 'ai_explanation',
        _ => true,
      };
    }).toList();
  }

  Future<void> _toggleImportance(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty || _busyIds.contains(id)) return;
    final previous = _isImportant(item);
    setState(() {
      _busyIds.add(id);
      item['is_important'] = !previous;
    });
    try {
      await BookService.setMingtaiItemImportance(id, isImportant: !previous);
      if (mounted) setState(() => _busyIds.remove(id));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        item['is_important'] = previous;
        _busyIds.remove(id);
      });
      _showMessage('重要标记保存失败：$e');
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty || _busyIds.contains(id)) return;
    final index = _items.indexOf(item);
    var undone = false;
    setState(() {
      _busyIds.add(id);
      _items.remove(item);
    });
    final controller = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除${_sourceLabel(item['source']?.toString() ?? '')}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            undone = true;
            if (!mounted) return;
            setState(() {
              _items.insert(index.clamp(0, _items.length), item);
              _busyIds.remove(id);
            });
          },
        ),
      ),
    );
    await controller.closed;
    if (undone) return;
    try {
      await BookService.deleteMingtaiItem(id);
      if (mounted) setState(() => _busyIds.remove(id));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items.insert(index.clamp(0, _items.length), item);
        _busyIds.remove(id);
      });
      _showMessage('删除失败：$e');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final visibleItems = _visibleItems;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.bookTitle.isEmpty ? '这本书的阅读痕迹' : widget.bookTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_items.length} 条属于你的阅读痕迹',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildTypeFilters(),
                  ],
                ),
              ),
            ),
            if (visibleItems.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    '这里暂时没有对应的阅读痕迹。',
                    style: TextStyle(color: palette.textSecondary),
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: visibleItems.length,
                itemBuilder: (_, index) {
                  final item = visibleItems[index];
                  final id = item['id']?.toString() ?? '';
                  return XiaouSwipeActions(
                    key: ValueKey(id),
                    isImportant: _isImportant(item),
                    onToggleImportant: _busyIds.contains(id)
                        ? null
                        : () => _toggleImportance(item),
                    onDelete: _busyIds.contains(id)
                        ? null
                        : () => _deleteItem(item),
                    child: XiaouCard(
                      entryId: item['remote_entry_id']?.toString() ?? '',
                      source: item['source']?.toString() ?? '',
                      originalText: item['original_text']?.toString() ?? '',
                      userNote: item['user_note']?.toString() ?? '',
                      aiTags: item['ai_tags']?.toString() ?? '',
                      aiUnderstanding:
                          item['ai_understanding']?.toString() ?? '',
                      bookTitle: item['book_title']?.toString() ?? '',
                      chapterIndex: item['chapter_index']?.toString() ?? '',
                      chapterTitle: item['chapter_title']?.toString() ?? '',
                      createdAt: item['created_at']?.toString() ?? '',
                      isImportant: _isImportant(item),
                      followUpCount:
                          int.tryParse(
                            item['follow_up_count']?.toString() ?? '',
                          ) ??
                          0,
                      latestFollowUpQuestion:
                          item['latest_follow_up_question']?.toString() ?? '',
                    ),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 36)),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeFilters() {
    final palette = context.appPalette;
    const filters = <(String, String)>[
      ('all', '全部'),
      ('thought', '想法'),
      ('highlight', '划线'),
      ('ai_explanation', '小U解读'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((filter) {
          final selected = _sourceFilter == filter.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(filter.$2),
              selected: selected,
              showCheckmark: false,
              onSelected: (_) => setState(() => _sourceFilter = filter.$1),
              backgroundColor: palette.card.withAlpha(180),
              selectedColor: palette.primaryLight.withAlpha(105),
              side: BorderSide(
                color: selected
                    ? palette.primary.withAlpha(90)
                    : palette.divider.withAlpha(100),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  bool _isImportant(Map<String, dynamic> item) {
    final value = item['is_important'];
    return value == true || value == 1 || value?.toString() == '1';
  }

  String _sourceLabel(String source) {
    return switch (source) {
      'ai_explanation' => '小U解读',
      'thought' || 'manual' => '想法',
      'highlight' => '原始划线',
      _ => '阅读痕迹',
    };
  }
}
