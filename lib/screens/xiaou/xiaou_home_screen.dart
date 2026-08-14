import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../config/theme.dart';
import '../../l10n/l10n.dart';
import '../../models/ai_conversation.dart';
import '../../models/user_entry.dart';
import '../../models/xiaou_conversation.dart';
import '../../services/ai_service.dart';
import '../../services/first_use_guide_service.dart';
import '../../services/xiaou_conversation_service.dart';
import '../../utils/ai_consent_gate.dart';
import '../../services/book_service.dart';
import '../../widgets/first_use_guides.dart';
import 'book_traces_screen.dart';
import 'topic_screen.dart';
import 'widgets/xiaou_card.dart';
import 'widgets/xiaou_presence_orb.dart';
import 'widgets/xiaou_swipe_actions.dart';
import 'xiaou_entry_grouping.dart';
import '../../utils/markdown_sanitizer.dart';
import '../../utils/latest_request_guard.dart';

class XiaouHomeScreen extends StatefulWidget {
  final int refreshSignal;
  final bool autoLoad;
  final bool isActive;

  const XiaouHomeScreen({
    super.key,
    this.refreshSignal = 0,
    this.autoLoad = true,
    this.isActive = true,
  });

  @override
  State<XiaouHomeScreen> createState() => _XiaouHomeScreenState();
}

class _BookOption {
  final String key;
  final String title;

  const _BookOption({required this.key, required this.title});
}

