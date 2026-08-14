import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../l10n/l10n.dart';
import '../../models/book.dart';
import '../../models/mingtai_community.dart';
import '../../services/auth_service.dart';
import '../../services/app_image_cache.dart';
import '../../services/book_service.dart';
import '../../services/first_use_guide_service.dart';
import '../../services/mingtai_community_api.dart';
import '../../services/privacy_service.dart';
import '../../utils/community_safety.dart';
import '../../widgets/first_use_guides.dart';
import 'mingtai_screen.dart' show MingtaiProfileScreen;

const _communityApi = MingtaiCommunityApi();

class _CommunityFeedSnapshot {
  final List<CommunityPost> posts;
  final List<CommunityBook> books;
  final List<CommunityReader> readers;
  final bool usingFallback;
  final bool requiresAuth;

  const _CommunityFeedSnapshot({
    required this.posts,
    required this.books,
    required this.readers,
    required this.usingFallback,
    required this.requiresAuth,
  });
}

Future<bool?> showCommunityPostComposer(
  BuildContext context, {
  Book? localBook,
  CommunityBook? communityBook,
  String initialType = 'thought',
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CommunityPostComposer(
      initialLocalBook: localBook,
      initialCommunityBook: communityBook,
      initialType: initialType,
    ),
  );
}

class CommunityMingtaiScreen extends StatefulWidget {
  final int refreshSignal;
  final bool isActive;

  const CommunityMingtaiScreen({
    super.key,
    this.refreshSignal = 0,
    this.isActive = true,
  });

  @override
  State<CommunityMingtaiScreen> createState() => _CommunityMingtaiScreenState();
}

