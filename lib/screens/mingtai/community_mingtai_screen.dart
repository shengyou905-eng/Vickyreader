import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../models/book.dart';
import '../../models/mingtai_community.dart';
import '../../services/auth_service.dart';
import '../../services/book_service.dart';
import '../../services/mingtai_community_api.dart';
import '../../services/privacy_service.dart';
import '../../utils/community_safety.dart';
import 'mingtai_screen.dart' show MingtaiProfileScreen;

const _communityApi = MingtaiCommunityApi();

Future<bool?> showCommunityPostComposer(
  BuildContext context, {
  Book? localBook,
  CommunityBook? communityBook,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CommunityPostComposer(
      initialLocalBook: localBook,
      initialCommunityBook: communityBook,
    ),
  );
}

class CommunityMingtaiScreen extends StatefulWidget {
  final int refreshSignal;

  const CommunityMingtaiScreen({super.key, this.refreshSignal = 0});

  @override
  State<CommunityMingtaiScreen> createState() => _CommunityMingtaiScreenState();
}

class _CommunityMingtaiScreenState extends State<CommunityMingtaiScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  int _tabIndex = 1;
  bool _loading = true;
  bool _refreshing = false;
  bool _searching = false;
  String? _error;
  String _searchQuery = '';
  List<CommunityPost> _posts = const [];
  List<CommunityBook> _books = const [];
  List<CommunityPost> _searchPosts = const [];
  List<CommunityBook> _searchBooks = const [];

  String get _tab => const ['following', 'discover', 'same_book'][_tabIndex];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CommunityMingtaiScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      _load(quiet: true);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (quiet && _refreshing) return;
    setState(() {
      if (_posts.isEmpty && !quiet) _loading = true;
      _refreshing = quiet || _posts.isNotEmpty;
      _error = null;
    });
    try {
      final result = await _communityApi.getFeed(_tab);
      if (!mounted) return;
      setState(() {
        _posts = result.posts;
        _books = result.books;
        _loading = false;
        _refreshing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendly(error);
        _loading = false;
        _refreshing = false;
      });
    }
  }

  void _changeTab(int index) {
    if (_tabIndex == index) return;
    setState(() {
      _tabIndex = index;
      _posts = const [];
      _books = const [];
      _error = null;
    });
    _load();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _searchBooks = const [];
        _searchPosts = const [];
        _searching = false;
      } else {
        _searching = true;
      }
    });
    if (query.isEmpty) return;
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final result = await _communityApi.search(query);
        if (!mounted || _searchQuery != query) return;
        setState(() {
          _searchBooks = result.books;
          _searchPosts = result.posts;
          _searching = false;
        });
      } catch (error) {
        if (!mounted || _searchQuery != query) return;
        setState(() {
          _searching = false;
          _error = _friendly(error);
        });
      }
    });
  }

  Future<void> _compose() async {
    final created = await showCommunityPostComposer(context);
    if (created == true) await _load(quiet: true);
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
    ).showSnackBar(const SnackBar(content: Text('登录后才能参与明台讨论')));
    Navigator.of(context).pushNamed('/settings');
    return false;
  }

  Future<void> _toggleResonance(int index) async {
    if (!await _requireLogin()) return;
    final post = _posts[index];
    final next = !post.viewerResonated;
    setState(() {
      _posts = [..._posts]
        ..[index] = post.copyWith(
          viewerResonated: next,
          resonanceCount: (post.resonanceCount + (next ? 1 : -1)).clamp(
            0,
            1 << 30,
          ),
        );
    });
    try {
      final actual = await _communityApi.toggleResonance(post.id);
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

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final searching = _searchQuery.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('明台'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '消息',
            onPressed: _openNotifications,
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          IconButton(
            tooltip: '写阅读动态',
            onPressed: _compose,
            icon: const Icon(Icons.edit_note_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_refreshing) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '找一本书、作者或一句话',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: searching
                    ? IconButton(
                        tooltip: '清除',
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
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('关注')),
                  ButtonSegment(value: 1, label: Text('发现')),
                  ButtonSegment(value: 2, label: Text('同书')),
                ],
                selected: {_tabIndex},
                showSelectedIcon: false,
                onSelectionChanged: (value) => _changeTab(value.first),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => _load(quiet: true),
                    child: searching
                        ? _SearchResults(
                            loading: _searching,
                            books: _searchBooks,
                            posts: _searchPosts,
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
                                  title: '明台暂时没有打开',
                                  message: _error!,
                                  action: '再试一次',
                                  onAction: _load,
                                )
                              else if (_posts.isEmpty)
                                _FeedEmpty(
                                  tabIndex: _tabIndex,
                                  onCompose: _compose,
                                  onLogin: () => Navigator.of(
                                    context,
                                  ).pushNamed('/settings'),
                                )
                              else ...[
                                if (_tabIndex == 1 && _books.isNotEmpty)
                                  _CommunityBooksStrip(
                                    books: _books,
                                    onOpen: _openBook,
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
                                      onResonance: () =>
                                          _toggleResonance(index),
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

class CommunityBookScreen extends StatefulWidget {
  final String bookId;
  final CommunityBook? initialBook;

  const CommunityBookScreen({
    super.key,
    required this.bookId,
    this.initialBook,
  });

  @override
  State<CommunityBookScreen> createState() => _CommunityBookScreenState();
}

class _CommunityBookScreenState extends State<CommunityBookScreen> {
  CommunityBook? _book;
  List<CommunityPost> _posts = const [];
  List<CommunityReader> _readers = const [];
  bool _loading = true;
  bool _savingState = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _book = widget.initialBook;
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await _communityApi.getBook(widget.bookId);
      if (!mounted) return;
      setState(() {
        _book = result.book;
        _posts = result.posts;
        _readers = result.readers;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendly(error);
        _loading = false;
      });
    }
  }

  Future<void> _setStatus(String status) async {
    if (_savingState) return;
    await AuthService.init();
    if (!AuthService.isLoggedIn) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('登录后才能记录阅读状态')));
      return;
    }
    setState(() => _savingState = true);
    try {
      final next = _book?.viewerStatus == status ? 'none' : status;
      var isPrivate = true;
      if (next != 'none') {
        if (!mounted) return;
        final makePublic = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('谁可以看到这个阅读状态？'),
            content: const Text('默认只保存在你的账号中。只有主动公开后，其他同书读者才可能看见。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('仅自己可见'),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('公开给同书读者'),
              ),
            ],
          ),
        );
        if (makePublic == null) return;
        isPrivate = !makePublic;
        if (makePublic) {
          final current = await PrivacyService.getCommunityPrivacy();
          await PrivacyService.updateCommunityPrivacy({
            'show_reading_status': true,
            'show_reading_progress': current['show_reading_progress'] == true,
            'allow_follows': current['allow_follows'] != false,
            'appear_in_same_book': true,
          });
        }
      }
      await _communityApi.setBookState(
        widget.bookId,
        next,
        isPrivate: isPrivate,
      );
      await _load();
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _savingState = false);
    }
  }

  Future<void> _compose() async {
    final book = _book;
    if (book == null) return;
    final created = await showCommunityPostComposer(
      context,
      communityBook: book,
    );
    if (created == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    final palette = context.appPalette;
    return Scaffold(
      appBar: AppBar(title: const Text('公共书页')),
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
                                '${book.translator} 译',
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
                              '${book.finishedCount} 人读过 · ${book.readingCount} 人正在读',
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
                  if (book.description.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      book.description,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 15,
                        height: 1.75,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'want_to_read', label: Text('想读')),
                      ButtonSegment(value: 'reading', label: Text('在读')),
                      ButtonSegment(value: 'finished', label: Text('读过')),
                    ],
                    selected: book.viewerStatus.isEmpty
                        ? const <String>{}
                        : {book.viewerStatus},
                    emptySelectionAllowed: true,
                    showSelectedIcon: false,
                    onSelectionChanged:
                        _savingState ||
                            (book.viewerStatus.isEmpty &&
                                !AuthService.isLoggedIn)
                        ? (value) => _setStatus(value.first)
                        : (value) => _setStatus(value.first),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: palette.primaryLight.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      book.canRead
                          ? '这本书已具备明确的公开阅读授权。'
                          : '版权书籍在明台只展示书籍信息和读者原创内容。请在私人书架导入你合法获得的电子书继续阅读。',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                        height: 1.55,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  _SectionHeader(
                    title: '同书读者',
                    trailing: '${_readers.length} 位公开读者',
                  ),
                  const SizedBox(height: 12),
                  if (_readers.isEmpty)
                    const _InlineEmpty('还没有人公开自己的阅读状态。')
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
                    title: '大家最近在讨论',
                    action: '写下想法',
                    onAction: _compose,
                  ),
                  const SizedBox(height: 12),
                  if (_posts.isEmpty)
                    const _InlineEmpty('还没有人认真写下这本书带来的问题。')
                  else
                    ..._posts.map(
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
                          onComments: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => _CommunityCommentsSheet(post: post),
                          ).then((_) => _load()),
                          onResonance: () async {
                            await _communityApi.toggleResonance(post.id);
                            await _load();
                          },
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
        title: Text('拉黑 ${data.nickname}？'),
        content: const Text('双方将不再看到彼此的动态，也会自动取消关注关系。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认拉黑'),
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
        title: Text(_isMine ? '我的阅读档案' : '阅读档案'),
        actions: [
          if (_isMine)
            IconButton(
              tooltip: '编辑资料',
              onPressed: _editProfile,
              icon: const Icon(Icons.edit_outlined),
            ),
          if (!_isMine)
            PopupMenuButton<String>(
              tooltip: '更多',
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
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'report', child: Text('举报用户')),
                PopupMenuItem(value: 'block', child: Text('拉黑用户')),
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
                              data.bio.isEmpty ? '还没有写下一句话介绍。' : data.bio,
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
                          child: Text(_following ? '已关注' : '关注'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '${data.followerCount} 位读者关注 · 正在读 ${data.reading.length} 本',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 30),
                  _ProfileBookSection(title: '正在读', books: data.reading),
                  _ProfileBookSection(title: '读过', books: data.finished),
                  _ProfileBookSection(title: '想读', books: data.wantToRead),
                  const SizedBox(height: 8),
                  const _SectionHeader(title: '公开想法与讨论'),
                  const SizedBox(height: 12),
                  if (data.posts.isEmpty)
                    const _InlineEmpty('还没有公开留下阅读想法。')
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
                          onResonance: () async {
                            await _communityApi.toggleResonance(post.id);
                            await _load();
                          },
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
                  title: Text(_notificationTitle(item)),
                  subtitle: item.preview.isEmpty
                      ? Text(_timeLabel(item.createdAt))
                      : Text(
                          '${item.preview}\n${_timeLabel(item.createdAt)}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
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
  final VoidCallback onResonance;
  final VoidCallback? onDeleted;

  const CommunityPostCard({
    super.key,
    required this.post,
    required this.onBook,
    required this.onProfile,
    required this.onComments,
    required this.onResonance,
    this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.divider.withValues(alpha: 0.72)),
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
                        '${_postTypeLabel(post.postType)} · ${_timeLabel(post.createdAt)}',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '更多',
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
                      ? const [
                          PopupMenuItem(value: 'delete', child: Text('删除这条内容')),
                        ]
                      : const [
                          PopupMenuItem(value: 'report', child: Text('举报这条内容')),
                        ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (post.quotedText.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
              decoration: BoxDecoration(
                color: palette.primaryLight.withValues(alpha: 0.16),
                border: Border(
                  left: BorderSide(color: palette.primary, width: 2),
                ),
              ),
              child: Text(
                post.quotedText,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            post.content,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 15,
              height: 1.65,
            ),
          ),
          const SizedBox(height: 14),
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
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: onResonance,
                icon: Icon(
                  post.viewerResonated
                      ? Icons.auto_awesome
                      : Icons.auto_awesome_outlined,
                  size: 17,
                ),
                label: Text(
                  post.resonanceCount == 0
                      ? '共鸣'
                      : '${post.resonanceCount} 次共鸣',
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: onComments,
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                label: Text(
                  post.commentCount == 0 ? '讨论' : '${post.commentCount} 条讨论',
                ),
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
        title: const Text('删除这条公开内容？'),
        content: const Text('相关短摘录、评论和共鸣也会一起删除，且无法恢复。'),
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
    if (confirmed != true || !context.mounted) return;
    try {
      await _communityApi.deletePost(post.id);
      onDeleted?.call();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('公开内容已删除')));
      }
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }
}

class _CommunityPostComposer extends StatefulWidget {
  final Book? initialLocalBook;
  final CommunityBook? initialCommunityBook;

  const _CommunityPostComposer({
    this.initialLocalBook,
    this.initialCommunityBook,
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
  String _type = 'thought';
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
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
      setState(() => _error = '请先登录后再发布');
      return;
    }
    final content = _contentController.text.trim();
    if (content.length < 5) {
      setState(() => _error = '请至少写下 5 个字的完整想法');
      return;
    }
    if (_quoteController.text.trim().length > 240) {
      setState(() => _error = '公开摘录不能超过 240 个字符');
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
        if (local == null) throw Exception('请先选择一本书');
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
                    const Text(
                      '写下正在读的这一刻',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '只公开你主动写下的内容，不会上传电子书文件。',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (widget.initialCommunityBook != null)
                      _SelectedBookRow(book: widget.initialCommunityBook!)
                    else if (_localBooks.isEmpty)
                      const _InlineEmpty('私人书架还没有可关联的书。')
                    else
                      DropdownButtonFormField<Book>(
                        initialValue: _selectedLocalBook,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '关联书籍'),
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
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'thought', label: Text('想法')),
                        ButtonSegment(value: 'question', label: Text('问题')),
                        ButtonSegment(
                          value: 'reading_update',
                          label: Text('进度'),
                        ),
                      ],
                      selected: {_type},
                      showSelectedIcon: false,
                      onSelectionChanged: (value) =>
                          setState(() => _type = value.first),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _quoteController,
                      maxLines: 3,
                      maxLength: 240,
                      decoration: const InputDecoration(
                        labelText: '短摘录（可选）',
                        hintText: '只摘录讨论所需的一小段原文',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _contentController,
                      minLines: 5,
                      maxLines: 10,
                      maxLength: 4000,
                      decoration: const InputDecoration(
                        labelText: '你的想法或问题',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _chapterController,
                      maxLines: 1,
                      decoration: const InputDecoration(
                        labelText: '阅读位置（可选）',
                        hintText: '例如：第一卷 第三章',
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
                        label: Text(_submitting ? '正在发布…' : '发布到明台'),
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

  const _CommunityCommentsSheet({required this.post});

  @override
  State<_CommunityCommentsSheet> createState() =>
      _CommunityCommentsSheetState();
}

class _CommunityCommentsSheetState extends State<_CommunityCommentsSheet> {
  final _controller = TextEditingController();
  List<CommunityComment> _comments = const [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
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
      await _communityApi.createComment(widget.post.id, content);
      _controller.clear();
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
                                  Text(
                                    item.content,
                                    style: const TextStyle(height: 1.5),
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
              child: Row(
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
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  final bool loading;
  final List<CommunityBook> books;
  final List<CommunityPost> posts;
  final ValueChanged<CommunityBook> onOpenBook;
  final ValueChanged<String> onOpenProfile;
  final ValueChanged<CommunityPost> onOpenComments;

  const _SearchResults({
    required this.loading,
    required this.books,
    required this.posts,
    required this.onOpenBook,
    required this.onOpenProfile,
    required this.onOpenComments,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (books.isEmpty && posts.isEmpty) {
      return const Center(child: Text('明台还没有找到相关书页或讨论。'));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
      children: [
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
                onResonance: () {},
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CommunityBooksStrip extends StatelessWidget {
  final List<CommunityBook> books;
  final ValueChanged<CommunityBook> onOpen;

  const _CommunityBooksStrip({required this.books, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: '最近出现的书'),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: books.length,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final book = books[index];
                return InkWell(
                  onTap: () => onOpen(book),
                  child: SizedBox(
                    width: 78,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CommunityBookCover(book: book, width: 72, height: 102),
                        const SizedBox(height: 7),
                        Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, height: 1.25),
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
            ? Image.network(
                book.coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _coverFallback(palette),
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
          ? NetworkImage(imageUrl)
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

class _FeedEmpty extends StatelessWidget {
  final int tabIndex;
  final VoidCallback onCompose;
  final VoidCallback onLogin;

  const _FeedEmpty({
    required this.tabIndex,
    required this.onCompose,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    final loggedIn = AuthService.isLoggedIn;
    final title = switch (tabIndex) {
      0 => loggedIn ? '关注的人还没有留下新动态。' : '登录后查看关注的读者。',
      2 => loggedIn ? '你正在读的书还没有新讨论。' : '登录后查看同书读者。',
      _ => '明台还很安静。',
    };
    final message = switch (tabIndex) {
      0 => '关注一位读者后，她公开的阅读想法会出现在这里。',
      2 => '在公共书页标记“在读”，就能遇见读同一本书的人。',
      _ => '分享一本正在读的书，以及它让你停下来的问题。',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: _QuietMessage(
        icon: Icons.auto_stories_outlined,
        title: title,
        message: message,
        action: loggedIn ? '写下阅读动态' : '去登录',
        onAction: loggedIn ? onCompose : onLogin,
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

String _postTypeLabel(String type) => switch (type) {
  'question' => '提出了一个问题',
  'reading_update' => '更新了阅读进度',
  'excerpt' => '分享了一段摘录',
  _ => '写下了阅读想法',
};

String _timeLabel(DateTime? date) {
  if (date == null) return '';
  final difference = DateTime.now().difference(date);
  if (difference.inMinutes < 1) return '刚刚';
  if (difference.inHours < 1) return '${difference.inMinutes} 分钟前';
  if (difference.inDays < 1) return '${difference.inHours} 小时前';
  if (difference.inDays < 7) return '${difference.inDays} 天前';
  return '${date.month}月${date.day}日';
}

String _notificationTitle(CommunityNotification item) {
  return switch (item.eventType) {
    'follow' => '${item.actorNickname} 关注了你的阅读档案',
    'post_comment' => '${item.actorNickname} 回应了你的阅读想法',
    'post_resonance' => '${item.actorNickname} 与你的想法产生了共鸣',
    _ => '${item.actorNickname} 在明台留下了回应',
  };
}