class _XiaouLoadNotice extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _XiaouLoadNotice({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: palette.card.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.divider.withValues(alpha: 0.65)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: palette.icon),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
        ],
      ),
    );
  }
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
  String? _loadError;
  bool _hasResolvedLoad = false;
  final LatestRequestGuard _loadGuard = LatestRequestGuard();
  int _presencePulseKey = 0;
  String _searchQuery = '';
  String _bookFilter = 'all';
  String _sourceFilter = 'all';
  bool _importantOnly = false;
  final Set<String> _deletingIds = {};
  final Set<String> _updatingImportanceIds = {};
  bool _showPresenceGuide = false;
  Timer? _presenceGuidePulseTimer;

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      _load();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeShowPresenceGuide());
    });
  }

  @override
  void didUpdateWidget(covariant XiaouHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshSignal != oldWidget.refreshSignal) {
      _load(forceRefresh: true);
    }
    if (widget.isActive && !oldWidget.isActive) {
      unawaited(_maybeShowPresenceGuide());
    }
  }

  @override
  void dispose() {
    _loadGuard.invalidate();
    _presenceGuidePulseTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _maybeShowPresenceGuide() async {
    final shouldShow = await FirstUseGuideService.claim(
      FirstUseGuide.xiaouPresence,
    );
    if (!mounted || !shouldShow) return;
    setState(() {
      _showPresenceGuide = true;
      _presencePulseKey++;
    });
    _presenceGuidePulseTimer?.cancel();
    _presenceGuidePulseTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted || !_showPresenceGuide) return;
      setState(() => _presencePulseKey++);
    });
  }

  Future<void> _dismissPresenceGuide() async {
    await FirstUseGuideService.complete(FirstUseGuide.xiaouPresence);
    if (!mounted) return;
    setState(() => _showPresenceGuide = false);
  }

  Future<void> _openPresenceGuide() async {
    await FirstUseGuideService.complete(FirstUseGuide.xiaouPresence);
    if (!mounted) return;
    setState(() => _showPresenceGuide = false);
    await _showAgentChat();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (!forceRefresh && _recentlyLoadedWithContent()) {
      return;
    }
    if (_loadInFlight) {
      _loadGuard.invalidate();
      _reloadAfterCurrent = true;
      _forceReloadAfterCurrent = _forceReloadAfterCurrent || forceRefresh;
      return;
    }
    _loadInFlight = true;
    final requestVersion = _loadGuard.begin();
    debugPrint(
      '[XiaouLoad] start version=$requestVersion force=$forceRefresh '
      'visible=${_allItems.length}',
    );
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
    if (!mounted || !_loadGuard.isCurrent(requestVersion)) {
      debugPrint('[XiaouLoad] stale cache ignored version=$requestVersion');
      _loadInFlight = false;
      _runQueuedLoadIfNeeded();
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
      _loadError = null;
    });

    final errors = <Object>[];
    final refreshNetwork = forceRefresh || cached != null || cachedHome != null;

    Future<void> loadInsight() async {
      try {
        final insight = await BookService.getXiaouHomeInsight(
          forceRefresh: refreshNetwork,
          fallbackToCacheOnError: false,
        );
        if (!mounted || !_loadGuard.isCurrent(requestVersion)) {
          debugPrint(
            '[XiaouLoad] stale insight ignored version=$requestVersion',
          );
          return;
        }
        setState(() {
          if (_shouldPulseForNewInsight(_homeInsight, insight)) {
            _presencePulseKey++;
          }
          _homeInsight = insight;
          _useInsightSnapshotIfNeeded(insight);
        });
      } catch (error) {
        errors.add(error);
        debugPrint(
          '[XiaouLoad] insight failed version=$requestVersion: $error',
        );
      }
    }

    Future<void> loadEntries() async {
      try {
        final overview = await BookService.getMingtaiOverview(
          forceRefresh: refreshNetwork,
          fallbackToCacheOnError: false,
        );
        if (!mounted || !_loadGuard.isCurrent(requestVersion)) {
          debugPrint(
            '[XiaouLoad] stale entries ignored version=$requestVersion',
          );
          return;
        }
        setState(() {
          _items = overview.items;
          _allItems = overview.allItems;
          _loading = false;
        });
        debugPrint(
          '[XiaouLoad] server snapshot version=$requestVersion '
          'items=${overview.allItems.length} '
          'empty=${overview.allItems.isEmpty}',
        );
      } catch (error) {
        errors.add(error);
        debugPrint(
          '[XiaouLoad] entries failed version=$requestVersion: $error',
        );
      }
    }

    try {
      await Future.wait([loadInsight(), loadEntries()]);
    } finally {
      if (mounted && _loadGuard.isCurrent(requestVersion)) {
        _lastLoadCompletedAt = DateTime.now();
        setState(() {
          _loading = false;
          _refreshing = false;
          _hasResolvedLoad = true;
          _loadError = errors.isEmpty ? null : _friendlyLoadError(errors.first);
        });
        debugPrint(
          '[XiaouLoad] complete version=$requestVersion '
          'error=${errors.isNotEmpty} retained=${_allItems.length}',
        );
      }
      _loadInFlight = false;
      _runQueuedLoadIfNeeded();
    }
  }

  void _runQueuedLoadIfNeeded() {
    if (!_reloadAfterCurrent || !mounted) return;
    final nextForceRefresh = _forceReloadAfterCurrent;
    _reloadAfterCurrent = false;
    _forceReloadAfterCurrent = false;
    unawaited(_load(forceRefresh: nextForceRefresh));
  }

  String _friendlyLoadError(Object error) {
    final message = error.toString().replaceFirst(
      RegExp(r'^Exception:\s*'),
      '',
    );
    if (message.contains('Timeout') || message.contains('timeout')) {
      return context.l10n.xiaouLoadRetained;
    }
    return context.l10n.xiaouLoadRetained;
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
        content: Text(
          context.l10n.deletedEntry(_localizedSourceLabel(context, source)),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: context.l10n.undo,
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
        SnackBar(
          content: Text(context.l10n.deleteFailed(e.toString())),
          behavior: SnackBarBehavior.floating,
        ),
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
          content: Text(context.l10n.importanceSaveFailed(e.toString())),
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
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: Text(context.l10n.xiaouTitle), centerTitle: true),
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
          if (_showPresenceGuide)
            XiaouPresenceGuide(
              onOpen: _openPresenceGuide,
              onDismiss: _dismissPresenceGuide,
            ),
          Positioned(
            right: 36,
            bottom: 88 + MediaQuery.viewPaddingOf(context).bottom,
            child: RepaintBoundary(
              child: XiaouPresenceOrb(
                isThinking: _showPresenceGuide,
                pulseKey: _presencePulseKey,
                onTap: _showPresenceGuide ? _openPresenceGuide : _showAgentChat,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAgentChat() async {
    if (!await AiConsentGate.ensure(context) || !mounted) return;
    final contextItem = _allItems.cast<Map<String, dynamic>?>().firstWhere(
      (item) => (item?['book_id']?.toString().trim() ?? '').isNotEmpty,
      orElse: () => null,
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _XiaouAgentChatSheet(
        contextBookId: contextItem?['book_id']?.toString() ?? '',
        contextBookTitle: contextItem?['book_title']?.toString() ?? '',
      ),
    );
  }

  Widget _buildContent() {
    final visibleItems = _visibleItems();
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
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
          if (_loadError != null)
            SliverToBoxAdapter(
              child: _XiaouLoadNotice(
                message: _loadError!,
                onRetry: () => _load(forceRefresh: true),
              ),
            ),
          SliverToBoxAdapter(child: _buildMemoryTools()),
          if (visibleItems.isEmpty)
            SliverToBoxAdapter(
              child: _buildFilteredEmpty(loadFailed: _loadError != null),
            )
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
          SliverToBoxAdapter(
            child: SizedBox(
              key: const ValueKey('xiaou-scroll-bottom-inset'),
              height: 112 + keyboardInset,
            ),
          ),
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
        'ai_question' => source == 'ai_question',
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
      orElse: () => _BookOption(key: 'all', title: context.l10n.allBooks),
    );
    final filters = <(String, String)>[
      ('all', context.l10n.all),
      ('thought', context.l10n.thoughts),
      ('highlight', context.l10n.highlights),
      ('ai_explanation', context.l10n.xiaouExplanations),
      ('ai_question', context.l10n.xiaouQuestions),
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
            context.l10n.readingTraces,
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
              hintText: context.l10n.searchTraces,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: context.l10n.clearSearch,
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
            tooltip: context.l10n.allBooks,
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
          SizedBox(
            height: 42,
            child: Row(
              children: [
                for (var index = 0; index < filters.length; index++) ...[
                  if (index > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: _sourceFilter == filters[index].$1,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(11),
                          onTap: () =>
                              setState(() => _sourceFilter = filters[index].$1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOut,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: _sourceFilter == filters[index].$1
                                  ? palette.primaryLight.withAlpha(92)
                                  : palette.card.withAlpha(180),
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(
                                color: _sourceFilter == filters[index].$1
                                    ? palette.primary.withAlpha(90)
                                    : palette.divider.withAlpha(100),
                              ),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                filters[index].$2,
                                maxLines: 1,
                                style: TextStyle(
                                  color: _sourceFilter == filters[index].$1
                                      ? palette.primaryDark
                                      : palette.textPrimary,
                                  fontSize: 12.5,
                                  fontWeight: _sourceFilter == filters[index].$1
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
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
            label: Text(context.l10n.importantOnly),
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
    final result = <_BookOption>[
      _BookOption(key: 'all', title: context.l10n.allBooks),
    ];
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

  String _localizedSourceLabel(BuildContext context, String source) {
    return switch (source) {
      'ai_explanation' => context.l10n.xiaouExplanations,
      'ai_question' => context.l10n.xiaouQuestions,
      'thought' || 'manual' => context.l10n.thoughts,
      'highlight' => context.l10n.highlights,
      _ => context.l10n.readingTraces,
    };
  }

  Widget _buildFilteredEmpty({bool loadFailed = false}) {
    final palette = context.appPalette;
    final hasAnyItems = (_allItems.isNotEmpty ? _allItems : _items).isNotEmpty;
    return SizedBox(
      height: 230,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Text(
            hasAnyItems
                ? context.l10n.noMatchingTraces
                : loadFailed && _hasResolvedLoad
                ? context.l10n.noNewTraces
                : context.l10n.tracesEmptyBody,
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
                context.l10n.xiaouDiscovery,
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
              child: Text(
                _discoveryExpanded
                    ? context.l10n.collapse
                    : context.l10n.expand,
              ),
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
  final String contextBookId;
  final String contextBookTitle;

  const _XiaouAgentChatSheet({
    this.contextBookId = '',
    this.contextBookTitle = '',
  });

  @override
  State<_XiaouAgentChatSheet> createState() => _XiaouAgentChatSheetState();
}

class _XiaouAgentChatSheetState extends State<_XiaouAgentChatSheet> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<AiMessage> _messages = [];
  StreamSubscription<String>? _subscription;
  bool _loading = false;
  bool _openingConversation = false;
  String? _error;
  String? _historySyncWarning;
  String? _conversationId;
  String _conversationTitle = '';
  String _conversationBookId = '';
  String _conversationBookTitle = '';
  bool _isXiaouAsks = false;
  bool _currentAssistantPersisted = false;

  List<(IconData, String, String)> _quickActions(BuildContext context) => [
    (
      Icons.auto_awesome_outlined,
      context.l10n.quickExplainLabel,
      context.l10n.quickExplainPrompt,
    ),
    (
      Icons.format_quote_rounded,
      context.l10n.quickReviewLabel,
      context.l10n.quickReviewPrompt,
    ),
    (
      Icons.menu_book_outlined,
      context.l10n.quickBookChatLabel,
      context.l10n.quickBookChatPrompt,
    ),
  ];

  @override
  void dispose() {
    if (_loading &&
        _messages.isNotEmpty &&
        _messages.last.role == 'assistant' &&
        _messages.last.content.trim().isNotEmpty) {
      unawaited(
        _persistAssistant(_messages.last.content.trim(), status: 'cancelled'),
      );
    }
    _subscription?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _loading || _openingConversation) return;
    await _subscription?.cancel();
    final availableHistory = _messages
        .where((m) => m.content.trim().isNotEmpty)
        .toList();
    final history = availableHistory.length <= 10
        ? availableHistory
        : availableHistory.sublist(availableHistory.length - 10);
    final userMessage = AiMessage(
      role: 'user',
      content: text,
      timestamp: DateTime.now(),
    );
    final assistantTime = DateTime.now().add(const Duration(milliseconds: 1));
    setState(() {
      _controller.clear();
      _error = null;
      _historySyncWarning = null;
      _loading = true;
      _currentAssistantPersisted = false;
      _messages.add(userMessage);
      _messages.add(
        AiMessage(role: 'assistant', content: '', timestamp: assistantTime),
      );
    });
    _scrollToBottom();

    try {
      final conversationId = await _ensureConversation(text);
      await XiaouConversationService.appendMessage(
        conversationId: conversationId,
        role: 'user',
        content: text,
      );
    } catch (error) {
      _setHistorySyncWarning('这次对话暂未同步到历史记录：${_shortError(error)}');
    }
    if (!mounted) return;

    final buffer = StringBuffer();
    _subscription =
        AiService.xiaouAgentStream(
          message: text,
          conversationHistory: history,
          interactionMode: _isXiaouAsks ? 'xiaou_asks' : 'chat',
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
            final partial = buffer.toString().trim();
            if (partial.isNotEmpty) {
              unawaited(_persistAssistant(partial, status: 'error'));
            }
            setState(() {
              _loading = false;
              _error = AiService.friendlyError(error);
              _removeEmptyAssistantTail();
            });
          },
          onDone: () {
            if (!mounted) return;
            final answer = buffer.toString().trim();
            if (answer.isNotEmpty) {
              unawaited(_persistAssistant(answer));
            }
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
    final partial = _messages.isNotEmpty && _messages.last.role == 'assistant'
        ? _messages.last.content.trim()
        : '';
    if (partial.isNotEmpty) {
      unawaited(_persistAssistant(partial, status: 'cancelled'));
    }
    setState(() {
      _loading = false;
      _removeEmptyAssistantTail();
    });
  }

  Future<String> _ensureConversation(String firstMessage) async {
    final currentId = _conversationId;
    if (currentId != null && currentId.isNotEmpty) return currentId;
    final conversation = await XiaouConversationService.create(
      kind: _isXiaouAsks ? 'xiaou_asks' : 'chat',
      title: _isXiaouAsks ? '小U问我' : '',
      bookId: _conversationBookId.isNotEmpty
          ? _conversationBookId
          : widget.contextBookId,
      bookTitle: _conversationBookTitle.isNotEmpty
          ? _conversationBookTitle
          : widget.contextBookTitle,
    );
    if (!mounted) return conversation.id;
    setState(() {
      _conversationId = conversation.id;
      _conversationTitle = _isXiaouAsks ? '小U问我' : _titleFrom(firstMessage);
      _conversationBookId = conversation.bookId;
      _conversationBookTitle = conversation.bookTitle;
    });
    return conversation.id;
  }

  Future<void> _persistAssistant(
    String content, {
    String status = 'completed',
  }) async {
    if (_currentAssistantPersisted || content.trim().isEmpty) return;
    final conversationId = _conversationId;
    if (conversationId == null || conversationId.isEmpty) return;
    _currentAssistantPersisted = true;
    try {
      await XiaouConversationService.appendMessage(
        conversationId: conversationId,
        role: 'assistant',
        content: content,
        status: status,
      );
    } catch (error) {
      _currentAssistantPersisted = false;
      _setHistorySyncWarning('回答暂未同步到历史记录：${_shortError(error)}');
    }
  }

  void _setHistorySyncWarning(String message) {
    if (!mounted) return;
    setState(() => _historySyncWarning = message);
  }

  void _startNewConversation() {
    if (_loading || _openingConversation) return;
    setState(() {
      _messages.clear();
      _conversationId = null;
      _conversationTitle = '';
      _conversationBookId = '';
      _conversationBookTitle = '';
      _isXiaouAsks = false;
      _error = null;
      _historySyncWarning = null;
      _currentAssistantPersisted = false;
    });
  }

  Future<void> _startXiaouAsksConversation() async {
    if (_loading || _openingConversation) return;
    await _subscription?.cancel();
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _conversationId = null;
      _conversationTitle = '小U问我';
      _conversationBookId = widget.contextBookId;
      _conversationBookTitle = widget.contextBookTitle;
      _isXiaouAsks = true;
      _error = null;
      _historySyncWarning = null;
      _currentAssistantPersisted = false;
    });
    await _requestXiaouQuestion();
  }

  Future<void> _requestXiaouQuestion() async {
    if (_loading || _openingConversation || !_isXiaouAsks) return;
    await _subscription?.cancel();
    final history = _messages
        .where((message) => message.content.trim().isNotEmpty)
        .toList(growable: false);
    final assistantTime = DateTime.now();
    setState(() {
      _error = null;
      _historySyncWarning = null;
      _loading = true;
      _currentAssistantPersisted = false;
      _messages.add(
        AiMessage(role: 'assistant', content: '', timestamp: assistantTime),
      );
    });
    _scrollToBottom();

    try {
      await _ensureConversation('小U问我');
    } catch (error) {
      _setHistorySyncWarning('这次对谈暂未同步到历史记录：${_shortError(error)}');
    }
    if (!mounted) return;

    final buffer = StringBuffer();
    _subscription =
        AiService.xiaouOpeningQuestionStream(
          conversationHistory: history,
          currentBookId: _conversationBookId,
          currentBookTitle: _conversationBookTitle,
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
            final partial = buffer.toString().trim();
            if (partial.isNotEmpty) {
              unawaited(_persistAssistant(partial, status: 'error'));
            }
            setState(() {
              _loading = false;
              _error = AiService.friendlyError(error);
              _removeEmptyAssistantTail();
            });
          },
          onDone: () {
            if (!mounted) return;
            final question = buffer.toString().trim();
            if (question.isNotEmpty) {
              unawaited(_persistAssistant(question));
            }
            setState(() {
              _loading = false;
              if (question.isEmpty) {
                _error = '小U还没有想好从哪里问起，可以再换一个问题。';
                _removeEmptyAssistantTail();
              }
            });
          },
          cancelOnError: true,
        );
  }

  Future<void> _endXiaouAsks() async {
    if (!_isXiaouAsks || _loading || _openingConversation) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('结束这次对谈？'),
        content: const Text('这段内容不会自动进入你的阅读痕迹。你可以只结束，也可以把自己的回答保存为一条想法。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('继续聊'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: const Text('不保存，结束'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('保存为想法'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'save' && !await _saveXiaouAsksAsThought()) return;
    if (mounted) Navigator.pop(context);
  }

  Future<bool> _saveXiaouAsksAsThought() async {
    final userAnswers = _messages
        .where(
          (message) =>
              message.role == 'user' && message.content.trim().isNotEmpty,
        )
        .map((message) => message.content.trim())
        .toList(growable: false);
    if (userAnswers.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('你还没有写下回答，暂时没有可保存的想法')));
      return false;
    }
    final openingQuestion = _messages
        .where(
          (message) =>
              message.role == 'assistant' && message.content.trim().isNotEmpty,
        )
        .map((message) => stripMarkdownMarkers(message.content).trim())
        .firstWhere((content) => content.isNotEmpty, orElse: () => '小U问我');
    final thought = userAnswers.join('\n\n');
    final now = DateTime.now();
    try {
      await BookService.insertUserEntry(
        UserEntry(
          id: const Uuid().v4(),
          source: 'thought',
          bookId: _conversationBookId,
          bookTitle: _conversationBookTitle,
          originalText: openingQuestion,
          userInput: thought,
          autoTags: const ['小U问我'],
          autoSummary: thought.length > 120
              ? '${thought.substring(0, 120)}…'
              : thought,
          metadataJson: jsonEncode({
            'origin': 'xiaou_asks',
            'conversation_id': _conversationId ?? '',
            'transcript': _messages
                .where((message) => message.content.trim().isNotEmpty)
                .map(
                  (message) => {
                    'role': message.role,
                    'content': message.content.trim(),
                  },
                )
                .toList(growable: false),
          }),
          createdAt: now,
          updatedAt: now.toUtc().toIso8601String(),
        ),
      );
      if (!mounted) return true;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已保存为想法')));
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存想法失败：${_shortError(error)}')));
      }
      return false;
    }
  }

  Future<void> _showHistory() async {
    if (_loading || _openingConversation) return;
    final conversationId = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => const _XiaouConversationHistorySheet(),
    );
    if (conversationId == null || !mounted) return;
    setState(() {
      _openingConversation = true;
      _error = null;
    });
    try {
      final thread = await XiaouConversationService.get(conversationId);
      if (!mounted) return;
      setState(() {
        _conversationId = thread.conversation.id;
        _conversationTitle = thread.conversation.displayTitle;
        _conversationBookId = thread.conversation.bookId;
        _conversationBookTitle = thread.conversation.bookTitle;
        _isXiaouAsks = thread.conversation.isXiaouAsks;
        _messages
          ..clear()
          ..addAll(thread.messages);
        _historySyncWarning = null;
      });
      _scrollToBottom();
    } catch (error) {
      if (mounted) {
        setState(() => _error = '读取历史对话失败：${_shortError(error)}');
      }
    } finally {
      if (mounted) setState(() => _openingConversation = false);
    }
  }

  Future<void> _saveMessageAsFreeNote(AiMessage message) async {
    final content = stripMarkdownMarkers(message.content).trim();
    if (content.isEmpty) return;
    await _saveContentAsFreeNote(
      initialTitle: _conversationTitle.isEmpty ? '和小U的对话' : _conversationTitle,
      initialContent: content,
    );
  }

  Future<void> _saveConversationAsFreeNote() async {
    final messages = _messages
        .where((message) => message.content.trim().isNotEmpty)
        .toList(growable: false);
    if (messages.isEmpty) return;
    final content = messages
        .map((message) {
          final label = message.role == 'assistant' ? '小U' : '我';
          final body = message.role == 'assistant'
              ? stripMarkdownMarkers(message.content).trim()
              : message.content.trim();
          return '$label：\n$body';
        })
        .join('\n\n');
    await _saveContentAsFreeNote(
      initialTitle: _conversationTitle.isEmpty ? '和小U的对话' : _conversationTitle,
      initialContent: content,
    );
  }

  Future<void> _saveContentAsFreeNote({
    required String initialTitle,
    required String initialContent,
  }) async {
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _SaveXiaouMessageToFreeNoteSheet(
        initialTitle: initialTitle,
        initialContent: initialContent,
      ),
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await BookService.saveFreeNote(
        title: result.$1,
        content: result.$2,
        waitForRemote: true,
      );
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('已存入随心记，仅自己可见')));
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('已保存在本机，云端会在网络恢复后继续同步')),
      );
    }
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
                            _isXiaouAsks
                                ? context.l10n.xiaouAsksMe
                                : context.l10n.chatWithXiaou,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _conversationTitle.isEmpty
                                ? _isXiaouAsks
                                      ? context.l10n.xiaouAsksSubtitle
                                      : context.l10n.xiaouChatSubtitle
                                : _conversationTitle,
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
                    if (!_isXiaouAsks) ...[
                      IconButton(
                        tooltip: context.l10n.chatHistory,
                        onPressed: _loading ? null : _showHistory,
                        icon: const Icon(Icons.history_rounded),
                      ),
                      PopupMenuButton<String>(
                        tooltip: context.l10n.conversationActions,
                        enabled: !_loading && !_openingConversation,
                        onSelected: (value) {
                          if (value == 'new') {
                            _startNewConversation();
                          } else if (value == 'save') {
                            unawaited(_saveConversationAsFreeNote());
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'new',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.edit_square),
                              title: Text(context.l10n.newConversation),
                            ),
                          ),
                          if (_messages.any(
                            (message) => message.content.trim().isNotEmpty,
                          ))
                            PopupMenuItem(
                              value: 'save',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.bookmark_add_outlined),
                                title: Text(context.l10n.saveWholeConversation),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (_loading)
                      TextButton(
                        onPressed: _cancel,
                        child: Text(context.l10n.stop),
                      ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              if (_isXiaouAsks)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: _loading || _openingConversation
                            ? null
                            : _requestXiaouQuestion,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(context.l10n.changeQuestion),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: _loading || _openingConversation
                            ? null
                            : _endXiaouAsks,
                        icon: const Icon(Icons.stop_circle_outlined, size: 18),
                        label: Text(context.l10n.endConversation),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _openingConversation
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty
                    ? _buildEmptyState(palette)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          return _XiaouAgentBubble(
                            message: _messages[index],
                            onSaveToFreeNote:
                                _isXiaouAsks ||
                                    _messages[index].content.trim().isEmpty
                                ? null
                                : () =>
                                      _saveMessageAsFreeNote(_messages[index]),
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
              if (_historySyncWarning != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                  child: Text(
                    _historySyncWarning!,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 11.5,
                    ),
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
                            hintText: _isXiaouAsks
                                ? context.l10n.xiaouAnswerHint
                                : context.l10n.askXiaouDirectly,
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
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
      children: [
        Text(
          context.l10n.xiaouStartFromReading,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 17,
            height: 1.55,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          context.l10n.xiaouStartBody,
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        Material(
          color: palette.primarySoft.withValues(alpha: 0.56),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _startXiaouAsksConversation,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.question_answer_outlined,
                    size: 19,
                    color: palette.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.xiaouAsksMe,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          context.l10n.xiaouAskMeSubtitle,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 19,
                    color: palette.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        for (final action in _quickActions(context))
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Material(
              color: palette.card.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _send(action.$3),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(action.$1, size: 19, color: palette.icon),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          action.$2,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 19,
                        color: palette.textSecondary,
                      ),
                    ],
                  ),
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
  final VoidCallback? onSaveToFreeNote;

  const _XiaouAgentBubble({
    required this.message,
    required this.loading,
    this.onSaveToFreeNote,
  });

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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Expanded(child: AiGeneratedNotice(compact: true)),
                        if (onSaveToFreeNote != null)
                          IconButton(
                            tooltip: '存入随心记',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 34,
                              minHeight: 34,
                            ),
                            onPressed: onSaveToFreeNote,
                            icon: const Icon(
                              Icons.bookmark_add_outlined,
                              size: 17,
                            ),
                          ),
                      ],
                    ),
                  if (isUser && onSaveToFreeNote != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: '存入随心记',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 34,
                          minHeight: 34,
                        ),
                        onPressed: onSaveToFreeNote,
                        icon: const Icon(Icons.bookmark_add_outlined, size: 17),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _XiaouConversationHistorySheet extends StatefulWidget {
  const _XiaouConversationHistorySheet();

  @override
  State<_XiaouConversationHistorySheet> createState() =>
      _XiaouConversationHistorySheetState();
}

class _XiaouConversationHistorySheetState
    extends State<_XiaouConversationHistorySheet> {
  List<XiaouConversationSummary> _conversations = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _deletingIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final conversations = await XiaouConversationService.list();
      if (!mounted) return;
      setState(() => _conversations = conversations);
    } catch (error) {
      if (mounted) {
        setState(() => _error = _shortError(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(XiaouConversationSummary conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这段对话？'),
        content: const Text('删除后无法恢复，但已经存入随心记的内容不会受到影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingIds.add(conversation.id));
    try {
      await XiaouConversationService.delete(conversation.id);
      if (!mounted) return;
      setState(() {
        _conversations = _conversations
            .where((item) => item.id != conversation.id)
            .toList(growable: false);
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：${_shortError(error)}')));
      }
    } finally {
      if (mounted) setState(() => _deletingIds.remove(conversation.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return FractionallySizedBox(
      heightFactor: 0.82,
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
                color: palette.divider,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '和小U说过的话',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(palette)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AppPalette palette) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '历史记录暂时没有打开\n$_error',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary, height: 1.55),
              ),
              const SizedBox(height: 14),
              TextButton(onPressed: _load, child: const Text('再试一次')),
            ],
          ),
        ),
      );
    }
    if (_conversations.isEmpty) {
      return Center(
        child: Text(
          '还没有保存过的对话。',
          style: TextStyle(color: palette.textSecondary),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      itemCount: _conversations.length,
      separatorBuilder: (_, _) => Divider(color: palette.divider, height: 1),
      itemBuilder: (context, index) {
        final conversation = _conversations[index];
        final deleting = _deletingIds.contains(conversation.id);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 8,
          ),
          title: Text(
            conversation.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              [
                if (conversation.lastMessage.isNotEmpty)
                  conversation.lastMessage,
                _formatConversationDate(conversation.updatedAt),
              ].join('\n'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
          trailing: deleting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: '删除对话',
                  onPressed: () => _delete(conversation),
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                ),
          onTap: deleting
              ? null
              : () => Navigator.pop(context, conversation.id),
        );
      },
    );
  }
}

class _SaveXiaouMessageToFreeNoteSheet extends StatefulWidget {
  final String initialTitle;
  final String initialContent;

  const _SaveXiaouMessageToFreeNoteSheet({
    required this.initialTitle,
    required this.initialContent,
  });

  @override
  State<_SaveXiaouMessageToFreeNoteSheet> createState() =>
      _SaveXiaouMessageToFreeNoteSheetState();
}

class _SaveXiaouMessageToFreeNoteSheetState
    extends State<_SaveXiaouMessageToFreeNoteSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _contentController = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _save() {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;
    Navigator.pop(context, (_titleController.text.trim(), content));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Material(
        color: palette.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.divider,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '存入随心记',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '保存后仅自己可见，也不会自动交给小U再次观察。',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _titleController,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: '标题',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _contentController,
                  minLines: 5,
                  maxLines: 12,
                  decoration: const InputDecoration(labelText: '正文'),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('保存到随心记'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _shortError(Object error) {
  return error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
}

String _titleFrom(String message) {
  final firstLine = message
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '和小U说话');
  return firstLine.length > 36 ? '${firstLine.substring(0, 36)}…' : firstLine;
}

String _formatConversationDate(DateTime date) {
  final local = date.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return '今天 ${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
  return '${local.year}.${local.month.toString().padLeft(2, '0')}.'
      '${local.day.toString().padLeft(2, '0')}';
}