class _CommunityMingtaiScreenState extends State<CommunityMingtaiScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  int _tabIndex = 0;
  bool _loading = true;
  bool _refreshing = false;
  bool _searching = false;
  String? _error;
  String _searchQuery = '';
  List<CommunityPost> _posts = const [];
  List<CommunityBook> _books = const [];
  List<CommunityReader> _suggestedReaders = const [];
  bool _usingFallback = false;
  bool _requiresAuth = false;
  int _feedRequestVersion = 0;
  int _searchRequestVersion = 0;
  String? _searchError;
  final Map<String, _CommunityFeedSnapshot> _feedSnapshots = {};
  List<CommunityPost> _searchPosts = const [];
  List<CommunityBook> _searchBooks = const [];
  bool _showIntroductionGuide = false;

  String get _tab => const ['recommend', 'following', 'same_read'][_tabIndex];

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeShowIntroductionGuide());
    });
  }

  @override
  void didUpdateWidget(covariant CommunityMingtaiScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      _load(quiet: true);
    }
    if (widget.isActive && !oldWidget.isActive) {
      unawaited(_maybeShowIntroductionGuide());
    }
  }

  @override
  void dispose() {
    _feedRequestVersion++;
    _searchRequestVersion++;
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _maybeShowIntroductionGuide() async {
    final shouldShow = await FirstUseGuideService.claim(
      FirstUseGuide.mingtaiIntroduction,
    );
    if (!mounted || !shouldShow) return;
    setState(() => _showIntroductionGuide = true);
  }

  Future<void> _dismissIntroductionGuide() async {
    await FirstUseGuideService.complete(FirstUseGuide.mingtaiIntroduction);
    if (!mounted) return;
    setState(() => _showIntroductionGuide = false);
  }

  Future<void> _showSharingGuide() async {
    await FirstUseGuideService.complete(FirstUseGuide.mingtaiIntroduction);
    if (!mounted) return;
    setState(() => _showIntroductionGuide = false);
    await showMingtaiSharingGuide(context);
  }

  Future<void> _load({bool quiet = false}) async {
    if (quiet && _refreshing) return;
    final requestVersion = ++_feedRequestVersion;
    final requestedTab = _tab;
    setState(() {
      if (_posts.isEmpty && !quiet) _loading = true;
      _refreshing = quiet || _posts.isNotEmpty;
      _error = null;
    });
    debugPrint(
      '[MingtaiFeed] start version=$requestVersion tab=$requestedTab '
      'retained=${_posts.length}',
    );
    try {
      final result = await _communityApi.getFeed(requestedTab);
      if (!mounted || requestVersion != _feedRequestVersion) {
        debugPrint(
          '[MingtaiFeed] stale result ignored version=$requestVersion',
        );
        return;
      }
      final snapshot = _CommunityFeedSnapshot(
        posts: result.posts,
        books: result.books,
        readers: result.suggestedReaders,
        usingFallback: result.fallback,
        requiresAuth: result.requiresAuth,
      );
      _feedSnapshots[requestedTab] = snapshot;
      setState(() {
        _posts = result.posts;
        _books = result.books;
        _suggestedReaders = result.suggestedReaders;
        _usingFallback = result.fallback;
        _requiresAuth = result.requiresAuth;
        _loading = false;
        _refreshing = false;
      });
      debugPrint(
        '[MingtaiFeed] server snapshot version=$requestVersion '
        'tab=$requestedTab posts=${result.posts.length} '
        'books=${result.books.length} '
        'empty=${result.posts.isEmpty && result.books.isEmpty}',
      );
    } catch (error) {
      if (!mounted || requestVersion != _feedRequestVersion) return;
      setState(() {
        _error = _friendly(error);
        _loading = false;
        _refreshing = false;
      });
      debugPrint(
        '[MingtaiFeed] failed version=$requestVersion tab=$requestedTab '
        'retained=${_posts.length}: $error',
      );
    }
  }

  void _changeTab(int index) {
    if (_tabIndex == index) return;
    final nextTab = const ['recommend', 'following', 'same_read'][index];
    final snapshot = _feedSnapshots[nextTab];
    setState(() {
      _tabIndex = index;
      _posts = snapshot?.posts ?? const [];
      _books = snapshot?.books ?? const [];
      _suggestedReaders = snapshot?.readers ?? const [];
      _usingFallback = snapshot?.usingFallback ?? false;
      _requiresAuth = snapshot?.requiresAuth ?? false;
      _error = null;
    });
    _load(quiet: snapshot != null);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final requestVersion = ++_searchRequestVersion;
    final query = value.trim();
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _searchBooks = const [];
        _searchPosts = const [];
        _searching = false;
        _searchError = null;
      } else {
        _searching = true;
        _searchError = null;
      }
    });
    if (query.isEmpty) return;
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final result = await _communityApi.search(query);
        if (!mounted ||
            _searchQuery != query ||
            requestVersion != _searchRequestVersion) {
          debugPrint(
            '[MingtaiSearch] stale result ignored version=$requestVersion',
          );
          return;
        }
        setState(() {
          _searchBooks = result.books;
          _searchPosts = result.posts;
          _searching = false;
          _searchError = null;
        });
        debugPrint(
          '[MingtaiSearch] result version=$requestVersion query=$query '
          'posts=${result.posts.length} books=${result.books.length}',
        );
      } catch (error) {
        if (!mounted ||
            _searchQuery != query ||
            requestVersion != _searchRequestVersion) {
          return;
        }
        setState(() {
          _searching = false;
          _searchError = _friendly(error);
        });
        debugPrint(
          '[MingtaiSearch] failed version=$requestVersion query=$query: $error',
        );
      }
    });
  }

  Future<void> _compose({
    String initialType = 'thought',
    CommunityBook? book,
  }) async {
    final created = await showCommunityPostComposer(
      context,
      communityBook: book,
      initialType: initialType,
    );
    if (created == true) await _load(quiet: true);
  }

  Future<void> _openComposeActions() async {
    if (!await _requireLogin() || !mounted) return;
    final type = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ComposeActionSheet(),
    );
    if (type == null || !mounted) return;
    await _compose(initialType: type);
  }

  Future<void> _openNotifications() async {
    if (!await _requireLogin()) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CommunityNotificationsScreen()),
    );
  }

  Future<bool> _requireLogin() async {
    await AuthService.init();
    if (AuthService.isLoggedIn) return true;
    if (!mounted) return false;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.loginRequiredMingtai)));
    Navigator.of(context).pushNamed('/settings');
    return false;
  }

  Future<void> _toggleFavorite(int index) async {
    if (!await _requireLogin()) return;
    final post = _posts[index];
    final next = !post.viewerFavorited;
    setState(() {
      _posts = [..._posts]
        ..[index] = post.copyWith(
          viewerFavorited: next,
          favoriteCount: (post.favoriteCount + (next ? 1 : -1)).clamp(
            0,
            1 << 30,
          ),
        );
    });
    try {
      final actual = await _communityApi.toggleFavorite(post.id);
      if (!mounted || actual == next) return;
      await _load(quiet: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _posts = [..._posts]..[index] = post;
      });
      _showError(error);
    }
  }

  Future<void> _openQuoteReply(CommunityPost post) async {
    if (!await _requireLogin() || !mounted) return;
    final quote = await _pickQuotedSentence(context, post);
    if (quote == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommunityCommentsSheet(post: post, initialQuote: quote),
    );
    if (mounted) _load(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final searching = _searchQuery.isNotEmpty;
    final hasFeedSnapshot =
        _posts.isNotEmpty || _books.isNotEmpty || _suggestedReaders.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.mingtaiTitle),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: context.l10n.notifications,
            onPressed: _openNotifications,
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_refreshing) const LinearProgressIndicator(minHeight: 2),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: _showIntroductionGuide
                ? MingtaiIntroductionGuide(
                    onBrowse: _dismissIntroductionGuide,
                    onLearnSharing: _showSharingGuide,
                    onDismiss: _dismissIntroductionGuide,
                  )
                : const SizedBox.shrink(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: context.l10n.mingtaiSearch,
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: palette.surface.withValues(alpha: 0.82),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: palette.primary.withValues(alpha: 0.34),
                  ),
                ),
                suffixIcon: searching
                    ? IconButton(
                        tooltip: context.l10n.clear,
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                        icon: const Icon(Icons.close_rounded),
                      )
                    : null,
              ),
            ),
          ),
          if (!searching)
            _CommunityTabBar(selectedIndex: _tabIndex, onChanged: _changeTab),
          Expanded(
            child: _loading
                ? const _FeedLoading()
                : RefreshIndicator(
                    onRefresh: () => _load(quiet: true),
                    child: searching
                        ? _SearchResults(
                            loading: _searching,
                            error: _searchError,
                            books: _searchBooks,
                            posts: _searchPosts,
                            onRetry: () => _onSearchChanged(_searchQuery),
                            onOpenBook: _openBook,
                            onOpenProfile: _openProfile,
                            onOpenComments: _openComments,
                          )
                        : ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
                            children: [
                              if (_error != null)
                                _QuietMessage(
                                  icon: Icons.cloud_off_outlined,
                                  title: context.l10n.mingtaiUnavailable,
                                  message: _error!,
                                  action: context.l10n.tryAgain,
                                  onAction: _load,
                                ),
                              if (_error == null || hasFeedSnapshot) ...[
                                if (_tabIndex == 0 && _books.isNotEmpty)
                                  _DailyReadingQuestion(
                                    book: _books.first,
                                    onAnswer: () => _compose(
                                      initialType: 'question',
                                      book: _books.first,
                                    ),
                                    onBook: () => _openBook(_books.first),
                                  ),
                                if (_tabIndex == 1 &&
                                    _suggestedReaders.isNotEmpty)
                                  _SuggestedReadersStrip(
                                    readers: _suggestedReaders,
                                    onOpen: (reader) =>
                                        _openProfile(reader.userId),
                                  ),
                                if (_requiresAuth)
                                  _LoginContextHint(
                                    tabIndex: _tabIndex,
                                    onLogin: () => Navigator.of(
                                      context,
                                    ).pushNamed('/settings'),
                                  ),
                                if (_usingFallback)
                                  _FallbackFeedIntro(tabIndex: _tabIndex),
                                if (_posts.isEmpty)
                                  _CompactFeedStart(
                                    hasBookContext: _books.isNotEmpty,
                                    onCompose: () => _compose(),
                                  ),
                                ...List.generate(
                                  _posts.length,
                                  (index) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: CommunityPostCard(
                                      post: _posts[index],
                                      onBook: () => _openBook(
                                        CommunityBook(
                                          id: _posts[index].bookId,
                                          title: _posts[index].bookTitle,
                                          author: _posts[index].bookAuthor,
                                          coverUrl: _posts[index].bookCoverUrl,
                                          description: '',
                                          canRead: false,
                                          wantCount: 0,
                                          readingCount: 0,
                                          finishedCount: 0,
                                          postCount: 0,
                                          viewerStatus: '',
                                        ),
                                      ),
                                      onProfile: () =>
                                          _openProfile(_posts[index].userId),
                                      onComments: () =>
                                          _openComments(_posts[index]),
                                      onQuoteReply: () =>
                                          _openQuoteReply(_posts[index]),
                                      onFavorite: () => _toggleFavorite(index),
                                      onMoreFromBook: () => _openBook(
                                        CommunityBook(
                                          id: _posts[index].bookId,
                                          title: _posts[index].bookTitle,
                                          author: _posts[index].bookAuthor,
                                          coverUrl: _posts[index].bookCoverUrl,
                                          description: '',
                                          canRead: false,
                                          wantCount: 0,
                                          readingCount: 0,
                                          finishedCount: 0,
                                          postCount: 0,
                                          viewerStatus: '',
                                        ),
                                      ),
                                      onDeleted: _load,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: searching
          ? null
          : _LeaveReadingButton(onPressed: _openComposeActions),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      backgroundColor: palette.background,
    );
  }

  void _openBook(CommunityBook book) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityBookScreen(bookId: book.id, initialBook: book),
      ),
    );
  }

  void _openProfile(String userId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CommunityProfileScreen(userId: userId)),
    );
  }

  Future<void> _openComments(CommunityPost post) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommunityCommentsSheet(post: post),
    );
    if (mounted) _load(quiet: true);
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_friendly(error))));
  }
}

