import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/book.dart';
import '../../providers/bookshelf_provider.dart';
import '../../providers/reader_provider.dart';
import '../../services/auth_service.dart';
import '../../services/book_service.dart';
import '../reader/reader_screen.dart';

class MingtaiScreen extends StatefulWidget {
  const MingtaiScreen({super.key});

  @override
  State<MingtaiScreen> createState() => _MingtaiScreenState();
}

class _MingtaiScreenState extends State<MingtaiScreen> {
  final Random _encounterRandom = Random();
  final TextEditingController _searchController = TextEditingController();
  MingtaiHomeData? _home;
  Timer? _prefetchTimer;
  Timer? _searchDebounce;
  int? _encounterIndex;
  String _searchQuery = '';
  List<MingtaiPublicBook> _remoteSearchBooks = const [];
  bool _searching = false;
  String? _searchError;
  bool _loading = false;
  bool _refreshing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final cached = forceRefresh
        ? null
        : BookService.cachedMingtaiHome() ??
              await BookService.restoreCachedMingtaiHome();
    final canShowCache = _home == null && cached != null;
    if (!mounted) return;
    final hasVisibleHome = _home != null || canShowCache;
    setState(() {
      if (canShowCache) _home = cached;
      _loading = !hasVisibleHome;
      _refreshing = hasVisibleHome;
      _error = null;
    });
    if (canShowCache) _schedulePrefetchVisibleBooks(cached);

