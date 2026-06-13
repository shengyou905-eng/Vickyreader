import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
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
  MingtaiHomeData? _home;
  Timer? _prefetchTimer;
  int? _encounterIndex;
  bool _loading = false;
  bool _refreshing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (forceRefresh) {
      await BookService.clearMingtaiHomeCache();
    }
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
      if (prefetchedIds.length >= 1) return;
    }
  }

  @override
  void dispose() {
    _prefetchTimer?.cancel();
    super.dispose();
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

  void _openBookById(String bookId, {MingtaiPublicBook? initialBook}) {
    if (bookId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MingtaiBookDetailScreen(
          bookId: bookId,
          initialBook: initialBook ?? _findBook(bookId),
        ),
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

  List<MingtaiPublicBook> _recentlyStoppedBooks(MingtaiHomeData home) {
    final seen = <String>{};
    final books = <MingtaiPublicBook>[];
    for (final book in home.readingNow) {
      if (book.id.isEmpty || !seen.add(book.id)) continue;
      books.add(book);
    }
    return books;
  }

  List<MingtaiPublicBook> _newBooks(MingtaiHomeData home) {
    final seen = <String>{};
    return home.latestBooks.where((book) {
      if (book.id.isEmpty || !seen.add(book.id)) return false;
      return true;
    }).toList();
  }

  List<MingtaiPageMoment> _encounterCandidates(MingtaiHomeData home) {
    final seen = <String>{};
    final moments = <MingtaiPageMoment>[];
    for (final moment in [
      ...home.encounterPool,
      if (home.todayPage != null) home.todayPage!,
      ...home.latestBooks.map(_momentFromBook),
    ]) {
      final key = '${moment.publicBookId}:${moment.id}';
      if (moment.publicBookId.isEmpty || !seen.add(key)) continue;
      moments.add(moment);
    }
    return moments;
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

  MingtaiPageMoment? _currentEncounter(List<MingtaiPageMoment> candidates) {
    final index = _encounterIndex;
    if (index == null || candidates.isEmpty) return null;
    return candidates[index % candidates.length];
  }

  void _drawEncounter(List<MingtaiPageMoment> candidates) {
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
    return home.todayPage == null &&
        home.recentThoughts.isEmpty &&
        home.recentDiscussions.isEmpty &&
        home.readingNow.isEmpty &&
        home.latestBooks.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final home = _home;
    final recentlyStoppedBooks = home == null
        ? const <MingtaiPublicBook>[]
        : _recentlyStoppedBooks(home);
    final newBooks = home == null
        ? const <MingtaiPublicBook>[]
        : _newBooks(home);
    final encounterCandidates = home == null
        ? const <MingtaiPageMoment>[]
        : _encounterCandidates(home);
    final encounterMoment = _currentEncounter(encounterCandidates);

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
                        if (_error != null)
                          _QuietError(
                            message: _error!,
                            onRetry: () => _load(forceRefresh: true),
                          )
                        else if (home == null || _isQuiet(home))
                          const _QuietEmpty()
                        else ...[
                          _TodayEncounterCard(
                            moment: encounterMoment,
                            canDraw: encounterCandidates.isNotEmpty,
                            onDraw: () => _drawEncounter(encounterCandidates),
                            onShuffle: () =>
                                _drawEncounter(encounterCandidates),
                            onOpen: encounterMoment == null
                                ? null
                                : () => _openBookById(
                                      encounterMoment.publicBookId,
                                    ),
                          ),
                          if (recentlyStoppedBooks.isNotEmpty)
                            _ReadingNowSection(
                              books: recentlyStoppedBooks,
                              onTap: (book) =>
                                  _openBookById(book.id, initialBook: book),
                            ),
                          if (home.recentThoughts.isNotEmpty)
                            _RecentThoughtsSection(
                              items: home.recentThoughts,
                              onTap: (item) => _openBookById(item.bookId),
                            )
                          else if (home.recentDiscussions.isNotEmpty)
                            _RecentDiscussionsSection(
                              items: home.recentDiscussions,
                              onTap: (item) => _openBookById(
                                item.book.id,
                                initialBook: item.book,
                              ),
                            ),
                          if (newBooks.isNotEmpty)
                            _NewBooksSection(
                              books: newBooks,
                              onTap: (book) =>
                                  _openBookById(book.id, initialBook: book),
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
  final Set<String> _resonatingIds = {};
  final Set<String> _commentingIds = {};
  bool _descriptionExpanded = false;
  bool _hasReadingProgress = false;
  bool _loading = true;
  bool _startingReading = false;
  bool _borrowing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initialBook = widget.initialBook;
    if (initialBook != null) {
      _detail = MingtaiBookDetail(
        book: initialBook,
        annotations: const [],
      );
      _loading = false;
      unawaited(BookService.prefetchMingtaiBookChapters(initialBook));
      unawaited(_loadReadingProgress(initialBook));
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
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
    setState(() => _borrowing = true);
    try {
      await BookService.borrowMingtaiBook(book);
      if (!mounted) return;
      await context.read<BookshelfProvider>().loadBooks();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已借阅到书架'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
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

  Future<void> _sendResonance(MingtaiFeedItem item) async {
    if (_resonatingIds.contains(item.id)) return;
    setState(() => _resonatingIds.add(item.id));
    try {
      await BookService.createMingtaiResonance(annotationId: item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('共鸣已留下'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _load(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('共鸣失败：$e'), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _resonatingIds.remove(item.id));
    }
  }

  Future<void> _sendComment(MingtaiFeedItem item) async {
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('围绕这条批注写一句'),
        content: TextField(
          controller: controller,
          maxLength: 1000,
          maxLines: 3,
          decoration: const InputDecoration(hintText: '只回应这条页边笔记，不做普通评论区'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('发送'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (content == null || content.isEmpty) return;

    setState(() => _commentingIds.add(item.id));
    try {
      await BookService.createMingtaiAnnotationComment(
        annotationId: item.id,
        content: content,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('评论已留下'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _load(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('评论失败：$e'), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _commentingIds.remove(item.id));
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
      builder: (_) => _TraceDetailSheet(
        item: item,
        resonating: _resonatingIds.contains(item.id),
        commenting: _commentingIds.contains(item.id),
        onResonance: () => _sendResonance(item),
        onComment: () => _sendComment(item),
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
      appBar: AppBar(title: const Text('明台')),
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
                    onPressed: _startingReading ||
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
                        value: _selectedBook,
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
                        value: _copyrightStatus,
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
    final userInput = entry['user_input']?.toString() ??
        entry['user_note']?.toString() ??
        '';
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

class _TodayEncounterCard extends StatelessWidget {
  final MingtaiPageMoment? moment;
  final bool canDraw;
  final VoidCallback onDraw;
  final VoidCallback onShuffle;
  final VoidCallback? onOpen;

  const _TodayEncounterCard({
    required this.moment,
    required this.canDraw,
    required this.onDraw,
    required this.onShuffle,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final current = moment;
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
                  '让明台替你随机翻开一本书。',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 14,
                    height: 1.65,
                  ),
                ),
                const SizedBox(height: 22),
                OutlinedButton(
                  onPressed: canDraw ? onDraw : null,
                  child: const Text('抽一张'),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current.text,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 17,
                    height: 1.85,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '《${current.bookTitle}》',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (current.bookAuthor.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    current.bookAuthor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (current.bookOneLineSummary.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    current.bookOneLineSummary.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: onOpen,
                      child: const Text('进入书页'),
                    ),
                    TextButton(
                      onPressed: onShuffle,
                      child: const Text('换一本'),
                    ),
                  ],
                ),
              ],
            ),
          if (!canDraw && current == null) ...[
            const SizedBox(height: 12),
            Text(
              '明台暂时还没有可以偶遇的书页。',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentThoughtsSection extends StatelessWidget {
  final List<MingtaiFeedItem> items;
  final ValueChanged<MingtaiFeedItem> onTap;

  const _RecentThoughtsSection({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _MingtaiSection(
      title: '✦ 最近留下痕迹',
      subtitle: '一些人在书页边缘留下的停顿',
      children: items
          .map(
            (item) => _ThoughtPreviewCard(item: item, onTap: () => onTap(item)),
          )
          .toList(),
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
    final text = item.annotationText.trim().isNotEmpty
        ? item.annotationText.trim()
        : item.originalText.trim();
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

class _RecentDiscussionsSection extends StatelessWidget {
  final List<MingtaiDiscussionPreview> items;
  final ValueChanged<MingtaiDiscussionPreview> onTap;

  const _RecentDiscussionsSection({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _MingtaiSection(
      title: '✦ 最近留下痕迹',
      subtitle: '刚刚被回应过的书页',
      children: items
          .map(
            (item) =>
                _DiscussionPreviewCard(item: item, onTap: () => onTap(item)),
          )
          .toList(),
    );
  }
}

class _DiscussionPreviewCard extends StatelessWidget {
  final MingtaiDiscussionPreview item;
  final VoidCallback onTap;

  const _DiscussionPreviewCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BookCover(
              imageUrl: item.book.coverUrl,
              title: item.book.title,
              author: item.book.author,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '《${item.book.title}》',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.excerpt,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      height: 1.55,
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

class _ReadingNowSection extends StatelessWidget {
  final List<MingtaiPublicBook> books;
  final ValueChanged<MingtaiPublicBook> onTap;

  const _ReadingNowSection({required this.books, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _MingtaiSection(
      title: '✦ 最近有人停留',
      subtitle: '最近有人从这里走进了一本书',
      children: [
        _BookRail(books: books, onTap: onTap),
      ],
    );
  }
}

class _NewBooksSection extends StatelessWidget {
  final List<MingtaiPublicBook> books;
  final ValueChanged<MingtaiPublicBook> onTap;

  const _NewBooksSection({required this.books, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _MingtaiSection(
      title: '✦ 新来到明台',
      subtitle: '刚刚被放到公共书页上的书',
      children: [_BookRail(books: books, onTap: onTap)],
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
        separatorBuilder: (_, __) => const SizedBox(width: 12),
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

  const _MingtaiSection({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title: title),
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

  const _BookIntroduction({
    required this.oneLine,
    required this.expandedGuide,
  });

  factory _BookIntroduction.fromBook(
    MingtaiPublicBook book,
  ) {
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

String _expandedGuideFromSource(
  String sourceText,
  String title,
) {
  final sentences = RegExp(r'[^。！？!?]+[。！？!?]?')
      .allMatches(sourceText)
      .map((match) => _cleanIntroText(match.group(0) ?? ''))
      .where((sentence) => sentence.length > 8)
      .take(3)
      .toList();
  if (sentences.length >= 2) {
    final joined = sentences.join('');
    return joined.length <= 180 ? joined : '${joined.substring(0, 180).trim()}...';
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
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
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

class _TraceDetailSheet extends StatelessWidget {
  final MingtaiFeedItem item;
  final bool resonating;
  final bool commenting;
  final VoidCallback onResonance;
  final VoidCallback onComment;

  const _TraceDetailSheet({
    required this.item,
    required this.resonating,
    required this.commenting,
    required this.onResonance,
    required this.onComment,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final annotation = item.annotationText.trim();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.chapterTitle.isEmpty ? '公开痕迹' : item.chapterTitle,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                item.originalText.trim().isEmpty
                    ? _traceMainText(item)
                    : item.originalText.trim(),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 16,
                  height: 1.75,
                ),
              ),
              if (annotation.isNotEmpty) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(15, 13, 15, 14),
                  decoration: BoxDecoration(
                    color: palette.background,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: palette.divider),
                  ),
                  child: Text(
                    annotation,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 14,
                      height: 1.65,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _QuietAction(
                    icon: Icons.favorite_border,
                    label: resonating ? '发送中' : '共鸣',
                    onTap: resonating ? null : onResonance,
                  ),
                  _QuietAction(
                    icon: Icons.mode_comment_outlined,
                    label: commenting ? '发送中' : '评论',
                    onTap: commenting ? null : onComment,
                  ),
                  if (item.resonanceCount > 0)
                    _MetaPill(text: '已有 ${item.resonanceCount} 人停留'),
                  if (item.commentCount > 0)
                    _MetaPill(text: '${item.commentCount} 句回应'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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
                placeholder: (_, __) => _BookCoverFallback(
                  title: title,
                  author: author,
                  large: displayLarge,
                ),
                errorWidget: (_, __, ___) => _BookCoverFallback(
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