class _CommunityTabBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _CommunityTabBar({
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final labels = [
      context.l10n.recommended,
      context.l10n.following,
      context.l10n.readingTogether,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: SizedBox(
        height: 42,
        child: Row(
          children: List.generate(labels.length, (index) {
            final selected = index == selectedIndex;
            return Expanded(
              child: InkWell(
                onTap: () => onChanged(index),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      labels[index],
                      style: TextStyle(
                        color: selected
                            ? palette.textPrimary
                            : palette.textSecondary,
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 9),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: selected ? 24 : 0,
                      height: 2,
                      decoration: BoxDecoration(
                        color: palette.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _FeedLoading extends StatelessWidget {
  const _FeedLoading();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 110),
      itemCount: 3,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (_, index) => Container(
        height: index == 0 ? 164 : 208,
        decoration: BoxDecoration(
          color: palette.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _LeaveReadingButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _LeaveReadingButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Material(
      color: palette.surface.withValues(alpha: 0.94),
      elevation: 2,
      shadowColor: palette.primary.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_outlined, size: 17, color: palette.icon),
              const SizedBox(width: 8),
              Text(
                context.l10n.leaveReadingTrace,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposeActionSheet extends StatelessWidget {
  const _ComposeActionSheet();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final actions = [
      (
        'reading_update',
        context.l10n.shareCurrentReading,
        context.l10n.shareCurrentReadingSubtitle,
      ),
      (
        'excerpt',
        context.l10n.publishHighlight,
        context.l10n.publishHighlightSubtitle,
      ),
      ('thought', context.l10n.writeThought, context.l10n.writeThoughtSubtitle),
      ('review', context.l10n.writeReview, context.l10n.writeReviewSubtitle),
    ];
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.divider,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              context.l10n.mingtaiComposeTitle,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.mingtaiComposePrivacy,
              style: TextStyle(color: palette.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            ...actions.map(
              (action) => InkWell(
                onTap: () => Navigator.pop(context, action.$1),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              action.$2,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              action.$3,
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 17,
                        color: palette.icon.withValues(alpha: 0.72),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyReadingQuestion extends StatelessWidget {
  final CommunityBook book;
  final VoidCallback onAnswer;
  final VoidCallback onBook;

  const _DailyReadingQuestion({
    required this.book,
    required this.onAnswer,
    required this.onBook,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final questions = [
      context.l10n.dailyQuestionOne,
      context.l10n.dailyQuestionTwo,
      context.l10n.dailyQuestionThree,
      context.l10n.dailyQuestionFour,
    ];
    final seed = DateTime.now().day + book.title.hashCode.abs();
    final question = questions[seed % questions.length];
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 14),
      decoration: BoxDecoration(
        color: palette.primaryLight.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.todayQuestion(book.title),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            question,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 17,
              height: 1.55,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton(
                onPressed: onAnswer,
                child: Text(context.l10n.leaveResponse),
              ),
              TextButton(
                onPressed: onBook,
                child: Text(context.l10n.enterBookPage),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuggestedReadersStrip extends StatelessWidget {
  final List<CommunityReader> readers;
  final ValueChanged<CommunityReader> onOpen;

  const _SuggestedReadersStrip({required this.readers, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.meetReaders,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: readers.length,
              separatorBuilder: (_, _) => const SizedBox(width: 18),
              itemBuilder: (_, index) {
                final reader = readers[index];
                return InkWell(
                  onTap: () => onOpen(reader),
                  child: SizedBox(
                    width: 78,
                    child: Column(
                      children: [
                        CommunityAvatar(
                          name: reader.nickname,
                          imageUrl: reader.avatarUrl,
                          radius: 21,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          reader.nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          reader.status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.appPalette.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginContextHint extends StatelessWidget {
  final int tabIndex;
  final VoidCallback onLogin;

  const _LoginContextHint({required this.tabIndex, required this.onLogin});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tabIndex == 1
                  ? context.l10n.loginFollowingHint
                  : context.l10n.loginSameBookHint,
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
            ),
          ),
          TextButton(onPressed: onLogin, child: Text(context.l10n.login)),
        ],
      ),
    );
  }
}

class _FallbackFeedIntro extends StatelessWidget {
  final int tabIndex;

  const _FallbackFeedIntro({required this.tabIndex});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        tabIndex == 1
            ? context.l10n.followingQuietFallback
            : context.l10n.sameBookQuietFallback,
        style: TextStyle(color: palette.textSecondary, fontSize: 12),
      ),
    );
  }
}

class _CompactFeedStart extends StatelessWidget {
  final bool hasBookContext;
  final VoidCallback onCompose;

  const _CompactFeedStart({
    required this.hasBookContext,
    required this.onCompose,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasBookContext
                ? context.l10n.noReplies
                : context.l10n.mingtaiFirstResponse,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            context.l10n.startWithBook,
            style: TextStyle(color: palette.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onCompose,
            child: Text(context.l10n.leaveReadingTrace),
          ),
        ],
      ),
    );
  }
}

class CommunityBookScreen extends StatefulWidget {
  final String bookId;
  final CommunityBook? initialBook;
  final String? focusPostId;

  const CommunityBookScreen({
    super.key,
    required this.bookId,
    this.initialBook,
    this.focusPostId,
  });

  @override
  State<CommunityBookScreen> createState() => _CommunityBookScreenState();
}

class _CommunityBookScreenState extends State<CommunityBookScreen> {
  CommunityBook? _book;
  List<CommunityPost> _posts = const [];
  List<CommunityReader> _readers = const [];
  bool _loading = true;
  String? _error;
  String _sortMode = 'latest';
  String _contentFilter = 'all';
  double? _viewerProgress;
  bool _focusedPostOpened = false;

  List<CommunityPost> get _visiblePosts {
    final filtered = _posts
        .where((post) {
          return switch (_contentFilter) {
            'excerpt' => post.postType == 'excerpt',
            'fragment' => const [
              'fragment_thought',
              'thought',
              'question',
            ].contains(post.postType),
            'status' => const [
              'reading_status',
              'reading_update',
            ].contains(post.postType),
            'review' => post.postType == 'review',
            _ => true,
          };
        })
        .toList(growable: false);
    final sorted = [...filtered];
    if (_sortMode == 'hot') {
      sorted.sort((a, b) {
        final aScore = a.commentCount * 2 + a.favoriteCount;
        final bScore = b.commentCount * 2 + b.favoriteCount;
        return bScore.compareTo(aScore);
      });
    } else if (_sortMode == 'near' && _viewerProgress != null) {
      sorted.sort((a, b) {
        final aDistance = a.readingProgress == null
            ? double.infinity
            : (a.readingProgress! - _viewerProgress!).abs();
        final bDistance = b.readingProgress == null
            ? double.infinity
            : (b.readingProgress! - _viewerProgress!).abs();
        return aDistance.compareTo(bDistance);
      });
    } else {
      sorted.sort(
        (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
          a.createdAt ?? DateTime(1970),
        ),
      );
    }
    return sorted;
  }

  @override
  void initState() {
    super.initState();
    _book = widget.initialBook;
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _communityApi.getBook(widget.bookId),
        BookService.getBooks(),
      ]);
      final result =
          results[0]
              as ({
                CommunityBook book,
                List<CommunityPost> posts,
                List<CommunityReader> readers,
              });
      final localBooks = results[1] as List<Book>;
      final normalizedTitle = result.book.title.trim().toLowerCase();
      final matchingLocal = localBooks.where(
        (book) => book.title.trim().toLowerCase() == normalizedTitle,
      );
      if (!mounted) return;
      setState(() {
        _book = result.book;
        _posts = result.posts;
        _readers = result.readers;
        _viewerProgress = matchingLocal.isEmpty
            ? null
            : matchingLocal.first.readingProgress.clamp(0.0, 1.0).toDouble();
        _loading = false;
        _error = null;
      });
      _openFocusedPostIfNeeded();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendly(error);
        _loading = false;
      });
    }
  }

  void _openFocusedPostIfNeeded() {
    final focusPostId = widget.focusPostId;
    if (_focusedPostOpened || focusPostId == null || focusPostId.isEmpty) {
      return;
    }
    final match = _posts.where((post) => post.id == focusPostId);
    if (match.isEmpty) return;
    _focusedPostOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openPostComments(match.first);
    });
  }

  Future<void> _openPostComments(
    CommunityPost post, {
    String initialQuote = '',
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _CommunityCommentsSheet(post: post, initialQuote: initialQuote),
    );
    if (mounted) await _load();
  }

  Future<void> _quoteReply(CommunityPost post) async {
    final quote = await _pickQuotedSentence(context, post);
    if (quote == null || !mounted) return;
    await _openPostComments(post, initialQuote: quote);
  }

  Future<void> _toggleFavorite(CommunityPost post) async {
    try {
      await _communityApi.toggleFavorite(post.id);
      await _load();
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _compose() async {
    final book = _book;
    if (book == null) return;
    final created = await showCommunityPostComposer(
      context,
      communityBook: book,
      initialType: 'fragment_thought',
    );
    if (created == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    final palette = context.appPalette;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.sameBookSpace)),
      body: _loading && book == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && book == null
          ? Center(child: Text(_error!))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CommunityBookCover(book: book!, width: 92, height: 132),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              book.title,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 23,
                                height: 1.25,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              book.author,
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                            if (book.translator.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                context.l10n.translatorLabel(book.translator),
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            if (book.publisher.isNotEmpty ||
                                book.editionLabel.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                [
                                  book.publisher,
                                  book.editionLabel,
                                ].where((item) => item.isNotEmpty).join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            Text(
                              context.l10n.bookCommunitySummary(
                                book.postCount,
                                book.readingCount,
                              ),
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  _SectionHeader(
                    title: context.l10n.sameBookReaders,
                    trailing: context.l10n.sameBookReaderCount(_readers.length),
                  ),
                  const SizedBox(height: 12),
                  if (_readers.isEmpty)
                    _InlineEmpty(context.l10n.noPublicReadingStatus)
                  else
                    SizedBox(
                      height: 92,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _readers.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 18),
                        itemBuilder: (context, index) {
                          final reader = _readers[index];
                          return InkWell(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CommunityProfileScreen(
                                  userId: reader.userId,
                                ),
                              ),
                            ),
                            child: SizedBox(
                              width: 62,
                              child: Column(
                                children: [
                                  CommunityAvatar(
                                    name: reader.nickname,
                                    imageUrl: reader.avatarUrl,
                                    radius: 24,
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    reader.nickname,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 28),
                  _SectionHeader(
                    title: context.l10n.publicExpressions,
                    action: context.l10n.writeDownThought,
                    onAction: _compose,
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _QuietChoice(
                          label: context.l10n.latest,
                          selected: _sortMode == 'latest',
                          onTap: () => setState(() => _sortMode = 'latest'),
                        ),
                        _QuietChoice(
                          label: context.l10n.mostDiscussed,
                          selected: _sortMode == 'hot',
                          onTap: () => setState(() => _sortMode = 'hot'),
                        ),
                        _QuietChoice(
                          label: context.l10n.nearMyProgress,
                          selected: _sortMode == 'near',
                          onTap: _viewerProgress == null
                              ? null
                              : () => setState(() => _sortMode = 'near'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final item in [
                          ('all', context.l10n.all),
                          ('excerpt', context.l10n.publicExcerpt),
                          ('fragment', context.l10n.fragmentThought),
                          ('status', context.l10n.readingReflection),
                          ('review', context.l10n.bookReview),
                        ])
                          _QuietChoice(
                            label: item.$2,
                            selected: _contentFilter == item.$1,
                            onTap: () =>
                                setState(() => _contentFilter = item.$1),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_visiblePosts.isEmpty)
                    _InlineEmpty(context.l10n.noPublicBookThoughts)
                  else
                    ..._visiblePosts.map(
                      (post) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: CommunityPostCard(
                          post: post,
                          onBook: null,
                          onProfile: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  CommunityProfileScreen(userId: post.userId),
                            ),
                          ),
                          onComments: () => _openPostComments(post),
                          onQuoteReply: () => _quoteReply(post),
                          onFavorite: () => _toggleFavorite(post),
                          onDeleted: _load,
                        ),
                      ),
                    ),
                ],
              ),
            ),
      backgroundColor: palette.background,
    );
  }
}

class CommunityProfileScreen extends StatefulWidget {
  final String? userId;

  const CommunityProfileScreen({super.key, this.userId});

  @override
  State<CommunityProfileScreen> createState() => _CommunityProfileScreenState();
}

class _CommunityProfileScreenState extends State<CommunityProfileScreen> {
  CommunityProfileData? _data;
  bool _loading = true;
  bool _following = false;
  String? _error;

  bool get _isMine =>
      widget.userId == null ||
      widget.userId == 'me' ||
      widget.userId == AuthService.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _communityApi.getProfile(widget.userId ?? 'me');
      if (!mounted) return;
      setState(() {
        _data = data;
        _following = data.viewerFollowing;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendly(error);
      });
    }
  }

  Future<void> _toggleFollow() async {
    final data = _data;
    if (data == null) return;
    try {
      final following = await _communityApi.setFollowing(
        data.userId,
        !_following,
      );
      if (mounted) setState(() => _following = following);
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _editProfile() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MingtaiProfileScreen()));
    await _load();
  }

  Future<void> _blockUser() async {
    final data = _data;
    if (data == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.blockUserTitle(data.nickname)),
        content: Text(context.l10n.blockUserBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.confirmBlock),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await PrivacyService.setBlocked(data.userId, true);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isMine ? context.l10n.myReadingProfile : context.l10n.readingProfile,
        ),
        actions: [
          if (_isMine)
            IconButton(
              tooltip: context.l10n.editProfile,
              onPressed: _editProfile,
              icon: const Icon(Icons.edit_outlined),
            ),
          if (!_isMine)
            PopupMenuButton<String>(
              tooltip: context.l10n.more,
              onSelected: (value) {
                if (value == 'report' && _data != null) {
                  showCommunityReportDialog(
                    context,
                    targetType: 'user',
                    targetId: _data!.userId,
                  );
                } else if (value == 'block') {
                  _blockUser();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'report',
                  child: Text(context.l10n.reportUser),
                ),
                PopupMenuItem(
                  value: 'block',
                  child: Text(context.l10n.blockUser),
                ),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
                children: [
                  Row(
                    children: [
                      CommunityAvatar(
                        name: data!.nickname,
                        imageUrl: data.avatarUrl,
                        radius: 38,
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data.nickname,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              data.bio.isEmpty
                                  ? context.l10n.bioEmpty
                                  : data.bio,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textSecondary,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!_isMine)
                        FilledButton.tonal(
                          onPressed: _toggleFollow,
                          child: Text(
                            _following
                                ? context.l10n.followed
                                : context.l10n.follow,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    context.l10n.profileFollowSummary(
                      data.followerCount,
                      data.reading.length,
                    ),
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 30),
                  _ProfileBookSection(
                    title: context.l10n.currentlyReading,
                    books: data.reading,
                  ),
                  _ProfileBookSection(
                    title: context.l10n.finishedReading,
                    books: data.finished,
                  ),
                  _ProfileBookSection(
                    title: context.l10n.wantToRead,
                    books: data.wantToRead,
                  ),
                  if (_isMine && data.favorites.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _SectionHeader(title: context.l10n.savedReadingTraces),
                    const SizedBox(height: 8),
                    ...data.favorites.map(
                      (post) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          post.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '《${post.bookTitle}》 · ${post.nickname}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CommunityBookScreen(
                              bookId: post.bookId,
                              focusPostId: post.id,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  const SizedBox(height: 8),
                  _SectionHeader(title: context.l10n.publicThoughtsDiscussions),
                  const SizedBox(height: 12),
                  if (data.posts.isEmpty)
                    _InlineEmpty(context.l10n.noPublicThoughts)
                  else
                    ...data.posts.map(
                      (post) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: CommunityPostCard(
                          post: post,
                          onBook: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  CommunityBookScreen(bookId: post.bookId),
                            ),
                          ),
                          onProfile: null,
                          onComments: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => _CommunityCommentsSheet(post: post),
                          ),
                          onQuoteReply: () async {
                            final quote = await _pickQuotedSentence(
                              context,
                              post,
                            );
                            if (quote == null) return;
                            if (!context.mounted) return;
                            await showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => _CommunityCommentsSheet(
                                post: post,
                                initialQuote: quote,
                              ),
                            );
                            await _load();
                          },
                          onFavorite: () async {
                            await _communityApi.toggleFavorite(post.id);
                            await _load();
                          },
                          onMoreFromBook: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  CommunityBookScreen(bookId: post.bookId),
                            ),
                          ),
                          onDeleted: _load,
                        ),
                      ),
                    ),
                ],
              ),
            ),
      backgroundColor: palette.background,
    );
  }
}

class CommunityNotificationsScreen extends StatefulWidget {
  const CommunityNotificationsScreen({super.key});

  @override
  State<CommunityNotificationsScreen> createState() =>
      _CommunityNotificationsScreenState();
}

class _CommunityNotificationsScreenState
    extends State<CommunityNotificationsScreen> {
  List<CommunityNotification> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _communityApi.getNotifications();
      await _communityApi.markNotificationsRead();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('明台消息')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const Center(child: Text('这里还没有新的回声。'))
          : ListView.separated(
              padding: const EdgeInsets.all(18),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const Divider(height: 28),
              itemBuilder: (context, index) {
                final item = _items[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CommunityAvatar(
                    name: item.actorNickname,
                    imageUrl: item.actorAvatarUrl,
                    radius: 22,
                  ),
                  title: Text(_notificationTitle(context, item)),
                  subtitle: item.preview.isEmpty
                      ? Text(_timeLabel(context, item.createdAt))
                      : Text(
                          '${item.preview}\n${_timeLabel(context, item.createdAt)}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                  onTap: item.bookId.isEmpty
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CommunityBookScreen(
                              bookId: item.bookId,
                              focusPostId: item.postId.isEmpty
                                  ? null
                                  : item.postId,
                            ),
                          ),
                        ),
                );
              },
            ),
    );
  }
}

class CommunityPostCard extends StatelessWidget {
  final CommunityPost post;
  final VoidCallback? onBook;
  final VoidCallback? onProfile;
  final VoidCallback onComments;
  final VoidCallback? onQuoteReply;
  final VoidCallback? onFavorite;
  final VoidCallback? onMoreFromBook;
  final VoidCallback? onDeleted;

  const CommunityPostCard({
    super.key,
    required this.post,
    required this.onBook,
    required this.onProfile,
    required this.onComments,
    this.onQuoteReply,
    this.onFavorite,
    this.onMoreFromBook,
    this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onProfile,
            child: Row(
              children: [
                CommunityAvatar(
                  name: post.nickname,
                  imageUrl: post.avatarUrl,
                  radius: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.nickname,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${_postTypeLabel(context, post.postType)} · ${_timeLabel(context, post.createdAt)}',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: context.l10n.more,
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'report') {
                      showCommunityReportDialog(
                        context,
                        targetType: 'post',
                        targetId: post.id,
                      );
                    } else if (value == 'delete') {
                      _deleteOwnPost(context);
                    }
                  },
                  itemBuilder: (_) => post.userId == AuthService.userId
                      ? [
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(context.l10n.deleteThisContent),
                          ),
                        ]
                      : [
                          PopupMenuItem(
                            value: 'report',
                            child: Text(context.l10n.reportThisContent),
                          ),
                        ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (post.postType == 'excerpt' && post.quotedText.isNotEmpty) ...[
            _ExpandableOriginalText(text: post.quotedText, prominent: true),
            if (post.content.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                post.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ],
          ] else ...[
            Text(
              post.content,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 16,
                height: 1.72,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (post.quotedText.isNotEmpty) ...[
              const SizedBox(height: 11),
              _ExpandableOriginalText(text: post.quotedText),
            ],
          ],
          const SizedBox(height: 18),
          InkWell(
            onTap: onBook,
            child: Row(
              children: [
                CommunityBookCover(
                  book: CommunityBook(
                    id: post.bookId,
                    title: post.bookTitle,
                    author: post.bookAuthor,
                    coverUrl: post.bookCoverUrl,
                    description: '',
                    canRead: false,
                    wantCount: 0,
                    readingCount: 0,
                    finishedCount: 0,
                    postCount: 0,
                    viewerStatus: '',
                  ),
                  width: 34,
                  height: 46,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '《${post.bookTitle}》',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        post.chapterLabel.isEmpty
                            ? post.bookAuthor
                            : post.chapterLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 2,
            runSpacing: 0,
            children: [
              TextButton(
                onPressed: onComments,
                child: Text(
                  post.commentCount == 0
                      ? context.l10n.reply
                      : context.l10n.responseCount(post.commentCount),
                ),
              ),
              if (onQuoteReply != null)
                TextButton(
                  onPressed: onQuoteReply,
                  child: Text(context.l10n.quoteReply),
                ),
              if (onFavorite != null)
                TextButton(
                  onPressed: onFavorite,
                  child: Text(
                    post.viewerFavorited
                        ? context.l10n.unfavorite
                        : post.favoriteCount > 0
                        ? '${context.l10n.favorite} ${post.favoriteCount}'
                        : context.l10n.favorite,
                  ),
                ),
              if (onMoreFromBook != null)
                TextButton(
                  onPressed: onMoreFromBook,
                  child: Text(context.l10n.viewSameBook),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _deleteOwnPost(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.deletePublicContentTitle),
        content: Text(context.l10n.deletePublicContentBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await _communityApi.deletePost(post.id);
      onDeleted?.call();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.publicContentDeleted)),
        );
      }
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }
}

class _ExpandableOriginalText extends StatefulWidget {
  final String text;
  final bool prominent;

  const _ExpandableOriginalText({required this.text, this.prominent = false});

  @override
  State<_ExpandableOriginalText> createState() =>
      _ExpandableOriginalTextState();
}

class _ExpandableOriginalTextState extends State<_ExpandableOriginalText> {
  bool _expanded = false;

  bool get _canExpand {
    final text = widget.text.trim();
    final limit = widget.prominent ? 130 : 56;
    return text.length > limit || text.split('\n').length > 2;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final prefix = widget.prominent ? '“' : context.l10n.originalTextPrefix;
    final suffix = widget.prominent ? '”' : '';
    final content = '$prefix${widget.text.trim()}$suffix';
    final textStyle = widget.prominent
        ? TextStyle(
            color: palette.textPrimary,
            fontSize: 16,
            height: 1.72,
            fontWeight: FontWeight.w500,
          )
        : TextStyle(color: palette.textSecondary, fontSize: 12, height: 1.55);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          content,
          maxLines: _expanded ? null : (widget.prominent ? 5 : 2),
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: textStyle,
        ),
        if (_canExpand) ...[
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                _expanded
                    ? context.l10n.collapseOriginal
                    : context.l10n.expandOriginal,
                style: TextStyle(
                  color: palette.primaryDark,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: palette.primaryDark,
              ),
            ],
          ),
        ],
      ],
    );

    if (widget.prominent) {
      return InkWell(
        onTap: _canExpand ? _toggle : null,
        borderRadius: BorderRadius.circular(8),
        child: body,
      );
    }
    return InkWell(
      onTap: _canExpand ? _toggle : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
        decoration: BoxDecoration(
          color: palette.primaryLight.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: body,
      ),
    );
  }

  void _toggle() => setState(() => _expanded = !_expanded);
}

class _CommunityPostComposer extends StatefulWidget {
  final Book? initialLocalBook;
  final CommunityBook? initialCommunityBook;
  final String initialType;

  const _CommunityPostComposer({
    this.initialLocalBook,
    this.initialCommunityBook,
    this.initialType = 'thought',
  });

  @override
  State<_CommunityPostComposer> createState() => _CommunityPostComposerState();
}

class _CommunityPostComposerState extends State<_CommunityPostComposer> {
  final _contentController = TextEditingController();
  final _quoteController = TextEditingController();
  final _chapterController = TextEditingController();
  List<Book> _localBooks = const [];
  Book? _selectedLocalBook;
  late String _type;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _selectedLocalBook = widget.initialLocalBook;
    _loadBooks();
  }

  @override
  void dispose() {
    _contentController.dispose();
    _quoteController.dispose();
    _chapterController.dispose();
    super.dispose();
  }

  Future<void> _loadBooks() async {
    if (widget.initialCommunityBook != null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final books = await BookService.getBooks();
      if (!mounted) return;
      final local = books
          .where((book) => !BookService.isMingtaiShelfBook(book))
          .toList(growable: false);
      setState(() {
        _localBooks = local;
        _selectedLocalBook ??= local.isEmpty ? null : local.first;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _friendly(error);
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    await AuthService.init();
    if (!mounted) return;
    if (!AuthService.isLoggedIn) {
      setState(() => _error = context.l10n.loginBeforePublishing);
      return;
    }
    final content = _contentController.text.trim();
    if (content.length < 5) {
      setState(() => _error = context.l10n.thoughtMinFive);
      return;
    }
    if (_type == 'review' && content.length < 10) {
      setState(() => _error = context.l10n.reviewMinTen);
      return;
    }
    if (_type == 'excerpt' && _quoteController.text.trim().isEmpty) {
      setState(() => _error = context.l10n.highlightRequiresExcerpt);
      return;
    }
    if (_quoteController.text.trim().length > 240) {
      setState(() => _error = context.l10n.excerptTooLong);
      return;
    }
    final guidelinesAccepted = await ensureCommunityGuidelines(context);
    if (!mounted || !guidelinesAccepted) return;
    final previewBookTitle =
        widget.initialCommunityBook?.title ?? _selectedLocalBook?.title ?? '';
    final confirmed = await confirmPublicPostPreview(
      context,
      bookTitle: previewBookTitle,
      content: content,
      quote: _quoteController.text.trim(),
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      var communityBook = widget.initialCommunityBook;
      if (communityBook == null) {
        final local = _selectedLocalBook;
        if (local == null) throw Exception(context.l10n.selectBookFirst);
        communityBook = await _communityApi.resolveBook(
          title: local.title,
          author: local.author,
          coverUrl: local.coverPath ?? '',
          description: local.description ?? '',
        );
      }
      await _communityApi.createPost(
        bookId: communityBook.id,
        type: _type,
        content: content,
        quotedText: _quoteController.text.trim(),
        chapterLabel: _chapterController.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = _friendly(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 32,
                        height: 4,
                        decoration: BoxDecoration(
                          color: palette.divider,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      context.l10n.mingtaiComposeTitle,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.l10n.mingtaiComposePrivacy,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (widget.initialCommunityBook != null)
                      _SelectedBookRow(book: widget.initialCommunityBook!)
                    else if (_localBooks.isEmpty)
                      _InlineEmpty(context.l10n.privateShelfNoBooks)
                    else
                      DropdownButtonFormField<Book>(
                        initialValue: _selectedLocalBook,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.l10n.selectBook,
                        ),
                        items: _localBooks
                            .map(
                              (book) => DropdownMenuItem(
                                value: book,
                                child: Text(
                                  '《${book.title}》 · ${book.author}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedLocalBook = value),
                      ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: InputDecoration(
                        labelText: context.l10n.postType,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'reading_update',
                          child: Text(context.l10n.readingUpdate),
                        ),
                        DropdownMenuItem(
                          value: 'excerpt',
                          child: Text(context.l10n.publicHighlight),
                        ),
                        DropdownMenuItem(
                          value: 'thought',
                          child: Text(context.l10n.readingThought),
                        ),
                        DropdownMenuItem(
                          value: 'fragment_thought',
                          child: Text(context.l10n.fragmentThought),
                        ),
                        DropdownMenuItem(
                          value: 'review',
                          child: Text(context.l10n.bookReview),
                        ),
                        if (_type == 'question')
                          DropdownMenuItem(
                            value: 'question',
                            child: Text(context.l10n.sameBookDiscussion),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _type = value);
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _quoteController,
                      maxLines: 3,
                      maxLength: 240,
                      decoration: InputDecoration(
                        labelText: _type == 'excerpt'
                            ? context.l10n.shortExcerpt
                            : context.l10n.shortExcerptOptional,
                        hintText: context.l10n.shortExcerptHint,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _contentController,
                      minLines: 5,
                      maxLines: 10,
                      maxLength: 4000,
                      decoration: InputDecoration(
                        labelText: _composerContentLabel(context, _type),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _chapterController,
                      maxLines: 1,
                      decoration: InputDecoration(
                        labelText: context.l10n.readingPositionOptional,
                        hintText: context.l10n.readingPositionHint,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            _submitting ||
                                (widget.initialCommunityBook == null &&
                                    _selectedLocalBook == null)
                            ? null
                            : _submit,
                        icon: const Icon(Icons.north_east_rounded),
                        label: Text(
                          _submitting
                              ? context.l10n.publishing
                              : context.l10n.publishToMingtai,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _CommunityCommentsSheet extends StatefulWidget {
  final CommunityPost post;
  final String initialQuote;

  const _CommunityCommentsSheet({required this.post, this.initialQuote = ''});

  @override
  State<_CommunityCommentsSheet> createState() =>
      _CommunityCommentsSheetState();
}

class _CommunityCommentsSheetState extends State<_CommunityCommentsSheet> {
  final _controller = TextEditingController();
  List<CommunityComment> _comments = const [];
  bool _loading = true;
  bool _sending = false;
  String _quotedText = '';
  String _parentReplyId = '';

  @override
  void initState() {
    super.initState();
    _quotedText = widget.initialQuote;
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final comments = await _communityApi.getComments(widget.post.id);
      if (mounted) {
        setState(() {
          _comments = comments;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final content = _controller.text.trim();
    if (content.length < 2 || _sending) return;
    if (!await ensureCommunityGuidelines(context) || !mounted) return;
    setState(() => _sending = true);
    try {
      await _communityApi.createComment(
        widget.post.id,
        content,
        quotedText: _quotedText,
        parentReplyId: _parentReplyId,
      );
      _controller.clear();
      setState(() {
        _quotedText = '';
        _parentReplyId = '';
      });
      await _load();
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.72,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: palette.divider,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                '围绕这段阅读继续讨论',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _comments.isEmpty
                  ? const Center(child: Text('还没有人回应。'))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      itemCount: _comments.length,
                      separatorBuilder: (_, _) => const Divider(height: 24),
                      itemBuilder: (context, index) {
                        final item = _comments[index];
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CommunityProfileScreen(
                                    userId: item.userId,
                                  ),
                                ),
                              ),
                              child: CommunityAvatar(
                                name: item.nickname,
                                imageUrl: item.avatarUrl,
                                radius: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.nickname,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (item.quotedText.isNotEmpty) ...[
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(9),
                                      color: palette.primaryLight.withValues(
                                        alpha: 0.12,
                                      ),
                                      child: Text(
                                        '“${item.quotedText}”',
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: palette.textSecondary,
                                          fontSize: 12,
                                          height: 1.45,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                  ],
                                  Text(
                                    item.content,
                                    style: const TextStyle(height: 1.5),
                                  ),
                                  const SizedBox(height: 3),
                                  TextButton(
                                    onPressed: () => setState(() {
                                      _quotedText = item.content;
                                      _parentReplyId = item.id;
                                    }),
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(44, 30),
                                    ),
                                    child: const Text('引用回应'),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: '更多',
                              onSelected: (value) {
                                if (value == 'report') {
                                  showCommunityReportDialog(
                                    context,
                                    targetType: 'comment',
                                    targetId: item.id,
                                  );
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'report',
                                  child: Text('举报评论'),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_quotedText.isNotEmpty) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '引用：“$_quotedText”',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '取消引用',
                          onPressed: () => setState(() {
                            _quotedText = '';
                            _parentReplyId = '';
                          }),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          maxLines: 3,
                          minLines: 1,
                          decoration: const InputDecoration(hintText: '写下回应…'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        tooltip: '发送',
                        onPressed: _sending ? null : _send,
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  final bool loading;
  final String? error;
  final List<CommunityBook> books;
  final List<CommunityPost> posts;
  final ValueChanged<CommunityBook> onOpenBook;
  final ValueChanged<String> onOpenProfile;
  final ValueChanged<CommunityPost> onOpenComments;
  final VoidCallback onRetry;

  const _SearchResults({
    required this.loading,
    required this.error,
    required this.books,
    required this.posts,
    required this.onOpenBook,
    required this.onOpenProfile,
    required this.onOpenComments,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null && books.isEmpty && posts.isEmpty) {
      return _QuietMessage(
        icon: Icons.cloud_off_outlined,
        title: '搜索暂时没有回应',
        message: error!,
        action: '重试',
        onAction: onRetry,
      );
    }
    if (books.isEmpty && posts.isEmpty) {
      return const Center(child: Text('明台还没有找到相关书页或讨论。'));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
      children: [
        if (error != null) ...[
          _QuietMessage(
            icon: Icons.cloud_off_outlined,
            title: '搜索暂时没有回应',
            message: error!,
            action: '重试',
            onAction: onRetry,
          ),
          const SizedBox(height: 12),
        ],
        if (books.isNotEmpty) ...[
          const _SectionHeader(title: '书籍'),
          const SizedBox(height: 10),
          ...books.map(
            (book) => ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              leading: CommunityBookCover(book: book, width: 42, height: 58),
              title: Text(book.title),
              subtitle: Text(book.author),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => onOpenBook(book),
            ),
          ),
          const SizedBox(height: 22),
        ],
        if (posts.isNotEmpty) ...[
          const _SectionHeader(title: '公开想法与问题'),
          const SizedBox(height: 10),
          ...posts.map(
            (post) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CommunityPostCard(
                post: post,
                onBook: () => onOpenBook(
                  CommunityBook(
                    id: post.bookId,
                    title: post.bookTitle,
                    author: post.bookAuthor,
                    coverUrl: post.bookCoverUrl,
                    description: '',
                    canRead: false,
                    wantCount: 0,
                    readingCount: 0,
                    finishedCount: 0,
                    postCount: 0,
                    viewerStatus: '',
                  ),
                ),
                onProfile: () => onOpenProfile(post.userId),
                onComments: () => onOpenComments(post),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ProfileBookSection extends StatelessWidget {
  final String title;
  final List<CommunityBook> books;

  const _ProfileBookSection({required this.title, required this.books});

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: title),
          const SizedBox(height: 12),
          SizedBox(
            height: 146,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: books.length,
              separatorBuilder: (_, _) => const SizedBox(width: 15),
              itemBuilder: (context, index) {
                final book = books[index];
                return InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CommunityBookScreen(
                        bookId: book.id,
                        initialBook: book,
                      ),
                    ),
                  ),
                  child: SizedBox(
                    width: 76,
                    child: Column(
                      children: [
                        CommunityBookCover(book: book, width: 70, height: 100),
                        const SizedBox(height: 7),
                        Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CommunityBookCover extends StatelessWidget {
  final CommunityBook book;
  final double width;
  final double height;

  const CommunityBookCover({
    super.key,
    required this.book,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: width,
        height: height,
        child: book.coverUrl.startsWith('http')
            ? CachedNetworkImage(
                imageUrl: book.coverUrl,
                cacheManager: AppImageCache.manager,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => _coverFallback(palette),
              )
            : _coverFallback(palette),
      ),
    );
  }

  Widget _coverFallback(AppPalette palette) {
    return ColoredBox(
      color: palette.primaryLight.withValues(alpha: 0.28),
      child: Icon(
        Icons.menu_book_rounded,
        color: palette.icon,
        size: width * 0.38,
      ),
    );
  }
}

class CommunityAvatar extends StatelessWidget {
  final String name;
  final String imageUrl;
  final double radius;

  const CommunityAvatar({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return CircleAvatar(
      radius: radius,
      backgroundColor: palette.primaryLight.withValues(alpha: 0.34),
      foregroundImage: imageUrl.startsWith('http')
          ? CachedNetworkImageProvider(
              imageUrl,
              cacheManager: AppImageCache.manager,
            )
          : null,
      child: Text(
        name.isEmpty ? '读' : name.characters.first,
        style: TextStyle(
          color: palette.primaryDark,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SelectedBookRow extends StatelessWidget {
  final CommunityBook book;

  const _SelectedBookRow({required this.book});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CommunityBookCover(book: book, width: 44, height: 60),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '《${book.title}》',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(book.author),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final String? action;
  final VoidCallback? onAction;

  const _SectionHeader({
    required this.title,
    this.trailing,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(color: palette.textSecondary, fontSize: 12),
          ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    );
  }
}

class _QuietChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _QuietChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: onTap == null
                  ? palette.textSecondary.withValues(alpha: 0.45)
                  : selected
                  ? palette.primaryDark
                  : palette.textSecondary,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _QuietMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onAction;

  const _QuietMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        child: Column(
          children: [
            Icon(icon, size: 42, color: palette.icon.withValues(alpha: 0.7)),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary, height: 1.6),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: onAction, child: Text(action)),
          ],
        ),
      ),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  final String text;

  const _InlineEmpty(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        text,
        style: TextStyle(color: context.appPalette.textSecondary, height: 1.55),
      ),
    );
  }
}

String _friendly(Object error) {
  return error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(_friendly(error))));
}

String _postTypeLabel(BuildContext context, String type) => switch (type) {
  'question' => context.l10n.sharedQuestion,
  'fragment_thought' => context.l10n.sharedFragmentThought,
  'reading_status' => context.l10n.sharedReadingStatus,
  'reading_update' => context.l10n.sharedCurrentReading,
  'excerpt' => context.l10n.sharedExcerpt,
  'review' => context.l10n.sharedReview,
  _ => context.l10n.sharedReadingThought,
};

Future<String?> _pickQuotedSentence(
  BuildContext context,
  CommunityPost post,
) async {
  final source = [
    post.quotedText,
    post.content,
  ].where((item) => item.trim().isNotEmpty).join('\n');
  final candidates = RegExp(r'[^。！？!?\n]+[。！？!?]?')
      .allMatches(source)
      .map((match) => match.group(0)?.trim() ?? '')
      .where((item) => item.length >= 2)
      .map((item) => item.length > 240 ? item.substring(0, 240) : item)
      .toSet()
      .take(8)
      .toList(growable: false);
  if (candidates.isEmpty) return null;
  if (candidates.length == 1) return candidates.first;
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
        itemCount: candidates.length + 1,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                context.l10n.selectQuote,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }
          final sentence = candidates[index - 1];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            title: Text(sentence, style: const TextStyle(height: 1.5)),
            onTap: () => Navigator.pop(sheetContext, sentence),
          );
        },
      ),
    ),
  );
}

String _composerContentLabel(BuildContext context, String type) =>
    switch (type) {
      'reading_update' => context.l10n.readingStatusHint,
      'excerpt' => context.l10n.excerptThoughtHint,
      'review' => context.l10n.reviewHint,
      'question' => context.l10n.questionHint,
      _ => context.l10n.yourThought,
    };

String _timeLabel(BuildContext context, DateTime? date) {
  if (date == null) return '';
  final difference = DateTime.now().difference(date);
  if (difference.inMinutes < 1) return context.l10n.justNow;
  if (difference.inHours < 1) {
    return context.l10n.minutesAgo(difference.inMinutes);
  }
  if (difference.inDays < 1) {
    return context.l10n.hoursAgo(difference.inHours);
  }
  if (difference.inDays < 7) return context.l10n.daysAgo(difference.inDays);
  return MaterialLocalizations.of(context).formatMediumDate(date);
}

String _notificationTitle(BuildContext context, CommunityNotification item) {
  return switch (item.eventType) {
    'follow' => context.l10n.notificationFollow(item.actorNickname),
    'post_comment' => context.l10n.notificationComment(item.actorNickname),
    'post_quote_reply' => context.l10n.notificationQuote(item.actorNickname),
    'post_resonance' => context.l10n.notificationResonance(item.actorNickname),
    _ => context.l10n.notificationDefault(item.actorNickname),
  };
}
