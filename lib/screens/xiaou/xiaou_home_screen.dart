import 'dart:async';

import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/ai_conversation.dart';
import '../../services/ai_service.dart';
import '../../utils/ai_consent_gate.dart';
import '../../services/book_service.dart';
import 'book_traces_screen.dart';
import 'topic_screen.dart';
import 'widgets/xiaou_card.dart';
import 'widgets/xiaou_presence_orb.dart';
import 'widgets/xiaou_swipe_actions.dart';
import 'xiaou_entry_grouping.dart';
import '../../utils/markdown_sanitizer.dart';

class XiaouHomeScreen extends StatefulWidget {
  final int refreshSignal;
  final bool autoLoad;

  const XiaouHomeScreen({
    super.key,
    this.refreshSignal = 0,
    this.autoLoad = true,
  });

  @override
  State<XiaouHomeScreen> createState() => _XiaouHomeScreenState();
}

class _BookOption {
  final String key;
  final String title;

  const _BookOption({required this.key, required this.title});
}

class _XiaouHomeScreenState extends State<XiaouHomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _allItems = [];
  XiaouHomeInsight _homeInsight = XiaouHomeInsight.empty();
  bool _discoveryExpanded = false;
  bool _loading = false;
  bool _refreshing = true;
  bool _loadInFlight = false;
  bool _reloadAfterCurrent = false;
  bool _forceReloadAfterCurrent = false;
  DateTime? _lastLoadCompletedAt;
  int _presencePulseKey = 0;
  String _searchQuery = '';
  String _bookFilter = 'all';
  String _sourceFilter = 'all';
  bool _importantOnly = false;
  final Set<String> _deletingIds = {};
  final Set<String> _updatingImportanceIds = {};

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant XiaouHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshSignal != oldWidget.refreshSignal) {
      _load(forceRefresh: true);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (!forceRefresh && _recentlyLoadedWithContent()) {
      return;
    }
    if (_loadInFlight) {
      _reloadAfterCurrent = true;
      _forceReloadAfterCurrent = _forceReloadAfterCurrent || forceRefresh;
      return;
    }
    _loadInFlight = true;
    final memoryOverview = BookService.cachedMingtaiOverview();
    final memoryInsight = BookService.cachedXiaouHomeInsight();
    final restored = await Future.wait<Object?>([
      memoryOverview == null
          ? BookService.restoreCachedMingtaiOverview()
          : Future<MingtaiOverview?>.value(memoryOverview),
      memoryInsight == null
          ? BookService.restoreCachedXiaouHomeInsight()
          : Future<XiaouHomeInsight?>.value(memoryInsight),
    ]);
    final cached = restored[0] as MingtaiOverview?;
    final cachedHome = restored[1] as XiaouHomeInsight?;
    if (!mounted) {
      _loadInFlight = false;
      return;
    }
    final hasVisibleContent =
        cached != null ||
        cachedHome != null ||
        _items.isNotEmpty ||
        _allItems.isNotEmpty ||
        _homeInsight.refreshedAt != null ||
        _homeInsight.recentEntries.isNotEmpty ||
        _homeInsight.longTermTopics.isNotEmpty;
    setState(() {
      if (cached != null) {
        _items = cached.items;
        _allItems = cached.allItems;
      }
      if (cachedHome != null) {
        _homeInsight = cachedHome;
        _useInsightSnapshotIfNeeded(cachedHome);
      }
      _loading = !hasVisibleContent;
      _refreshing = hasVisibleContent;
    });

    final waiters = <Future<void>>[
      BookService.getXiaouHomeInsight(forceRefresh: forceRefresh)
          .then((insight) {
            if (!mounted) return;
            setState(() {
              if (_shouldPulseForNewInsight(_homeInsight, insight)) {
                _presencePulseKey++;
              }
              _homeInsight = insight;
              _useInsightSnapshotIfNeeded(insight);
            });
          })
          .catchError((_) {}),
      BookService.getMingtaiOverview(forceRefresh: forceRefresh)
          .then((overview) {
            if (!mounted) return;
            setState(() {
              _items = overview.items;
              _allItems = overview.allItems;
              _loading = false;
            });
          })
          .catchError((_) {}),
    ];

    try {
      await Future.wait(waiters);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    } finally {
      if (mounted) {
        _lastLoadCompletedAt = DateTime.now();
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
      _loadInFlight = false;
      if (_reloadAfterCurrent && mounted) {
        final nextForceRefresh = _forceReloadAfterCurrent;
        _reloadAfterCurrent = false;
        _forceReloadAfterCurrent = false;
        _load(forceRefresh: nextForceRefresh);
      }
    }
  }

  bool _recentlyLoadedWithContent() {
    final lastLoadedAt = _lastLoadCompletedAt;
    if (lastLoadedAt == null) return false;
    if (DateTime.now().difference(lastLoadedAt) > const Duration(seconds: 20)) {
      return false;
    }
    return _items.isNotEmpty ||
        _allItems.isNotEmpty ||
        _homeInsight.refreshedAt != null ||
        _homeInsight.recentEntries.isNotEmpty ||
        _homeInsight.longTermTopics.isNotEmpty;
  }

  void _useInsightSnapshotIfNeeded(XiaouHomeInsight insight) {
    if (_allItems.isNotEmpty) return;
    final snapshot = BookService.xiaouSnapshotItems(insight);
    if (snapshot.isEmpty) return;
    _items = snapshot;
    _allItems = snapshot;
  }

  bool _shouldPulseForNewInsight(
    XiaouHomeInsight previous,
    XiaouHomeInsight next,
  ) {
    final previousText = previous.activeDiscovery;
    final nextText = next.activeDiscovery;
    if (nextText.trim().isEmpty || previousText == nextText) return false;
    return true;
  }

  void _openTopic(String tag) {
    final sourceItems = _allItems.isNotEmpty ? _allItems : _items;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => XiaouTopicScreen(tag: tag, items: sourceItems),
      ),
    );
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty || _deletingIds.contains(id)) return;
    final source = item['source']?.toString() ?? '';
    var undone = false;
    setState(() {
      _deletingIds.add(id);
      _removeItemFromLists(id);
    });

    final controller = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除${_sourceLabel(source)}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            undone = true;
            if (!mounted) return;
            setState(() {
              _restoreItemToLists(item);
              _deletingIds.remove(id);
            });
          },
        ),
      ),
    );
    await controller.closed;
    if (undone) return;
    try {
      await BookService.deleteMingtaiItem(id);
      if (!mounted) return;
      setState(() => _deletingIds.remove(id));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _restoreItemToLists(item);
        _deletingIds.remove(id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _toggleImportance(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty || _updatingImportanceIds.contains(id)) return;
    final previous = _isImportant(item);
    final next = !previous;
    setState(() {
      _updatingImportanceIds.add(id);
      _setImportanceInLists(id, next);
    });
    try {
      await BookService.setMingtaiItemImportance(id, isImportant: next);
      if (!mounted) return;
      setState(() => _updatingImportanceIds.remove(id));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _setImportanceInLists(id, previous);
        _updatingImportanceIds.remove(id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('重要标记保存失败：$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _removeItemFromLists(String id) {
    _items.removeWhere((entry) => entry['id']?.toString() == id);
    if (!identical(_items, _allItems)) {
      _allItems.removeWhere((entry) => entry['id']?.toString() == id);
    }
  }

  void _restoreItemToLists(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    void restore(List<Map<String, dynamic>> list) {
      if (list.any((entry) => entry['id']?.toString() == id)) return;
      list.add(item);
      list.sort((a, b) => _itemDate(b).compareTo(_itemDate(a)));
    }

    restore(_items);
    if (!identical(_items, _allItems)) restore(_allItems);
  }

  void _setImportanceInLists(String id, bool value) {
    final seen = <Map<String, dynamic>>{};
    for (final item in [..._items, ..._allItems]) {
      if (!seen.add(item) || item['id']?.toString() != id) continue;
      item['is_important'] = value;
    }
  }

  void _openBookTraces(Map<String, dynamic> item) {
    final bookId = item['book_id']?.toString() ?? '';
    final bookTitle = item['book_title']?.toString().trim() ?? '';
    if (bookId.isEmpty && bookTitle.isEmpty) return;
    final sourceItems = _allItems.isNotEmpty ? _allItems : _items;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => XiaouBookTracesScreen(
              bookId: bookTitle.isEmpty ? bookId : '',
              bookTitle: bookTitle,
              initialItems: sourceItems,
            ),
          ),
        )
        .then((_) => _load(forceRefresh: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('小U'), centerTitle: true),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            Column(
              children: [
                if (_refreshing) const LinearProgressIndicator(minHeight: 2),
                Expanded(child: _buildContent()),
              ],
            ),
          Positioned(
            right: 36,
            bottom: 88 + MediaQuery.of(context).padding.bottom,
            child: RepaintBoundary(
              child: XiaouPresenceOrb(
                isThinking: false,
                pulseKey: _presencePulseKey,
                onTap: _showAgentChat,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAgentChat() async {
    if (!await AiConsentGate.ensure(context) || !mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _XiaouAgentChatSheet(),
    );
  }

  Widget _buildContent() {
    final visibleItems = _visibleItems();
    return RefreshIndicator(
      onRefresh: () => _load(forceRefresh: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          if (_homeInsight.hasActiveDiscovery) ...[
            SliverToBoxAdapter(
              child: _buildDiscoveryCard(_homeInsight.activeDiscovery),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 4)),
          ],
          SliverToBoxAdapter(child: _buildMemoryTools()),
          if (visibleItems.isEmpty)
            SliverToBoxAdapter(child: _buildFilteredEmpty())
          else ...[
            SliverList(
              delegate: SliverChildBuilderDelegate((_, i) {
                final item = visibleItems[i];
                final id = (item['id'] as String?) ?? '';
                final source = (item['source'] as String?) ?? '';
                return XiaouSwipeActions(
                  key: ValueKey(id),
                  isImportant: _isImportant(item),
                  onToggleImportant: _updatingImportanceIds.contains(id)
                      ? null
                      : () => _toggleImportance(item),
                  onDelete: _deletingIds.contains(id)
                      ? null
                      : () => _deleteItem(item),
                  child: XiaouCard(
                    entryId: (item['remote_entry_id'] as String?) ?? '',
                    source: source,
                    originalText: (item['original_text'] as String?) ?? '',
                    userNote: (item['user_note'] as String?) ?? '',
                    aiTags: (item['ai_tags'] as String?) ?? '',
                    aiUnderstanding:
                        (item['ai_understanding'] as String?) ?? '',
                    bookTitle: (item['book_title'] as String?) ?? '',
                    chapterIndex: item['chapter_index']?.toString() ?? '',
                    chapterTitle: (item['chapter_title'] as String?) ?? '',
                    createdAt: (item['created_at'] as String?) ?? '',
                    isImportant: _isImportant(item),
                    followUpCount:
                        int.tryParse(
                          item['follow_up_count']?.toString() ?? '',
                        ) ??
                        0,
                    latestFollowUpQuestion:
                        item['latest_follow_up_question']?.toString() ?? '',
                    onTagTap: _openTopic,
                    onBookTap: () => _openBookTraces(item),
                  ),
                );
              }, childCount: visibleItems.length),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 112)),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _visibleItems() {
    final sourceItems = _allItems.isNotEmpty ? _allItems : _items;
    final query = _searchQuery.trim().toLowerCase();
    return sourceItems.where((item) {
      final source = item['source']?.toString() ?? '';
      final sourceMatches = switch (_sourceFilter) {
        'thought' => source == 'thought' || source == 'manual',
        'highlight' => source == 'highlight',
        'ai_explanation' => source == 'ai_explanation',
        _ => true,
      };
      if (!sourceMatches) return false;
      if (_importantOnly && !_isImportant(item)) return false;
      if (_bookFilter != 'all' && xiaouBookGroupKey(item) != _bookFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      final searchable = [
        item['original_text'],
        item['user_note'],
        item['ai_understanding'],
        item['book_title'],
        item['chapter_title'],
        item['ai_tags'],
      ].map((value) => value?.toString() ?? '').join('\n').toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  Widget _buildMemoryTools() {
    final palette = context.appPalette;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final bookMenuHeight = (viewportHeight * 0.42).clamp(240.0, 380.0);
    final bookOptions = _bookOptions();
    final selectedBook = bookOptions.firstWhere(
      (option) => option.key == _bookFilter,
      orElse: () => const _BookOption(key: 'all', title: '全部书籍'),
    );
    const filters = <(String, String)>[
      ('all', '全部'),
      ('thought', '想法'),
      ('highlight', '划线'),
      ('ai_explanation', '小U解读'),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        _homeInsight.hasActiveDiscovery ? 6 : 16,
        16,
        10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '阅读痕迹',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '找一句话、一本书或一个想法',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      icon: const Icon(Icons.close, size: 18),
                    ),
              filled: true,
              fillColor: palette.card.withAlpha(220),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: palette.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: palette.divider.withAlpha(120)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          PopupMenuButton<String>(
            tooltip: '按书籍筛选',
            initialValue: _bookFilter,
            position: PopupMenuPosition.under,
            constraints: BoxConstraints(maxHeight: bookMenuHeight),
            onSelected: (value) => setState(() => _bookFilter = value),
            itemBuilder: (_) => bookOptions
                .map(
                  (option) => PopupMenuItem<String>(
                    value: option.key,
                    child: Text(
                      option.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: palette.card.withAlpha(180),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: palette.divider.withAlpha(105)),
              ),
              child: Row(
                children: [
                  Icon(Icons.menu_book_outlined, size: 18, color: palette.icon),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      selectedBook.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(Icons.expand_more_rounded, color: palette.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
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
                    onSelected: (_) =>
                        setState(() => _sourceFilter = filter.$1),
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
          ),
          const SizedBox(height: 6),
          FilterChip(
            avatar: Icon(
              _importantOnly ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 17,
              color: _importantOnly
                  ? palette.primaryDark
                  : palette.textSecondary,
            ),
            label: const Text('仅看重要'),
            selected: _importantOnly,
            showCheckmark: false,
            onSelected: (value) => setState(() => _importantOnly = value),
            backgroundColor: palette.card.withAlpha(180),
            selectedColor: palette.primaryLight.withAlpha(105),
            side: BorderSide(
              color: _importantOnly
                  ? palette.primary.withAlpha(90)
                  : palette.divider.withAlpha(100),
            ),
          ),
        ],
      ),
    );
  }

  List<_BookOption> _bookOptions() {
    final sourceItems = _allItems.isNotEmpty ? _allItems : _items;
    final result = <_BookOption>[const _BookOption(key: 'all', title: '全部书籍')];
    final seen = <String>{'all'};
    for (final item in sourceItems) {
      final key = xiaouBookGroupKey(item);
      final title = item['book_title']?.toString().trim() ?? '';
      if (key == 'book:unknown' || title.isEmpty || !seen.add(key)) continue;
      result.add(_BookOption(key: key, title: title));
    }
    return result;
  }

  bool _isImportant(Map<String, dynamic> item) {
    final value = item['is_important'];
    return value == true || value == 1 || value?.toString() == '1';
  }

  DateTime _itemDate(Map<String, dynamic> item) {
    return DateTime.tryParse(item['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _sourceLabel(String source) {
    return switch (source) {
      'ai_explanation' => '小U解读',
      'thought' || 'manual' => '想法',
      'highlight' => '原始划线',
      _ => '阅读痕迹',
    };
  }

  Widget _buildFilteredEmpty() {
    final palette = context.appPalette;
    final hasAnyItems = (_allItems.isNotEmpty ? _allItems : _items).isNotEmpty;
    return SizedBox(
      height: 230,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Text(
            hasAnyItems ? '这里暂时没有找到对应的阅读痕迹。' : '划线、想法和小U解读会被安静地记在这里。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiscoveryCard(String discovery) {
    final palette = context.appPalette;
    final body = _cleanDiscoveryBody(discovery);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.card, palette.primaryLight.withAlpha(112)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.surface.withAlpha(190)),
        boxShadow: [
          BoxShadow(
            color: palette.primaryDark.withAlpha(18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: palette.icon, size: 18),
              const SizedBox(width: 8),
              Text(
                '小U发现了一件事',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            body,
            maxLines: _discoveryExpanded ? null : 7,
            overflow: _discoveryExpanded
                ? TextOverflow.visible
                : TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.55,
            ),
          ),
          if (_shouldShowDiscoveryToggle(body)) ...[
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: palette.primaryDark,
              ),
              onPressed: () {
                setState(() => _discoveryExpanded = !_discoveryExpanded);
              },
              child: Text(_discoveryExpanded ? '收起' : '展开'),
            ),
          ],
        ],
      ),
    );
  }

  String _cleanDiscoveryBody(String text) {
    return text.replaceFirst(RegExp(r'^✦\s*小U发现了一件事\s*'), '').trim();
  }

  bool _shouldShowDiscoveryToggle(String text) {
    return text.trim().length > 90 || text.trim().split('\n').length > 3;
  }
}

class _XiaouAgentChatSheet extends StatefulWidget {
  const _XiaouAgentChatSheet();

  @override
  State<_XiaouAgentChatSheet> createState() => _XiaouAgentChatSheetState();
}

class _XiaouAgentChatSheetState extends State<_XiaouAgentChatSheet> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<AiMessage> _messages = [];
  StreamSubscription<String>? _subscription;
  bool _loading = false;
  String? _error;

  static const List<String> _suggestions = [
    '为什么这句话让我停下来？',
    '这几本书之间有没有联系？',
    '你最近发现了什么？',
  ];

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _loading) return;
    await _subscription?.cancel();
    final history = _messages
        .where((m) => m.content.trim().isNotEmpty)
        .toList();
    final userMessage = AiMessage(
      role: 'user',
      content: text,
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
        AiService.xiaouAgentStream(
          message: text,
          conversationHistory: history,
        ).listen(
          (chunk) {
            if (!mounted) return;
            buffer.write(chunk);
            setState(() {
              _messages[_messages.length - 1] = AiMessage(
                role: 'assistant',
                content: buffer.toString(),
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
            if (!mounted) return;
            setState(() {
              _loading = false;
              if (buffer.isEmpty) {
                _error = '小U暂时还没有看清，可以换一种问法再试一次。';
                _removeEmptyAssistantTail();
              }
            });
          },
          cancelOnError: true,
        );
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
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Material(
          color: palette.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.divider.withAlpha(160),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '和小U说话',
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '直接问。小U会尽量把问题放回你的阅读里。',
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
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _messages.isEmpty
                    ? _buildEmptyState(palette)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          return _XiaouAgentBubble(
                            message: _messages[index],
                            loading:
                                _loading &&
                                index == _messages.length - 1 &&
                                _messages[index].role == 'assistant' &&
                                _messages[index].content.trim().isEmpty,
                          );
                        },
                      ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
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
                          enabled: !_loading,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: '直接问小U…',
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
                        onPressed: _loading ? null : () => _send(),
                        icon: const Icon(Icons.arrow_upward_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: palette.primary,
                          foregroundColor: palette.buttonForeground,
                          disabledBackgroundColor: palette.primaryLight,
                          disabledForegroundColor: palette.textSecondary,
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

  Widget _buildEmptyState(AppPalette palette) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
      children: [
        Text(
          '你可以直接问小U。',
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 17,
            height: 1.55,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '它会参考你的划线、想法、小U解读、主动授权的随心记，以及明台公开痕迹。看不清的时候，它会说不确定；不会再要求你使用固定问题。',
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 13,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          '一些问法，不是固定问题',
          style: TextStyle(
            color: palette.textSecondary.withAlpha(180),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        ..._suggestions.map(
          (text) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              text,
              style: TextStyle(
                color: palette.textSecondary.withAlpha(165),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _XiaouAgentBubble extends StatelessWidget {
  final AiMessage message;
  final bool loading;

  const _XiaouAgentBubble({required this.message, required this.loading});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isUser
              ? palette.primary.withAlpha(34)
              : palette.card.withAlpha(230),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isUser
                ? palette.primary.withAlpha(42)
                : palette.divider.withAlpha(160),
          ),
        ),
        child: loading
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '小U正在回看你的阅读痕迹…',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isUser
                        ? message.content
                        : stripMarkdownMarkers(message.content),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      height: 1.62,
                    ),
                  ),
                  if (!isUser && message.content.trim().isNotEmpty)
                    const AiGeneratedNotice(compact: true),
                ],
              ),
      ),
    );
  }
}