    try {
      final home = await BookService.getMingtaiHome(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _home = home;
        _loading = false;
        _refreshing = false;
      });
      _schedulePrefetchVisibleBooks(home);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_home == null) _error = e.toString();
        _loading = false;
        _refreshing = false;
      });
    }
  }

  void _schedulePrefetchVisibleBooks(MingtaiHomeData home) {
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      _prefetchVisibleBooks(home);
    });
  }

  void _prefetchVisibleBooks(MingtaiHomeData home) {
    final prefetchedIds = <String>{};
    for (final book in [...home.readingNow, ...home.latestBooks]) {
      if (!BookService.canReadMingtaiBook(book) ||
          !prefetchedIds.add(book.id)) {
        continue;
      }
      unawaited(BookService.prefetchMingtaiBookChapters(book));
      if (prefetchedIds.isNotEmpty) return;
    }
  }

  @override
  void dispose() {
    _prefetchTimer?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    _searchDebounce?.cancel();
    setState(() {
      _searchQuery = value;
      _searchError = null;
      if (query.isEmpty) {
        _remoteSearchBooks = const [];
        _searching = false;
      } else {
        _searching = true;
      }
    });
    if (query.isEmpty) return;
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      _runRemoteSearch(query);
    });
  }

  Future<void> _runRemoteSearch(String query) async {
    try {
      final books = await BookService.getMingtaiBooks(
        limit: 30,
        forceRefresh: true,
        search: query,
      );
      if (!mounted || _searchQuery.trim() != query) return;
      setState(() {
        _remoteSearchBooks = books
            .where(BookService.canReadMingtaiBook)
            .toList(growable: false);
        _searching = false;
      });
    } catch (e) {
      if (!mounted || _searchQuery.trim() != query) return;
      setState(() {
        _searchError = e.toString();
        _searching = false;
      });
    }
  }

  Future<void> _openPublishSheet() async {
    final published = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PublishBookSheet(),
    );
    if (published == true && mounted) {
      _load(forceRefresh: true);
    }
  }

  Future<void> _openBookById(
    String bookId, {
    MingtaiPublicBook? initialBook,
  }) async {
    if (bookId.isEmpty) return;
    final deletedBookId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => MingtaiBookDetailScreen(
          bookId: bookId,
          initialBook: initialBook ?? _findBook(bookId),
        ),
      ),
    );
    if (deletedBookId != null && mounted) {
      await _load(forceRefresh: true);
    }
  }

  void _openFullShelf(List<MingtaiPublicBook> books) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MingtaiShelfScreen(initialBooks: books),
      ),
    );
  }

  MingtaiPublicBook? _findBook(String bookId) {
    final home = _home;
    if (home == null) return null;
    for (final book in [
      ...home.readingNow,
      ...home.latestBooks,
      ...home.recentDiscussions.map((item) => item.book),
    ]) {
      if (book.id == bookId) return book;
    }
    return null;
  }

  List<MingtaiPublicBook> _allHomeBooks(MingtaiHomeData home) {
    final seen = <String>{};
    final books = <MingtaiPublicBook>[];
    for (final book in [
      ...home.readingNow,
      ...home.latestBooks,
      ...home.recentDiscussions.map((item) => item.book),
      ...home.recentThoughts.map(_bookFromTrace),
      ...home.encounterPool.map(_bookFromMoment),
      if (home.todayPage != null) _bookFromMoment(home.todayPage!),
    ]) {
      if (book.id.isEmpty || !seen.add(book.id)) continue;
      books.add(book);
    }
    return books;
  }

  MingtaiPublicBook _bookFromTrace(MingtaiFeedItem item) {
    return MingtaiPublicBook(
      id: item.bookId,
      uploaderUserId: '',
      sourceBookId: '',
      title: item.bookTitle,
      author: item.bookAuthor,
      coverUrl: item.bookCover,
      fileUrl: '',
      storagePath: '',
      fileType: 'epub',
      fileSize: 0,
      chapterCount: 0,
      description: '',
      authoritativeDescription: '',
      authoritativeDescriptionSource: '',
      authoritativeDescriptionUrl: '',
      oneLineSummary: '',
      oneLineSummarySource: '',
      encounterSummary: '',
      expandedGuide: '',
      readingThemes: const [],
      copyrightStatus: '',
      borrowCount: 0,
      readingCount: 0,
      annotationCount: 0,
      recentDiscussionCount: 0,
      createdAt: null,
    );
  }

  MingtaiPublicBook _bookFromMoment(MingtaiPageMoment moment) {
    return MingtaiPublicBook(
      id: moment.publicBookId,
      uploaderUserId: '',
      sourceBookId: '',
      title: moment.bookTitle,
      author: moment.bookAuthor,
      coverUrl: moment.bookCover,
      fileUrl: '',
      storagePath: '',
      fileType: 'epub',
      fileSize: 0,
      chapterCount: 0,
      description: '',
      authoritativeDescription: '',
      authoritativeDescriptionSource: '',
      authoritativeDescriptionUrl: '',
      oneLineSummary: moment.bookOneLineSummary,
      oneLineSummarySource: '',
      encounterSummary: '',
      expandedGuide: '',
      readingThemes: const [],
      copyrightStatus: '',
      borrowCount: 0,
      readingCount: 0,
      annotationCount: 0,
      recentDiscussionCount: 0,
      createdAt: null,
    );
  }

  List<MingtaiPublicBook> _shelfBooks(MingtaiHomeData home) {
    final seen = <String>{};
    final books = <MingtaiPublicBook>[];
    for (final book in _allHomeBooks(home)) {
      if (book.id.isEmpty || !seen.add(book.id)) continue;
      if (!BookService.canReadMingtaiBook(book)) continue;
      books.add(book);
    }
    return books;
  }

  List<MingtaiPublicBook> _encounterCandidates(MingtaiHomeData home) {
    return _shelfBooks(home);
  }

  MingtaiPageMoment _momentFromBook(MingtaiPublicBook book) {
    final summary = book.oneLineSummary.trim();
    return MingtaiPageMoment(
      id: 'book:${book.id}',
      publicBookId: book.id,
      source: 'book',
      text: summary.isNotEmpty ? summary : '也许可以从这本书开始。',
      annotationText: '',
      chapterIndex: '',
      chapterTitle: '',
      bookTitle: book.title,
      bookAuthor: book.author,
      bookCover: book.coverUrl,
      bookOneLineSummary: summary,
    );
  }

  MingtaiPageMoment _momentFromTrace(MingtaiFeedItem item) {
    return MingtaiPageMoment(
      id: 'trace:${item.id}',
      publicBookId: item.bookId,
      source: item.source,
      text: _traceDisplayText(item),
      annotationText: item.annotationText,
      chapterIndex: item.chapterIndex,
      chapterTitle: item.chapterTitle,
      bookTitle: item.bookTitle,
      bookAuthor: item.bookAuthor,
      bookCover: item.bookCover,
      bookOneLineSummary: '',
    );
  }

  List<MingtaiFeedItem> _qualityThoughts(MingtaiHomeData home) {
    return home.recentThoughts.where((item) {
      return _isMeaningfulPublicText(_traceDisplayText(item));
    }).toList();
  }

  List<MingtaiPageMoment> _searchMomentResults(
    MingtaiHomeData home,
    String query,
  ) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final seen = <String>{};
    final results = <MingtaiPageMoment>[];
    for (final moment in [
      ..._qualityThoughts(home).map(_momentFromTrace),
      ..._encounterCandidates(home)
          .map(_momentFromBook)
          .where((moment) => _isMeaningfulPublicText(moment.text)),
    ]) {
      final haystack = [
        moment.text,
        moment.annotationText,
        moment.bookTitle,
        moment.bookAuthor,
        moment.chapterTitle,
      ].join(' ').toLowerCase();
      if (!haystack.contains(q)) continue;
      final key = '${moment.publicBookId}:${moment.id}';
      if (!seen.add(key)) continue;
      results.add(moment);
      if (results.length >= 6) break;
    }
    return results;
  }

  List<MingtaiPublicBook> _searchBookResults(
    MingtaiHomeData home,
    String query,
  ) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _shelfBooks(home)
        .where((book) {
          final haystack = [
            book.title,
            book.author,
            book.oneLineSummary,
            book.encounterSummary,
            book.description,
          ].join(' ').toLowerCase();
          return haystack.contains(q);
        })
        .take(8)
        .toList();
  }

  List<MingtaiPublicBook> _mergeBookResults(
    List<MingtaiPublicBook> primary,
    List<MingtaiPublicBook> fallback,
  ) {
    final seen = <String>{};
    final results = <MingtaiPublicBook>[];
    for (final book in [...primary, ...fallback]) {
      if (book.id.isEmpty || !seen.add(book.id)) continue;
      results.add(book);
    }
    return results;
  }

  MingtaiPublicBook? _currentEncounter(List<MingtaiPublicBook> candidates) {
    final index = _encounterIndex;
    if (index == null || candidates.isEmpty) return null;
    return candidates[index % candidates.length];
  }

  void _drawEncounter(List<MingtaiPublicBook> candidates) {
    if (candidates.isEmpty) return;
    setState(() {
      if (candidates.length == 1) {
        _encounterIndex = 0;
        return;
      }
      final current = _encounterIndex;
      var next = _encounterRandom.nextInt(candidates.length);
      if (current != null && next == current % candidates.length) {
        next = (next + 1) % candidates.length;
      }
      _encounterIndex = next;
    });
  }

  bool _isQuiet(MingtaiHomeData home) {
    return _shelfBooks(home).isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final home = _home;
    final shelfBooks = home == null
        ? const <MingtaiPublicBook>[]
        : _shelfBooks(home);
    final encounterCandidates = home == null
        ? const <MingtaiPublicBook>[]
        : _encounterCandidates(home);
    final encounterBook = _currentEncounter(encounterCandidates);
    final searchMomentResults = home == null
        ? const <MingtaiPageMoment>[]
        : _searchMomentResults(home, _searchQuery);
    final localSearchBookResults = home == null
        ? const <MingtaiPublicBook>[]
        : _searchBookResults(home, _searchQuery);
    final hasSearch = _searchQuery.trim().isNotEmpty;
    final searchBookResults = hasSearch
        ? _mergeBookResults(_remoteSearchBooks, localSearchBookResults)
        : localSearchBookResults;

    return Scaffold(
      appBar: AppBar(
        title: const Text('明台'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file_outlined),
            tooltip: '发布到明台',
            onPressed: _openPublishSheet,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_refreshing) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _load(forceRefresh: true),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
                      children: [
                        _MingtaiSearchField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                        ),
                        if (_error != null)
                          _QuietError(
                            message: _error!,
                            onRetry: () => _load(forceRefresh: true),
                          )
                        else if (home == null || _isQuiet(home))
                          const _QuietEmpty()
                        else if (hasSearch)
                          _MingtaiSearchResultsSection(
                            books: searchBookResults,
                            moments: searchMomentResults,
                            loading: _searching,
                            error: _searchError,
                            onOpenBook: (book) =>
                                _openBookById(book.id, initialBook: book),
                            onOpenMoment: (moment) =>
                                _openBookById(moment.publicBookId),
                          )
                        else ...[
                          _TodayEncounterCard(
                            book: encounterBook,
                            canDraw: encounterCandidates.isNotEmpty,
                            onDraw: () => _drawEncounter(encounterCandidates),
                            onShuffle: () =>
                                _drawEncounter(encounterCandidates),
                            onOpen: encounterBook == null
                                ? null
                                : () => _openBookById(
                                    encounterBook.id,
                                    initialBook: encounterBook,
                                  ),
                          ),
                          if (shelfBooks.isNotEmpty)
                            _MingtaiShelfSection(
                              books: shelfBooks.take(6).toList(),
                              onBookTap: (book) =>
                                  _openBookById(book.id, initialBook: book),
                              onViewAll: () => _openFullShelf(shelfBooks),
                            ),
                          const SizedBox(height: 12),
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

class MingtaiShelfScreen extends StatefulWidget {
  final List<MingtaiPublicBook> initialBooks;

  const MingtaiShelfScreen({super.key, this.initialBooks = const []});

  @override
  State<MingtaiShelfScreen> createState() => _MingtaiShelfScreenState();
}

class _MingtaiShelfScreenState extends State<MingtaiShelfScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<MingtaiPublicBook> _books = const [];
  bool _loading = true;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _books = _readableUnique(widget.initialBooks);
    _loading = _books.isEmpty;
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (_books.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final books = await BookService.getMingtaiBooks(
        limit: 100,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _books = _readableUnique(books);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_books.isEmpty) _error = e.toString();
      });
    }
  }

  List<MingtaiPublicBook> _readableUnique(Iterable<MingtaiPublicBook> source) {
    final seen = <String>{};
    return source
        .where(
          (book) =>
              book.id.isNotEmpty &&
              seen.add(book.id) &&
              BookService.canReadMingtaiBook(book),
        )
        .toList();
  }

  List<MingtaiPublicBook> get _visibleBooks {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _books;
    return _books.where((book) {
      return book.title.toLowerCase().contains(query) ||
          book.author.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _openBook(MingtaiPublicBook book) async {
    final deletedBookId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            MingtaiBookDetailScreen(bookId: book.id, initialBook: book),
      ),
    );
    if (deletedBookId != null && mounted) {
      setState(() {
        _books = _books.where((item) => item.id != deletedBookId).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final books = _visibleBooks;
    return Scaffold(
      appBar: AppBar(title: const Text('明台书架')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '找一本书或作者',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空搜索',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close, size: 18),
                      ),
                filled: true,
                fillColor: palette.card.withAlpha(220),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      _QuietError(
                        message: _error!,
                        onRetry: () => _load(forceRefresh: true),
                      ),
                    ],
                  )
                : RefreshIndicator(
                    onRefresh: () => _load(forceRefresh: true),
                    child: books.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.fromLTRB(28, 100, 28, 40),
                            children: [
                              Text(
                                _books.isEmpty
                                    ? '明台书架暂时还没有可阅读的书。'
                                    : '没有找到相关书籍。',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
                            itemCount: books.length,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 14,
                                  childAspectRatio: 0.58,
                                ),
                            itemBuilder: (_, index) {
                              final book = books[index];
                              return _MingtaiShelfBookCard(
                                book: book,
                                onTap: () => _openBook(book),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class MingtaiProfileScreen extends StatefulWidget {
  final String? userId;

  const MingtaiProfileScreen({super.key, this.userId});

  @override
  State<MingtaiProfileScreen> createState() => _MingtaiProfileScreenState();
}

class _MingtaiProfileScreenState extends State<MingtaiProfileScreen> {
  MingtaiPublicProfile? _profile;
  int _unreadEchoCount = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isMe => widget.userId == null || widget.userId!.isEmpty;

  @override
  void initState() {
    super.initState();
    _load();
    if (_isMe) unawaited(_loadUnreadEchoCount());
  }

  Future<void> _loadUnreadEchoCount() async {
    try {
      final count = await BookService.getMingtaiUnreadNotificationCount();
      if (mounted) setState(() => _unreadEchoCount = count);
    } catch (_) {}
  }

  Future<void> _openEchoes() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MingtaiEchoScreen()));
    if (mounted) unawaited(_loadUnreadEchoCount());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = _isMe
          ? await BookService.getMingtaiMyProfile()
          : await BookService.getMingtaiPublicProfile(widget.userId!);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _editProfile() async {
    final current = _profile?.profile;
    if (current == null || _saving) return;
    final result = await showDialog<_ProfileEditResult>(
      context: context,
      builder: (_) => _ProfileEditDialog(profile: current),
    );
    if (result == null) return;

    setState(() => _saving = true);
    try {
      final updated = result.avatarBytes == null
          ? await BookService.updateMingtaiMyProfile(
              nickname: result.nickname,
              avatarUrl: result.avatarUrl,
              bio: result.bio,
            )
          : await BookService.uploadMingtaiProfileAvatar(
              bytes: result.avatarBytes!,
              fileName: result.avatarFileName,
              mimeType: result.avatarMimeType,
              nickname: result.nickname,
              bio: result.bio,
            );
      if (!mounted) return;
      final old = _profile;
      setState(() {
        _profile = old == null
            ? null
            : MingtaiPublicProfile(
                profile: updated,
                publicBooks: old.publicBooks,
                publicThoughts: old.publicThoughts,
                publicReviews: old.publicReviews,
                mingtaiStops: old.mingtaiStops,
                recentBooks: old.recentBooks,
                reviews: old.reviews,
                annotations: old.annotations,
              );
        _saving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('阅读档案已更新')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  Future<void> _editReview(MingtaiBookReview review) async {
    if (_saving) return;
    final content = await showDialog<String>(
      context: context,
      builder: (_) => _BookReviewDialog(
        initialContent: review.content,
        title: '修改短评',
        submitLabel: '保存修改',
        cancelLabel: '取消',
      ),
    );
    if (content == null || content.trim().isEmpty) return;
    if (!_isMeaningfulPublicText(content)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('短评至少需要 10 个字，并且不能是测试内容')));
      return;
    }

    setState(() => _saving = true);
    try {
      await BookService.updateMingtaiBookReview(
        reviewId: review.id,
        content: content.trim(),
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('短评已更新')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('修改失败：$e')));
    }
  }

  Future<void> _deleteReview(MingtaiBookReview review) async {
    if (_saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条短评？'),
        content: const Text('删除后，它将不再出现在这本书和你的公开阅读档案里。'),
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
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await BookService.deleteMingtaiBookReview(review);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('短评已删除')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }

  Future<void> _openBook(MingtaiPublicBook book) async {
    final deletedBookId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            MingtaiBookDetailScreen(bookId: book.id, initialBook: book),
      ),
    );
    if (deletedBookId != null && mounted) await _load();
  }

  MingtaiPublicBook _bookFromAnnotation(MingtaiFeedItem item) {
    return MingtaiPublicBook(
      id: item.bookId,
      uploaderUserId: '',
      sourceBookId: '',
      title: item.bookTitle,
      author: item.bookAuthor,
      coverUrl: item.bookCover,
      fileUrl: '',
      storagePath: '',
      fileType: 'epub',
      fileSize: 0,
      chapterCount: 0,
      description: '',
      authoritativeDescription: '',
      authoritativeDescriptionSource: '',
      authoritativeDescriptionUrl: '',
      oneLineSummary: '',
      oneLineSummarySource: '',
      encounterSummary: '',
      expandedGuide: '',
      readingThemes: const [],
      copyrightStatus: '',
      borrowCount: 0,
      readingCount: 0,
      annotationCount: 0,
      recentDiscussionCount: 0,
      createdAt: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isMe ? '我的阅读档案' : '阅读档案'),
        actions: [
          if (_isMe)
            _EchoIconButton(
              unreadCount: _unreadEchoCount,
              onPressed: _openEchoes,
            ),
          if (_isMe && profile != null)
            TextButton(
              onPressed: _saving ? null : _editProfile,
              child: Text(_saving ? '保存中' : '编辑资料'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ListView(
              padding: const EdgeInsets.all(18),
              children: [_QuietError(message: _error!, onRetry: _load)],
            )
          : profile == null
          ? const Center(child: Text('阅读档案暂时没有打开'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 34),
              children: [
                _ProfileHeaderCard(
                  profile: profile.profile,
                  isMe: _isMe,
                  onEdit: _editProfile,
                ),
                const SizedBox(height: 18),
                _ProfileStatsRow(profile: profile),
                if (profile.recentBooks.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  const _SectionTitle(title: '最近阅读'),
                  const SizedBox(height: 12),
                  _BookRail(books: profile.recentBooks, onTap: _openBook),
                ],
                const SizedBox(height: 24),
                const _SectionTitle(title: '公开短评'),
                const SizedBox(height: 12),
                if (profile.reviews.isEmpty)
                  _ProfileEmptyText(
                    text: _isMe ? '你还没有把读后感留在明台。' : 'TA 还没有公开短评。',
                  )
                else
                  ...profile.reviews
                      .take(8)
                      .map(
                        (review) => _ProfileReviewCard(
                          review: review,
                          canManage: _isMe,
                          onEdit: () => _editReview(review),
                          onDelete: () => _deleteReview(review),
                        ),
                      ),
                const SizedBox(height: 24),
                const _SectionTitle(title: '公开想法'),
                const SizedBox(height: 12),
                if (profile.annotations.isEmpty)
                  _ProfileEmptyText(
                    text: _isMe ? '你还没有公开阅读想法。' : 'TA 还没有公开阅读想法。',
                  )
                else
                  ...profile.annotations
                      .take(8)
                      .map(
                        (item) => _ThoughtPreviewCard(
                          item: item,
                          onTap: () => _openBook(_bookFromAnnotation(item)),
                        ),
                      ),
                const SizedBox(height: 12),
                Text(
                  '这里只展示公开短评、公开想法和公开阅读痕迹。私密随心记、小U对话和未公开记录不会出现在这里。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ],
            ),
    );
  }
}

class MingtaiEchoScreen extends StatefulWidget {
  const MingtaiEchoScreen({super.key});

  @override
  State<MingtaiEchoScreen> createState() => _MingtaiEchoScreenState();
}

class _MingtaiEchoScreenState extends State<MingtaiEchoScreen> {
  List<MingtaiNotification> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final items = await BookService.listMingtaiNotifications();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    await BookService.markAllMingtaiNotificationsRead();
    if (!mounted) return;
    setState(() {
      _items = _items
          .map(
            (item) => MingtaiNotification(
              id: item.id,
              eventType: item.eventType,
              targetType: item.targetType,
              targetId: item.targetId,
              publicBookId: item.publicBookId,
              bookTitle: item.bookTitle,
              bookAuthor: item.bookAuthor,
              bookCover: item.bookCover,
              preview: item.preview,
              actor: item.actor,
              readAt: item.readAt ?? DateTime.now(),
              createdAt: item.createdAt,
            ),
          )
          .toList();
    });
  }

  Future<void> _open(MingtaiNotification item) async {
    if (!item.isRead) {
      try {
        await BookService.markMingtaiNotificationRead(item.id);
      } catch (_) {}
    }
    if (!mounted || item.publicBookId.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MingtaiBookDetailScreen(bookId: item.publicBookId),
      ),
    );
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final hasUnread = _items.any((item) => !item.isRead);
    return Scaffold(
      appBar: AppBar(
        title: const Text('收到的回声'),
        actions: [
          if (hasUnread)
            TextButton(onPressed: _markAllRead, child: const Text('全部读过')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ListView(
              padding: const EdgeInsets.all(18),
              children: [_QuietError(message: _error!, onRetry: _load)],
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(28, 120, 28, 40),
                      children: [
                        Icon(
                          Icons.waves_outlined,
                          size: 42,
                          color: palette.illustration,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '还没有新的回声',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '有人回应你的公开想法或短评时，会安静地留在这里。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 13,
                            height: 1.6,
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 34),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, index) {
                        final item = _items[index];
                        return _EchoCard(item: item, onTap: () => _open(item));
                      },
                    ),
            ),
    );
  }
}

class _EchoIconButton extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onPressed;

  const _EchoIconButton({required this.unreadCount, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: '收到的回声',
          onPressed: onPressed,
          icon: const Icon(Icons.waves_outlined),
        ),
        if (unreadCount > 0)
          Positioned(
            right: 7,
            top: 8,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: palette.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

class _EchoCard extends StatelessWidget {
  final MingtaiNotification item;
  final VoidCallback onTap;

  const _EchoCard({required this.item, required this.onTap});

  String get _actionText {
    switch (item.eventType) {
      case 'annotation_comment':
        return '回应了你的公开想法';
      case 'annotation_resonance':
        return '在你的公开想法旁停留过';
      case 'review_comment':
        return '回应了你的读者短评';
      case 'review_resonance':
        return '与你的读者短评产生了共鸣';
      default:
        return '留下了一点回声';
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 15),
        decoration: BoxDecoration(
          color: item.isRead
              ? palette.card.withAlpha(205)
              : palette.primaryLight.withAlpha(70),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.divider.withAlpha(110)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileAvatar(profile: item.actor, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                      children: [
                        TextSpan(
                          text: item.actor.nickname,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(text: ' $_actionText'),
                      ],
                    ),
                  ),
                  if (item.preview.trim().isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      item.preview.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 7),
                  Text(
                    [
                      if (item.bookTitle.isNotEmpty) '《${item.bookTitle}》',
                      _dateLabel(item.createdAt),
                    ].join(' · '),
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
          ],
        ),
      ),
    );
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  final MingtaiUserProfile profile;
  final bool isMe;
  final VoidCallback onEdit;

  const _ProfileHeaderCard({
    required this.profile,
    required this.isMe,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.divider.withAlpha(120)),
      ),
      child: Row(
        children: [
          _ProfileAvatar(profile: profile, size: 58),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  profile.bio.isEmpty ? '还没有写下一句话介绍。' : profile.bio,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          if (isMe)
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑资料',
            ),
        ],
      ),
    );
  }
}

class _ProfileStatsRow extends StatelessWidget {
  final MingtaiPublicProfile profile;

  const _ProfileStatsRow({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ProfileStat(value: profile.publicBooks, label: '公开书页'),
        _ProfileStat(value: profile.publicThoughts, label: '公开想法'),
        _ProfileStat(value: profile.publicReviews, label: '公开短评'),
        _ProfileStat(value: profile.mingtaiStops, label: '明台停留'),
      ],
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final int value;
  final String label;

  const _ProfileStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ProfileReviewCard extends StatelessWidget {
  final MingtaiBookReview review;
  final bool canManage;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _ProfileReviewCard({
    required this.review,
    this.canManage = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      decoration: BoxDecoration(
        color: palette.card.withAlpha(235),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: palette.divider.withAlpha(120)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  review.content,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 14,
                    height: 1.65,
                  ),
                ),
              ),
              if (canManage)
                PopupMenuButton<String>(
                  tooltip: '管理短评',
                  icon: Icon(
                    Icons.more_horiz,
                    size: 20,
                    color: palette.textSecondary,
                  ),
                  onSelected: (value) {
                    if (value == 'edit') onEdit?.call();
                    if (value == 'delete') onDelete?.call();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('修改')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '《${review.bookTitle}》 · ${_dateLabel(review.createdAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ProfileEmptyText extends StatelessWidget {
  final String text;

  const _ProfileEmptyText({required this.text});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: palette.textSecondary,
          fontSize: 13,
          height: 1.6,
        ),
      ),
    );
  }
}

class _ProfileEditResult {
  final String nickname;
  final String avatarUrl;
  final String bio;
  final Uint8List? avatarBytes;
  final String avatarFileName;
  final String avatarMimeType;

  const _ProfileEditResult({
    required this.nickname,
    required this.avatarUrl,
    required this.bio,
    this.avatarBytes,
    this.avatarFileName = 'avatar.jpg',
    this.avatarMimeType = 'image/jpeg',
  });
}

class _ProfileEditDialog extends StatefulWidget {
  final MingtaiUserProfile profile;

  const _ProfileEditDialog({required this.profile});

  @override
  State<_ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<_ProfileEditDialog> {
  late final TextEditingController _nicknameController;
  late final TextEditingController _avatarController;
  late final TextEditingController _bioController;
  Uint8List? _pickedAvatarBytes;
  String _pickedAvatarName = 'avatar.jpg';
  String _pickedAvatarMimeType = 'image/jpeg';

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.profile.nickname);
    _avatarController = TextEditingController(text: widget.profile.avatarUrl);
    _bioController = TextEditingController(text: widget.profile.bio);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _avatarController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 58,
        maxWidth: 420,
        maxHeight: 420,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      final mimeType = image.mimeType ?? _mimeTypeFromName(image.name);
      if (bytes.length > 900 * 1024) {
        messenger.showSnackBar(
          const SnackBar(content: Text('头像图片仍然有点大，请换一张更小的图片')),
        );
        return;
      }
      setState(() {
        _pickedAvatarBytes = bytes;
        _pickedAvatarName = image.name.isEmpty ? 'avatar.jpg' : image.name;
        _pickedAvatarMimeType = mimeType;
      });
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('选择头像失败：$error')));
    }
  }

  String _mimeTypeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return AlertDialog(
      title: const Text('编辑阅读档案'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 74,
                      height: 74,
                      child: _pickedAvatarBytes != null
                          ? Image.memory(_pickedAvatarBytes!, fit: BoxFit.cover)
                          : _ProfileAvatar(profile: widget.profile, size: 74),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: palette.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: palette.card, width: 2),
                    ),
                    child: const Icon(
                      Icons.photo_camera_outlined,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _pickAvatar, child: const Text('从相册选择头像')),
            const SizedBox(height: 8),
            TextField(
              controller: _nicknameController,
              decoration: const InputDecoration(labelText: '昵称'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _avatarController,
              decoration: const InputDecoration(labelText: '头像 URL'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _bioController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: '一句话介绍'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              _ProfileEditResult(
                nickname: _nicknameController.text.trim(),
                avatarUrl: _avatarController.text.trim(),
                bio: _bioController.text.trim(),
                avatarBytes: _pickedAvatarBytes,
                avatarFileName: _pickedAvatarName,
                avatarMimeType: _pickedAvatarMimeType,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class MingtaiBookDetailScreen extends StatefulWidget {
  final String bookId;
  final MingtaiPublicBook? initialBook;

  const MingtaiBookDetailScreen({
    super.key,
    required this.bookId,
    this.initialBook,
  });

  @override
  State<MingtaiBookDetailScreen> createState() =>
      _MingtaiBookDetailScreenState();
}

class _MingtaiBookDetailScreenState extends State<MingtaiBookDetailScreen> {
  MingtaiBookDetail? _detail;
  List<MingtaiBookReview> _reviews = [];
  bool _descriptionExpanded = false;
  bool _hasReadingProgress = false;
  bool _loading = true;
  bool _loadingReviews = false;
  bool _startingReading = false;
  bool _borrowing = false;
  bool _submittingReview = false;
  bool _deletingBook = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(
      AuthService.init().then((_) {
        if (mounted) setState(() {});
      }),
    );
    final initialBook = widget.initialBook;
    if (initialBook != null) {
      _detail = MingtaiBookDetail(book: initialBook, annotations: const []);
      _loading = false;
      unawaited(BookService.prefetchMingtaiBookChapters(initialBook));
      unawaited(_loadReadingProgress(initialBook));
      unawaited(_loadReviews());
    }
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = _detail == null;
      _error = null;
    });
    try {
      final detail = await BookService.getMingtaiBookDetail(
        widget.bookId,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
      unawaited(BookService.prefetchMingtaiBookChapters(detail.book));
      unawaited(_loadReadingProgress(detail.book));
      unawaited(_loadReviews());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadReviews() async {
    final detail = _detail;
    if (detail == null || _loadingReviews) return;
    setState(() => _loadingReviews = true);
    try {
      final reviews = await BookService.listMingtaiBookReviews(detail.book.id);
      if (!mounted) return;
      setState(() {
        _reviews = reviews.where(_isMeaningfulReview).toList();
        _loadingReviews = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingReviews = false);
    }
  }

  bool _isMeaningfulReview(MingtaiBookReview review) {
    return _isMeaningfulPublicText(review.content);
  }

  void _openProfile(String userId) {
    if (userId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MingtaiProfileScreen(userId: userId)),
    );
  }

  bool get _canDeleteCurrentBook {
    final uploaderUserId = _detail?.book.uploaderUserId.trim() ?? '';
    final currentUserId = AuthService.userId?.trim() ?? '';
    return uploaderUserId.isNotEmpty &&
        currentUserId.isNotEmpty &&
        uploaderUserId == currentUserId;
  }

  Future<void> _deleteCurrentBook() async {
    final book = _detail?.book;
    if (book == null || _deletingBook || !_canDeleteCurrentBook) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('从明台删除这本书？'),
        content: Text(
          '《${book.title}》的公共文件、章节缓存、公开痕迹和短评都会一并删除。\n\n你本地书架里的原始书籍不会受到影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingBook = true);
    try {
      await BookService.deleteMyMingtaiBook(book.id);
      if (!mounted) return;
      Navigator.of(context).pop<String>(book.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingBook = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }

  Future<void> _showReviewDialog() async {
    final detail = _detail;
    if (detail == null || _submittingReview) return;
    await AuthService.init();
    if (!mounted) return;
    if (!AuthService.isLoggedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先登录后再留下短评')));
      return;
    }

    final content = await showDialog<String>(
      context: context,
      builder: (_) => const _BookReviewDialog(),
    );
    if (content == null || content.trim().isEmpty) return;
    if (!_isMeaningfulPublicText(content)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('短评至少需要 10 个字，并且不能是测试内容')));
      return;
    }

    setState(() => _submittingReview = true);
    try {
      final review = await BookService.createMingtaiBookReview(
        bookId: detail.book.id,
        content: content.trim(),
      );
      if (!mounted) return;
      setState(() {
        _reviews = [review, ..._reviews.where((item) => item.id != review.id)];
        _submittingReview = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('短评已留在明台')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _submittingReview = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('短评发布失败：$e')));
    }
  }

  Future<void> _loadReadingProgress(MingtaiPublicBook book) async {
    try {
      final shelfBookId = BookService.publicShelfBookId(book.id);
      final progress = await BookService.getReadingProgress(shelfBookId);
      if (!mounted || _detail?.book.id != book.id) return;
      final chapter = int.tryParse(progress?.chapterIndex ?? '') ?? 0;
      final offset = progress?.scrollOffset ?? 0;
      setState(() {
        _hasReadingProgress = chapter > 0 || offset > 8;
      });
    } catch (_) {}
  }

  Future<void> _borrow() async {
    final book = _detail?.book;
    if (book == null || _borrowing) return;
    final bookshelfProvider = context.read<BookshelfProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _borrowing = true);
    try {
      await BookService.borrowMingtaiBook(book);
      if (!mounted) return;
      await bookshelfProvider.loadBooks();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('已借阅到书架'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('借阅失败：$e'), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _borrowing = false);
    }
  }

  Future<void> _startReading() async {
    final book = _detail?.book;
    if (book == null || _startingReading) return;
    if (!BookService.canReadMingtaiBook(book)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('这本明台书缺少可阅读内容，请从书架重新发布覆盖'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _startingReading = true);
    try {
      unawaited(BookService.recordMingtaiBookRead(book.id));
      final readerBook = BookService.readableBookFromMingtai(book);
      final readerProvider = context.read<ReaderProvider>();
      unawaited(readerProvider.openBook(readerBook));
      if (!mounted) return;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ReaderScreen()));
    } finally {
      if (mounted) setState(() => _startingReading = false);
    }
  }

  List<MingtaiFeedItem> _thoughts(MingtaiBookDetail detail) {
    final items = detail.annotations
        .where((item) => item.source == 'thought' || item.source == 'manual')
        .toList();
    items.sort(_byRecentTrace);
    return items;
  }

  List<MingtaiFeedItem> _recentTraces(MingtaiBookDetail detail) {
    return _thoughts(detail);
  }

  int _sharedStopCount(MingtaiBookDetail detail) {
    final annotationCount = detail.book.annotationCount;
    final localCount = detail.annotations.length;
    final count = annotationCount > localCount ? annotationCount : localCount;
    return count;
  }

  int _byRecentTrace(MingtaiFeedItem a, MingtaiFeedItem b) {
    final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bTime.compareTo(aTime);
  }

  int _discussionCount(MingtaiBookDetail detail) {
    final fromBook = detail.book.recentDiscussionCount;
    final fromItems = detail.annotations.fold<int>(
      0,
      (sum, item) => sum + item.commentCount,
    );
    return fromBook > fromItems ? fromBook : fromItems;
  }

  void _openTraceSheet(MingtaiFeedItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _InteractionDetailSheet(
        targetType: 'annotation',
        targetId: item.id,
        title: item.chapterTitle.isEmpty ? '公开想法' : item.chapterTitle,
        body: item.originalText.trim().isEmpty
            ? _traceMainText(item)
            : item.originalText.trim(),
        secondaryText: item.annotationText.trim(),
        initialResonanceCount: item.resonanceCount,
        initialCommentCount: item.commentCount,
        onChanged: () => unawaited(_load(forceRefresh: true)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final palette = context.appPalette;
    final thoughts = detail == null
        ? const <MingtaiFeedItem>[]
        : _thoughts(detail);
    final traces = detail == null
        ? const <MingtaiFeedItem>[]
        : _recentTraces(detail);
    return Scaffold(
      appBar: AppBar(
        title: const Text('明台'),
        actions: [
          if (_canDeleteCurrentBook)
            PopupMenuButton<String>(
              enabled: !_deletingBook,
              tooltip: '管理这本书',
              onSelected: (value) {
                if (value == 'delete') _deleteCurrentBook();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 19),
                      SizedBox(width: 10),
                      Text('删除我上传的书'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      bottomNavigationBar: detail == null || _error != null
          ? null
          : Container(
              padding: EdgeInsets.fromLTRB(
                18,
                10,
                18,
                12 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                color: palette.surface.withAlpha(248),
                border: Border(top: BorderSide(color: palette.divider)),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed:
                        _startingReading ||
                            !BookService.canReadMingtaiBook(detail.book)
                        ? null
                        : _startReading,
                    child: Text(
                      !BookService.canReadMingtaiBook(detail.book)
                          ? '暂无可读内容'
                          : _startingReading
                          ? '打开中...'
                          : _hasReadingProgress
                          ? '继续阅读'
                          : '开始阅读',
                    ),
                  ),
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ListView(
              padding: const EdgeInsets.all(18),
              children: [_QuietError(message: _error!, onRetry: _load)],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 122),
              children: [
                _BookDetailHeader(
                  book: detail!.book,
                  borrowing: _borrowing,
                  descriptionExpanded: _descriptionExpanded,
                  onToggleDescription: () {
                    setState(
                      () => _descriptionExpanded = !_descriptionExpanded,
                    );
                  },
                  onBorrow: _borrow,
                ),
                const SizedBox(height: 20),
                _BookTraceStats(
                  readingCount: detail.book.readingCount,
                  sharedStopCount: _sharedStopCount(detail),
                  thoughtCount: thoughts.length,
                  discussionCount: _discussionCount(detail),
                ),
                const SizedBox(height: 24),
                _TraceMemorySection(
                  items: traces,
                  sharedStopCount: _sharedStopCount(detail),
                  onTap: _openTraceSheet,
                ),
                const SizedBox(height: 4),
                _BookReviewSection(
                  reviews: _reviews,
                  loading: _loadingReviews,
                  submitting: _submittingReview,
                  onWrite: _showReviewDialog,
                  onOpenProfile: _openProfile,
                  onChanged: () => unawaited(_loadReviews()),
                ),
              ],
            ),
    );
  }
}

class _PublishBookSheet extends StatefulWidget {
  const _PublishBookSheet();

  @override
  State<_PublishBookSheet> createState() => _PublishBookSheetState();
}

class _PublishBookSheetState extends State<_PublishBookSheet> {
  final Set<String> _selectedEntryIds = {};
  List<Book> _books = [];
  List<Map<String, dynamic>> _entries = [];
  Book? _selectedBook;
  String _copyrightStatus = 'public_domain';
  bool _loading = true;
  bool _loadingEntries = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    try {
      final books = await BookService.getBooks();
      if (!mounted) return;
      setState(() {
        _books = books
            .where((book) => !BookService.isMingtaiShelfBook(book))
            .toList();
        _selectedBook = _books.isEmpty ? null : _books.first;
        _loading = false;
      });
      if (_selectedBook != null) {
        _loadEntries(_selectedBook!.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadEntries(String bookId) async {
    setState(() {
      _loadingEntries = true;
      _selectedEntryIds.clear();
      _entries = const [];
    });
    try {
      final entries = await BookService.getPublishableEntriesForBook(bookId);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loadingEntries = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingEntries = false;
      });
    }
  }

  Future<void> _submit() async {
    final book = _selectedBook;
    if (book == null || _submitting) return;
    await AuthService.init();
    if (!mounted) return;
    if (!AuthService.isLoggedIn) {
      setState(() {
        _error = '请先登录后再发布到明台';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await BookService.publishBookToMingtai(
        book: book,
        copyrightStatus: _copyrightStatus,
        entryIds: _selectedEntryIds.toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已发布到明台'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: _loading
            ? const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: palette.divider,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '发布到明台',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '先选择版权状态。你也可以选择少量想法公开到书页边缘，未选择的内容仍只属于你。',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (_books.isEmpty)
                      const _PublishEmptyBooks()
                    else ...[
                      DropdownButtonFormField<Book>(
                        initialValue: _selectedBook,
                        items: _books
                            .map(
                              (book) => DropdownMenuItem(
                                value: book,
                                child: Text('《${book.title}》'),
                              ),
                            )
                            .toList(),
                        onChanged: (book) {
                          if (book == null) return;
                          setState(() => _selectedBook = book);
                          _loadEntries(book.id);
                        },
                        decoration: const InputDecoration(labelText: '书籍'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _copyrightStatus,
                        items: const [
                          DropdownMenuItem(
                            value: 'public_domain',
                            child: Text('公版书 public_domain'),
                          ),
                          DropdownMenuItem(
                            value: 'original',
                            child: Text('原创内容 original'),
                          ),
                          DropdownMenuItem(
                            value: 'authorized',
                            child: Text('已获授权 authorized'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _copyrightStatus = value);
                          }
                        },
                        decoration: const InputDecoration(labelText: '版权状态'),
                      ),
                      const SizedBox(height: 18),
                      const _SectionTitle(title: '可公开的想法'),
                      const SizedBox(height: 8),
                      if (_loadingEntries)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_entries.isEmpty)
                        const Text(
                          '这本书还没有可公开的想法。可以先发布书籍，之后再把某一句想法交给明台。',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        )
                      else
                        ..._entries.map(_buildEntryCheckbox),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _submit,
                          child: Text(_submitting ? '发布中...' : '发布到明台'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildEntryCheckbox(Map<String, dynamic> entry) {
    final id = entry['id']?.toString() ?? '';
    final userInput =
        entry['user_input']?.toString() ?? entry['user_note']?.toString() ?? '';
    final originalText = entry['original_text']?.toString() ?? '';
    final text = userInput.trim().isNotEmpty ? userInput : originalText;
    final source = BookService.mingtaiSourceLabel(
      entry['source']?.toString() ?? 'manual',
    );
    return CheckboxListTile(
      value: _selectedEntryIds.contains(id),
      contentPadding: EdgeInsets.zero,
      title: Text(
        text.isEmpty ? '无原文记录' : text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, height: 1.45),
      ),
      subtitle: Text(source),
      onChanged: (checked) {
        setState(() {
          if (checked == true) {
            _selectedEntryIds.add(id);
          } else {
            _selectedEntryIds.remove(id);
          }
        });
      },
    );
  }
}

class _MingtaiSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _MingtaiSearchField({
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: '找一本书、作者或一句话',
          prefixIcon: Icon(
            Icons.search_rounded,
            color: palette.textSecondary.withAlpha(170),
          ),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          filled: true,
          fillColor: palette.card.withAlpha(235),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: palette.divider.withAlpha(120)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: palette.divider.withAlpha(120)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: palette.primary.withAlpha(130)),
          ),
        ),
      ),
    );
  }
}

class _MingtaiSearchResultsSection extends StatelessWidget {
  final List<MingtaiPublicBook> books;
  final List<MingtaiPageMoment> moments;
  final bool loading;
  final String? error;
  final ValueChanged<MingtaiPublicBook> onOpenBook;
  final ValueChanged<MingtaiPageMoment> onOpenMoment;

  const _MingtaiSearchResultsSection({
    required this.books,
    required this.moments,
    required this.loading,
    required this.error,
    required this.onOpenBook,
    required this.onOpenMoment,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    if (!loading && books.isEmpty && moments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 58),
        child: Text(
          '没有在明台当前书页里找到。\n换个词试试看。',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 13,
            height: 1.7,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loading)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '正在明台里查找...',
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '搜索有点慢，先显示本地结果。',
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
            ),
          ),
        if (moments.isNotEmpty)
          _MingtaiSection(
            title: '✦ 找到的句子',
            subtitle: '从明台书页里拾起的一句话',
            children: moments
                .map(
                  (moment) => _MomentPreviewCard(
                    moment: moment,
                    onTap: () => onOpenMoment(moment),
                  ),
                )
                .toList(),
          ),
        if (books.isNotEmpty)
          _MingtaiSection(
            title: '✦ 找到的书',
            subtitle: '先进入书页，再开始阅读',
            children: [_BookRail(books: books, onTap: onOpenBook)],
          ),
      ],
    );
  }
}

class _MomentPreviewCard extends StatelessWidget {
  final MingtaiPageMoment moment;
  final VoidCallback onTap;

  const _MomentPreviewCard({required this.moment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
        decoration: BoxDecoration(
          color: palette.card.withAlpha(238),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.divider.withAlpha(135)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              moment.text.trim(),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 15,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 11),
            Text(
              '《${moment.bookTitle}》',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayEncounterCard extends StatelessWidget {
  final MingtaiPublicBook? book;
  final bool canDraw;
  final VoidCallback onDraw;
  final VoidCallback onShuffle;
  final VoidCallback? onOpen;

  const _TodayEncounterCard({
    required this.book,
    required this.canDraw,
    required this.onDraw,
    required this.onShuffle,
    required this.onOpen,
  });

  String _encounterLine(MingtaiPublicBook book) {
    final candidates = [
      book.encounterSummary,
      book.oneLineSummary,
      book.description,
    ];
    for (final value in candidates) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '也许可以从这本书开始。';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final current = book;
    return Container(
      margin: const EdgeInsets.only(bottom: 28),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '✦ 今日偶遇',
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          if (current == null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '不知道读什么？',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 20,
                    height: 1.45,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '让明台替你翻开一本书。',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 14,
                    height: 1.65,
                  ),
                ),
                const SizedBox(height: 22),
                OutlinedButton(
                  onPressed: canDraw ? onDraw : null,
                  child: const Text('遇见一本'),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _encounterLine(current),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    height: 1.75,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '《${current.title}》',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (current.author.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    current.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    FilledButton(onPressed: onOpen, child: const Text('进入书页')),
                    TextButton(onPressed: onShuffle, child: const Text('换一本')),
                  ],
                ),
              ],
            ),
          if (!canDraw && current == null) ...[
            const SizedBox(height: 12),
            Text(
              '明台暂时还没有可以偶遇的书。',
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThoughtPreviewCard extends StatelessWidget {
  final MingtaiFeedItem item;
  final VoidCallback onTap;

  const _ThoughtPreviewCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final text = _traceDisplayText(item);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
        decoration: BoxDecoration(
          color: palette.card.withAlpha(238),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.divider.withAlpha(135)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 15,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 11),
            Text(
              '《${item.bookTitle}》',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _MingtaiShelfSection extends StatelessWidget {
  final List<MingtaiPublicBook> books;
  final ValueChanged<MingtaiPublicBook> onBookTap;
  final VoidCallback onViewAll;

  const _MingtaiShelfSection({
    required this.books,
    required this.onBookTap,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return _MingtaiSection(
      title: '✦ 明台书架',
      subtitle: '从最近来到明台的书中慢慢翻看',
      action: TextButton(onPressed: onViewAll, child: const Text('查看全部')),
      children: [
        if (books.isEmpty)
          Text(
            '明台书架暂时还没有书。',
            style: TextStyle(color: palette.textSecondary, fontSize: 13),
          )
        else
          _MingtaiShelfGrid(books: books, onTap: onBookTap),
      ],
    );
  }
}

class _MingtaiShelfGrid extends StatelessWidget {
  final List<MingtaiPublicBook> books;
  final ValueChanged<MingtaiPublicBook> onTap;

  const _MingtaiShelfGrid({required this.books, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: books.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.58,
      ),
      itemBuilder: (_, index) {
        final book = books[index];
        return _MingtaiShelfBookCard(book: book, onTap: () => onTap(book));
      },
    );
  }
}

class _MingtaiShelfBookCard extends StatelessWidget {
  final MingtaiPublicBook book;
  final VoidCallback onTap;

  const _MingtaiShelfBookCard({required this.book, required this.onTap});

  String _statusText(MingtaiPublicBook book) {
    if (book.readingCount > 0) return '最近有人读';
    if (book.recentDiscussionCount > 0 || book.annotationCount > 0) {
      return '最近更新';
    }
    final createdAt = book.createdAt;
    if (createdAt != null &&
        DateTime.now().difference(createdAt).inDays <= 14) {
      return '新来到明台';
    }
    return '暂无状态';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.card.withAlpha(238),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.divider.withAlpha(120)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: _BookCover(
                imageUrl: book.coverUrl,
                title: book.title,
                author: book.author,
                width: 86,
                height: 120,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              book.author.trim().isEmpty ? '佚名' : book.author.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: palette.primaryLight.withAlpha(78),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _statusText(book),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.primaryDark.withAlpha(210),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookRail extends StatelessWidget {
  final List<MingtaiPublicBook> books;
  final ValueChanged<MingtaiPublicBook> onTap;

  const _BookRail({required this.books, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 152,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: books.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, index) {
          final book = books[index];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onTap(book),
            child: SizedBox(
              width: 88,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BookCover(
                    imageUrl: book.coverUrl,
                    title: book.title,
                    author: book.author,
                    large: true,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MingtaiSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? action;

  const _MingtaiSection({
    required this.title,
    required this.subtitle,
    required this.children,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _SectionTitle(title: title)),
              action ?? const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _BookDetailHeader extends StatelessWidget {
  final MingtaiPublicBook book;
  final bool borrowing;
  final bool descriptionExpanded;
  final VoidCallback onToggleDescription;
  final VoidCallback onBorrow;

  const _BookDetailHeader({
    required this.book,
    required this.borrowing,
    required this.descriptionExpanded,
    required this.onToggleDescription,
    required this.onBorrow,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final credits = _BookCredits.fromAuthor(book.author);
    final introduction = _BookIntroduction.fromBook(book);
    final hasReadableContent = BookService.canReadMingtaiBook(book);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BookCover(
              imageUrl: book.coverUrl,
              title: book.title,
              author: book.author,
              width: 112,
              height: 158,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '《${book.title}》',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      credits.author,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    if (credits.translator.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '译者：${credits.translator}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _MetaPill(text: _copyrightLabel(book.copyrightStatus)),
                        if (!hasReadableContent) const _MetaPill(text: '等待章节'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: borrowing || !hasReadableContent
                          ? null
                          : onBorrow,
                      icon: const Icon(Icons.library_add_outlined, size: 17),
                      label: Text(borrowing ? '借阅中...' : '借阅到书架'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: palette.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _BookIntroductionBlock(
          introduction: introduction,
          expanded: descriptionExpanded,
          onToggle: onToggleDescription,
        ),
      ],
    );
  }
}

class _BookCredits {
  final String author;
  final String translator;

  const _BookCredits({required this.author, required this.translator});

  factory _BookCredits.fromAuthor(String raw) {
    final parts = raw
        .split(RegExp(r'[;；]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return const _BookCredits(author: '佚名', translator: '');
    }
    final translatorParts = parts
        .where((part) => part.contains('译') || part.contains('翻译'))
        .map((part) => part.replaceAll(RegExp(r'译$'), '').trim())
        .where((part) => part.isNotEmpty)
        .toList();
    final authorParts = parts
        .where((part) => !translatorParts.contains(part))
        .where((part) => !(part.contains('译') || part.contains('翻译')))
        .toList();
    return _BookCredits(
      author: authorParts.isEmpty ? parts.first : authorParts.join('；'),
      translator: translatorParts.join('；'),
    );
  }
}

class _BookIntroduction {
  final String oneLine;
  final String expandedGuide;

  const _BookIntroduction({required this.oneLine, required this.expandedGuide});

  factory _BookIntroduction.fromBook(MingtaiPublicBook book) {
    final raw = _cleanIntroText(book.description);
    final oneLineSummary = _validIntroLine(book.oneLineSummary);
    final authoritativeDescription = _cleanIntroText(
      book.authoritativeDescription,
    );
    final title = _plainBookTitle(book.title);
    final sourceText = authoritativeDescription.isNotEmpty
        ? authoritativeDescription
        : raw;
    final expandedGuide = _validIntroLine(book.expandedGuide);

    return _BookIntroduction(
      oneLine: oneLineSummary.isNotEmpty
          ? oneLineSummary
          : _compactSentence(
              sourceText,
              fallback: title.isNotEmpty
                  ? '《$title》需要从正文里慢慢进入。'
                  : '这本书需要从正文里慢慢进入。',
            ),
      expandedGuide: expandedGuide.isNotEmpty
          ? expandedGuide
          : _expandedGuideFromSource(sourceText, title),
    );
  }
}

class _BookIntroductionBlock extends StatelessWidget {
  final _BookIntroduction introduction;
  final bool expanded;
  final VoidCallback onToggle;

  const _BookIntroductionBlock({
    required this.introduction,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
      decoration: BoxDecoration(
        color: palette.card.withAlpha(226),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: palette.primary.withAlpha(16),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                color: palette.primaryDark,
                size: 16,
              ),
              const SizedBox(width: 7),
              Text(
                '小U整理的读前导览',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _IntroPiece(
            title: '一句话简介',
            body: introduction.oneLine,
            emphasize: true,
          ),
          if (expanded) ...[
            const SizedBox(height: 14),
            _IntroPiece(title: '展开导读', body: introduction.expandedGuide),
          ],
          const SizedBox(height: 6),
          TextButton(
            onPressed: onToggle,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: palette.primaryDark,
            ),
            child: Text(expanded ? '收起导读' : '展开导读'),
          ),
        ],
      ),
    );
  }
}

class _IntroPiece extends StatelessWidget {
  final String title;
  final String body;
  final bool emphasize;

  const _IntroPiece({
    required this.title,
    required this.body,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          body,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: emphasize ? 16 : 14,
            height: emphasize ? 1.72 : 1.68,
            fontWeight: emphasize ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

String _cleanIntroText(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _validIntroLine(String value) {
  final text = _cleanIntroText(value);
  if (text.contains('围绕自身核心问题') ||
      text.contains('从正文和读者痕迹') ||
      text.contains('等待有人从第一页') ||
      text.contains('暂无可靠简介') ||
      text.contains('这本书刚来到明台')) {
    return '';
  }
  return text;
}

String _plainBookTitle(String title) {
  return title.replaceAll('《', '').replaceAll('》', '').trim();
}

String _compactSentence(String raw, {required String fallback}) {
  final matches = RegExp(r'[^。！？!?]+[。！？!?]?').allMatches(raw);
  final first = matches.isEmpty ? raw.trim() : matches.first.group(0)!.trim();
  final text = first.isEmpty ? fallback : first;
  if (text.length <= 72) return text;
  return '${text.substring(0, 72).trim()}...';
}

String _expandedGuideFromSource(String sourceText, String title) {
  final sentences = RegExp(r'[^。！？!?]+[。！？!?]?')
      .allMatches(sourceText)
      .map((match) => _cleanIntroText(match.group(0) ?? ''))
      .where((sentence) => sentence.length > 8)
      .take(3)
      .toList();
  if (sentences.length >= 2) {
    final joined = sentences.join('');
    return joined.length <= 180
        ? joined
        : '${joined.substring(0, 180).trim()}...';
  }
  final intro = sentences.isNotEmpty
      ? sentences.first
      : title.isNotEmpty
      ? '《$title》从正文展开它真正的问题。'
      : '这本书从正文展开它真正的问题。';
  return intro.length <= 180 ? intro : '${intro.substring(0, 180).trim()}...';
}

class _BookTraceStats extends StatelessWidget {
  final int readingCount;
  final int sharedStopCount;
  final int thoughtCount;
  final int discussionCount;

  const _BookTraceStats({
    required this.readingCount,
    required this.sharedStopCount,
    required this.thoughtCount,
    required this.discussionCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: context.appPalette.divider),
        ),
      ),
      child: Row(
        children: [
          _TraceStat(value: readingCount, label: '人在读'),
          _TraceStat(value: sharedStopCount, label: '共同停留'),
          _TraceStat(value: thoughtCount, label: '公开想法'),
          _TraceStat(value: discussionCount, label: '讨论'),
        ],
      ),
    );
  }
}

class _TraceStat extends StatelessWidget {
  final int value;
  final String label;

  const _TraceStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 11,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedTraceCard extends StatelessWidget {
  final MingtaiFeedItem item;
  final VoidCallback onTap;

  const _FeaturedTraceCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final text = _traceMainText(item);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 17),
        decoration: BoxDecoration(
          color: palette.card.withAlpha(238),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.divider.withAlpha(140)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '最近留下的话',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '“$text”',
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 16,
                height: 1.75,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _traceSourceLine(item),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _TraceMemorySection extends StatelessWidget {
  final List<MingtaiFeedItem> items;
  final int sharedStopCount;
  final ValueChanged<MingtaiFeedItem> onTap;

  const _TraceMemorySection({
    required this.items,
    required this.sharedStopCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: '✦ 最近留下的痕迹'),
          const SizedBox(height: 14),
          if (items.isEmpty && sharedStopCount > 0)
            _SharedStopCard(count: sharedStopCount)
          else if (items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
              decoration: BoxDecoration(
                color: palette.card.withAlpha(218),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: palette.divider.withAlpha(95)),
              ),
              child: Text(
                '这本书刚来到明台。\n\n还没有留下公开痕迹。\n\n也许你会成为第一个停留的人。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 14,
                  height: 1.8,
                ),
              ),
            )
          else ...[
            _FeaturedTraceCard(
              item: items.first,
              onTap: () => onTap(items.first),
            ),
            if (items.length > 1) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 154,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length > 9 ? 8 : items.length - 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final item = items[index + 1];
                    return _TracePreviewCard(
                      item: item,
                      onTap: () => onTap(item),
                    );
                  },
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _BookReviewSection extends StatelessWidget {
  final List<MingtaiBookReview> reviews;
  final bool loading;
  final bool submitting;
  final VoidCallback onWrite;
  final ValueChanged<String> onOpenProfile;
  final VoidCallback onChanged;

  const _BookReviewSection({
    required this.reviews,
    required this.loading,
    required this.submitting,
    required this.onWrite,
    required this.onOpenProfile,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _SectionTitle(title: '✦ 读者短评')),
              TextButton(
                onPressed: submitting ? null : onWrite,
                child: Text(submitting ? '发布中...' : '留下我的短评'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.primary,
                  ),
                ),
              ),
            )
          else if (reviews.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 21),
              decoration: BoxDecoration(
                color: palette.card.withAlpha(220),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: palette.divider.withAlpha(110)),
              ),
              child: Text(
                '还没有人认真写下这本书带来的回声。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            )
          else
            ...reviews
                .take(5)
                .map(
                  (review) => _BookReviewCard(
                    review: review,
                    onOpenProfile: () => onOpenProfile(review.user.userId),
                    onChanged: onChanged,
                  ),
                ),
        ],
      ),
    );
  }
}

class _BookReviewCard extends StatelessWidget {
  final MingtaiBookReview review;
  final VoidCallback onOpenProfile;
  final VoidCallback onChanged;

  const _BookReviewCard({
    required this.review,
    required this.onOpenProfile,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _showFullReview(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 15),
        decoration: BoxDecoration(
          color: palette.card.withAlpha(238),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.divider.withAlpha(130)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onOpenProfile,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ProfileAvatar(profile: review.user, size: 30),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          review.user.nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _dateLabel(review.createdAt),
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              review.content,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14,
                height: 1.65,
              ),
            ),
            if (review.resonanceCount > 0 || review.commentCount > 0) ...[
              const SizedBox(height: 10),
              Text(
                [
                  if (review.resonanceCount > 0) '${review.resonanceCount} 次共鸣',
                  if (review.commentCount > 0) '${review.commentCount} 句回应',
                ].join(' · '),
                style: TextStyle(color: palette.textSecondary, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showFullReview(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _InteractionDetailSheet(
        targetType: 'review',
        targetId: review.id,
        title: '读者短评',
        body: review.content,
        author: review.user,
        createdAt: review.createdAt,
        initialResonanceCount: review.resonanceCount,
        initialCommentCount: review.commentCount,
        onChanged: onChanged,
        onOpenProfile: () {
          Navigator.pop(context);
          onOpenProfile();
        },
      ),
    );
  }
}

class _BookReviewDialog extends StatefulWidget {
  final String initialContent;
  final String title;
  final String submitLabel;
  final String cancelLabel;

  const _BookReviewDialog({
    this.initialContent = '',
    this.title = '留下我的短评',
    this.submitLabel = '发布到明台',
    this.cancelLabel = '暂时保存为私密',
  });

  @override
  State<_BookReviewDialog> createState() => _BookReviewDialogState();
}

class _BookReviewDialogState extends State<_BookReviewDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final media = MediaQuery.of(context);
    final keyboardVisible = media.viewInsets.bottom > 0;
    final maxDialogHeight = media.size.height - media.viewInsets.bottom - 48;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxDialogHeight.clamp(280.0, media.size.height - 36),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: palette.divider.withAlpha(120)),
            boxShadow: [
              BoxShadow(
                color: palette.primary.withAlpha(22),
                blurRadius: 30,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '你想把这段读后感留在明台吗？\n它会出现在这本书的简介页，其他读者可以看见。\n你也可以之后在个人主页里修改或删除。',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 13,
                          height: 1.55,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _controller,
                        minLines: keyboardVisible ? 3 : 4,
                        maxLines: keyboardVisible ? 4 : 7,
                        autofocus: true,
                        scrollPadding: EdgeInsets.only(
                          bottom: media.viewInsets.bottom + 80,
                        ),
                        decoration: InputDecoration(
                          hintText: '写下这本书留给你的回声…',
                          filled: true,
                          fillColor: palette.background.withAlpha(150),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(widget.cancelLabel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, _controller.text.trim()),
                    child: Text(widget.submitLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SharedStopCard extends StatelessWidget {
  final int count;

  const _SharedStopCard({required this.count});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        color: palette.card.withAlpha(222),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.divider.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '最近共同停留',
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '$count 位读者曾在这本书里停留过。',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 15,
              height: 1.65,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TracePreviewCard extends StatelessWidget {
  final MingtaiFeedItem item;
  final VoidCallback onTap;

  const _TracePreviewCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 238,
        padding: const EdgeInsets.fromLTRB(15, 14, 15, 13),
        decoration: BoxDecoration(
          color: palette.card.withAlpha(236),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.divider.withAlpha(135)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _traceMainText(item),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14,
                height: 1.55,
              ),
            ),
            const Spacer(),
            Text(
              _traceSourceLine(item),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _InteractionDetailSheet extends StatefulWidget {
  final String targetType;
  final String targetId;
  final String title;
  final String body;
  final String secondaryText;
  final MingtaiUserProfile? author;
  final DateTime? createdAt;
  final int initialResonanceCount;
  final int initialCommentCount;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onChanged;

  const _InteractionDetailSheet({
    required this.targetType,
    required this.targetId,
    required this.title,
    required this.body,
    this.secondaryText = '',
    this.author,
    this.createdAt,
    this.initialResonanceCount = 0,
    this.initialCommentCount = 0,
    this.onOpenProfile,
    this.onChanged,
  });

  @override
  State<_InteractionDetailSheet> createState() =>
      _InteractionDetailSheetState();
}

class _InteractionDetailSheetState extends State<_InteractionDetailSheet> {
  List<MingtaiInteractionComment> _comments = const [];
  late int _resonanceCount;
  bool _loadingComments = true;
  bool _resonating = false;
  bool _commenting = false;
  String? _commentsError;

  @override
  void initState() {
    super.initState();
    _resonanceCount = widget.initialResonanceCount;
    _loadComments();
  }

  Future<void> _loadComments() async {
    try {
      final comments = await BookService.listMingtaiComments(
        targetType: widget.targetType,
        targetId: widget.targetId,
      );
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _loadingComments = false;
        _commentsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingComments = false;
        _commentsError = e.toString();
      });
    }
  }

  Future<bool> _ensureLoggedIn() async {
    await AuthService.init();
    if (AuthService.isLoggedIn) return true;
    if (!mounted) return false;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('请先登录，再留下回应')));
    return false;
  }

  Future<void> _sendResonance() async {
    if (_resonating || !await _ensureLoggedIn()) return;
    setState(() => _resonating = true);
    try {
      final count = await BookService.createMingtaiTargetResonance(
        targetType: widget.targetType,
        targetId: widget.targetId,
      );
      if (!mounted) return;
      setState(() {
        _resonanceCount = count > 0 ? count : _resonanceCount;
      });
      widget.onChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('共鸣已留下'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('共鸣失败：$e')));
    } finally {
      if (mounted) setState(() => _resonating = false);
    }
  }

  Future<void> _sendComment() async {
    if (_commenting || !await _ensureLoggedIn() || !mounted) return;
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('留下一句回应'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 1000,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(hintText: '回应这段文字本身…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('发送'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (content == null || content.isEmpty || !mounted) return;
    setState(() => _commenting = true);
    try {
      final comment = await BookService.createMingtaiComment(
        targetType: widget.targetType,
        targetId: widget.targetId,
        content: content,
      );
      if (!mounted) return;
      setState(() => _comments = [..._comments, comment]);
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('回应失败：$e')));
    } finally {
      if (mounted) setState(() => _commenting = false);
    }
  }

  void _openCommentProfile(MingtaiUserProfile profile) {
    if (profile.userId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MingtaiProfileScreen(userId: profile.userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return FractionallySizedBox(
      heightFactor: 0.82,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
            children: [
              if (widget.author != null) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: widget.onOpenProfile,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ProfileAvatar(profile: widget.author!, size: 34),
                      const SizedBox(width: 10),
                      Text(
                        widget.author!.nickname,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                Text(
                  widget.title,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                widget.body,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 16,
                  height: 1.75,
                ),
              ),
              if (widget.secondaryText.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(15, 13, 15, 14),
                  decoration: BoxDecoration(
                    color: palette.background,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    widget.secondaryText.trim(),
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 14,
                      height: 1.65,
                    ),
                  ),
                ),
              ],
              if (widget.createdAt != null) ...[
                const SizedBox(height: 12),
                Text(
                  _dateLabel(widget.createdAt),
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  _QuietAction(
                    icon: Icons.favorite_border,
                    label: _resonating ? '发送中' : '共鸣',
                    onTap: _resonating ? null : _sendResonance,
                  ),
                  const SizedBox(width: 8),
                  _QuietAction(
                    icon: Icons.mode_comment_outlined,
                    label: _commenting ? '发送中' : '回应',
                    onTap: _commenting ? null : _sendComment,
                  ),
                  const Spacer(),
                  if (_resonanceCount > 0)
                    Text(
                      '$_resonanceCount 次共鸣',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                '回应',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (_loadingComments)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_commentsError != null)
                TextButton(
                  onPressed: _loadComments,
                  child: const Text('重新读取回应'),
                )
              else if (_comments.isEmpty)
                Text(
                  '还没有回应。',
                  style: TextStyle(color: palette.textSecondary, fontSize: 13),
                )
              else
                ..._comments.map(
                  (comment) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => _openCommentProfile(comment.user),
                          child: _ProfileAvatar(
                            profile: comment.user,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                comment.user.nickname,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                comment.content,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 13,
                                  height: 1.55,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _dateLabel(comment.createdAt),
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 10,
                                ),
                              ),
                            ],
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
}

String _traceDisplayText(MingtaiFeedItem item) {
  final annotation = item.annotationText.trim();
  if (annotation.isNotEmpty) return annotation;
  final original = item.originalText.trim();
  if (original.isNotEmpty) return original;
  return _traceMainText(item);
}

bool _isMeaningfulPublicText(String value) {
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length < 8) return false;

  final compact = normalized.replaceAll(RegExp(r'\s+'), '');
  final lower = compact.toLowerCase();
  const badSamples = {
    '123',
    '1234',
    '111',
    '1111',
    '测试',
    'test',
    'asdf',
    'qwer',
    '无',
    '没有',
  };
  if (badSamples.contains(lower)) return false;
  if (RegExp(r'^[0-9a-zA-Z._-]+$').hasMatch(compact)) return false;
  if (RegExp(r'^(.)\1{2,}$', dotAll: true).hasMatch(compact)) return false;
  if (!RegExp(r'[\u4e00-\u9fa5A-Za-z]').hasMatch(compact)) return false;

  final chineseCount = RegExp(r'[\u4e00-\u9fa5]').allMatches(compact).length;
  final latinWords = RegExp(r'[A-Za-z]{3,}').allMatches(normalized).length;
  if (chineseCount < 4 && latinWords < 3) return false;

  return true;
}

String _traceMainText(MingtaiFeedItem item) {
  final annotation = item.annotationText.trim();
  if (item.source == 'thought' && annotation.isNotEmpty) return annotation;
  final original = item.originalText.trim();
  if (original.isNotEmpty) return original;
  if (annotation.isNotEmpty) return annotation;
  if (item.source == 'ai_explanation') return '有人把这一段交给小U解释过。';
  return '有人在这里停留过。';
}

String _traceSourceLine(MingtaiFeedItem item) {
  final source = BookService.mingtaiSourceLabel(item.source);
  final chapter = item.chapterTitle.trim();
  if (chapter.isEmpty) return source;
  return '$source · $chapter';
}

String _dateLabel(DateTime? value) {
  if (value == null) return '';
  final now = DateTime.now();
  final diff = now.difference(value);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  return '${value.year}.${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')}';
}

class _ProfileAvatar extends StatelessWidget {
  final MingtaiUserProfile profile;
  final double size;

  const _ProfileAvatar({required this.profile, required this.size});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final canLoadNetwork =
        profile.avatarUrl.startsWith('http://') ||
        profile.avatarUrl.startsWith('https://');
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.primaryLight.withAlpha(145),
            palette.card,
            palette.illustration.withAlpha(110),
          ],
        ),
      ),
      child: Text(
        profile.nickname.isEmpty ? '知' : profile.nickname.characters.first,
        style: TextStyle(
          color: palette.primaryDark,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    if (!canLoadNetwork) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: profile.avatarUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}

class _BookCover extends StatelessWidget {
  final String imageUrl;
  final String title;
  final String author;
  final bool large;
  final double? width;
  final double? height;

  const _BookCover({
    required this.imageUrl,
    this.title = '',
    this.author = '',
    this.large = false,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final canLoadNetwork =
        imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    final displayLarge = large || (height ?? 0) > 100;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: width ?? (large ? 70 : 50),
        height: height ?? (large ? 96 : 68),
        color: palette.illustration.withAlpha(72),
        child: canLoadNetwork
            ? CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                memCacheWidth: displayLarge ? 240 : 120,
                maxWidthDiskCache: displayLarge ? 480 : 240,
                fadeInDuration: const Duration(milliseconds: 160),
                placeholder: (_, _) => _BookCoverFallback(
                  title: title,
                  author: author,
                  large: displayLarge,
                ),
                errorWidget: (_, _, _) => _BookCoverFallback(
                  title: title,
                  author: author,
                  large: displayLarge,
                ),
              )
            : _BookCoverFallback(
                title: title,
                author: author,
                large: displayLarge,
              ),
      ),
    );
  }
}

class _BookCoverFallback extends StatelessWidget {
  final String title;
  final String author;
  final bool large;

  const _BookCoverFallback({
    this.title = '',
    this.author = '',
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final cleanTitle = _cleanTitle(title);
    final cleanAuthor = author.trim().isNotEmpty ? author.trim() : '佚名';
    final initials = _coverInitials(cleanTitle);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.primaryLight.withAlpha(92),
            palette.card.withAlpha(245),
            palette.primary.withAlpha(48),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            bottom: -8,
            child: Icon(
              Icons.menu_book_outlined,
              color: palette.primary.withAlpha(58),
              size: large ? 44 : 30,
            ),
          ),
          Padding(
            padding: EdgeInsets.all(large ? 8 : 5),
            child: large
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.menu_book_rounded,
                        size: 14,
                        color: palette.primaryDark.withAlpha(168),
                      ),
                      const Spacer(),
                      Text(
                        cleanTitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary.withAlpha(220),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          height: 1.18,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        cleanAuthor,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textSecondary.withAlpha(180),
                          fontSize: 6.5,
                          height: 1.1,
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Text(
                      initials,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.primaryDark.withAlpha(215),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.05,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static String _cleanTitle(String value) {
    final cleaned = value
        .replaceAll('《', '')
        .replaceAll('》', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? '知读' : cleaned;
  }

  static String _coverInitials(String value) {
    final cleaned = _cleanTitle(value).replaceAll(RegExp(r'\s+'), '');
    if (cleaned.length <= 2) return cleaned;
    return cleaned.substring(0, 2);
  }
}

class _MetaPill extends StatelessWidget {
  final String text;

  const _MetaPill({required this.text});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: palette.primaryLight.withAlpha(68),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
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
    final palette = context.appPalette;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: palette.primaryLight.withAlpha(68),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: palette.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: palette.primaryDark),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: palette.primaryDark,
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

class _QuietEmpty extends StatelessWidget {
  const _QuietEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      alignment: Alignment.center,
      child: const Text(
        '明台还很安静。\n等第一本书、第一句话和第一条页边笔记慢慢出现。',
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

class _PublishEmptyBooks extends StatelessWidget {
  const _PublishEmptyBooks();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Text(
        '你的书架还没有可发布的本地书。',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
      ),
    );
  }
}

class _QuietError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _QuietError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.card.withAlpha(240),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.divider),
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
      '不做热榜，不追逐喧闹。明台只留下那些值得停一停的书页。',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 12,
        height: 1.6,
      ),
    );
  }
}

String _copyrightLabel(String status) {
  if (status == 'public_domain') return '公版书';
  if (status == 'original') return '原创';
  if (status == 'authorized') return '已授权';
  return '版权已声明';
}
