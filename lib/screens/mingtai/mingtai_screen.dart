import 'dart:async';

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
  MingtaiHomeData? _home;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final cached = BookService.cachedMingtaiHome();
    final canShowCache = _home == null && cached != null;
    if (!mounted) return;
    setState(() {
      if (canShowCache) _home = cached;
      _loading = _home == null && !canShowCache;
      _refreshing = _home != null || canShowCache;
      _error = null;
    });
    if (canShowCache) _prefetchVisibleBooks(cached);

    try {
      final home = await BookService.getMingtaiHome(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _home = home;
        _loading = false;
        _refreshing = false;
      });
      _prefetchVisibleBooks(home);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_home == null) _error = e.toString();
        _loading = false;
        _refreshing = false;
      });
    }
  }

  void _prefetchVisibleBooks(MingtaiHomeData home) {
    final prefetchedIds = <String>{};
    for (final book in [...home.readingNow, ...home.latestBooks]) {
      if (!BookService.canReadMingtaiBook(book) ||
          !prefetchedIds.add(book.id)) {
        continue;
      }
      unawaited(BookService.prefetchMingtaiBookChapters(book));
      if (prefetchedIds.length >= 3) return;
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

  void _openBook(MingtaiPublicBook book) {
    if (!BookService.canReadMingtaiBook(book)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('这本明台书尚未生成章节缓存，请重新发布后再阅读'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    unawaited(BookService.recordMingtaiBookRead(book.id));
    final readerBook = BookService.readableBookFromMingtai(book);
    unawaited(context.read<ReaderProvider>().openBook(readerBook));
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ReaderScreen()));
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

  List<MingtaiPublicBook> _latestBooks(MingtaiHomeData home) {
    final readingIds = home.readingNow.map((book) => book.id).toSet();
    return home.latestBooks
        .where((book) => !readingIds.contains(book.id))
        .toList();
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
                        else if (_home == null || _isQuiet(_home!))
                          const _QuietEmpty()
                        else ...[
                          if (_home!.todayPage != null)
                            _TodayPageCard(
                              moment: _home!.todayPage!,
                              onTap: () =>
                                  _openBookById(_home!.todayPage!.publicBookId),
                            ),
                          if (_home!.recentThoughts.isNotEmpty)
                            _RecentThoughtsSection(
                              items: _home!.recentThoughts,
                              onTap: (item) => _openBookById(item.bookId),
                            ),
                          if (_home!.recentDiscussions.isNotEmpty)
                            _RecentDiscussionsSection(
                              items: _home!.recentDiscussions,
                              onTap: (item) => _openBook(item.book),
                            ),
                          if (_home!.readingNow.isNotEmpty)
                            _ReadingNowSection(
                              books: _home!.readingNow,
                              onTap: _openBook,
                            ),
                          if (_latestBooks(_home!).isNotEmpty)
                            _BookSection(
                              title: '最新公开',
                              books: _latestBooks(_home!),
                              onTap: _openBook,
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
  final Set<String> _expandedIds = {};
  final Set<String> _resonatingIds = {};
  final Set<String> _commentingIds = {};
  int _selectedCommunityTab = 0;
  bool _loading = true;
  bool _startingReading = false;
  bool _borrowing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initialBook = widget.initialBook;
    if (initialBook != null) {
      _detail = MingtaiBookDetail(book: initialBook, annotations: const []);
      _loading = false;
      unawaited(BookService.prefetchMingtaiBookChapters(initialBook));
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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

  void _toggleContext(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  List<MingtaiFeedItem> _itemsForCurrentTab(MingtaiBookDetail detail) {
    if (_selectedCommunityTab == 0) {
      final highlights = detail.annotations
          .where((item) => item.source == 'highlight')
          .toList();
      highlights.sort((a, b) {
        final aChapter = int.tryParse(a.chapterIndex) ?? 0;
        final bChapter = int.tryParse(b.chapterIndex) ?? 0;
        final byChapter = aChapter.compareTo(bChapter);
        if (byChapter != 0) return byChapter;
        final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      return highlights;
    }
    if (_selectedCommunityTab == 1) {
      return detail.annotations
          .where((item) => item.source == 'thought' || item.source == 'manual')
          .toList();
    }
    return detail.annotations
        .where((item) => item.source == 'ai_explanation')
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(title: Text(detail?.book.title ?? '明台书籍')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ListView(
              padding: const EdgeInsets.all(18),
              children: [_QuietError(message: _error!, onRetry: _load)],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
              children: [
                _BookDetailHeader(
                  book: detail!.book,
                  startingReading: _startingReading,
                  borrowing: _borrowing,
                  onStartReading: _startReading,
                  onBorrow: _borrow,
                ),
                const SizedBox(height: 22),
                _CommunityTabs(
                  selectedIndex: _selectedCommunityTab,
                  onChanged: (index) {
                    setState(() => _selectedCommunityTab = index);
                  },
                ),
                const SizedBox(height: 12),
                if (_itemsForCurrentTab(detail).isEmpty)
                  _BookEmptyAnnotations(tabIndex: _selectedCommunityTab)
                else
                  ..._itemsForCurrentTab(detail).map(
                    (item) => _AnnotationCard(
                      item: item,
                      expanded: _expandedIds.contains(item.id),
                      resonating: _resonatingIds.contains(item.id),
                      commenting: _commentingIds.contains(item.id),
                      onResonance: () => _sendResonance(item),
                      onComment: () => _sendComment(item),
                      onToggleContext: () => _toggleContext(item.id),
                    ),
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
                      '先选择版权状态，再选择要公开的批注。未选择的内容不会公开。',
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
                      const _SectionTitle(title: '公开批注'),
                      const SizedBox(height: 8),
                      if (_loadingEntries)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_entries.isEmpty)
                        const Text(
                          '这本书还没有可公开的阅读记录。可以先发布书籍，之后再公开批注。',
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
    final text = entry['original_text']?.toString() ?? '';
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

class _TodayPageCard extends StatelessWidget {
  final MingtaiPageMoment moment;
  final VoidCallback onTap;

  const _TodayPageCard({required this.moment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
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
            '今日书页',
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            moment.text,
            maxLines: 7,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 17,
              height: 1.85,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (moment.annotationText.trim().isNotEmpty &&
              moment.annotationText.trim() != moment.text.trim()) ...[
            const SizedBox(height: 18),
            Text(
              moment.annotationText,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
                height: 1.65,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  '《${moment.bookTitle}》${moment.bookAuthor.isEmpty ? '' : '  ·  ${moment.bookAuthor}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
              TextButton(onPressed: onTap, child: const Text('进入阅读')),
            ],
          ),
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
      title: '最近被看见的想法',
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
      title: '最近讨论',
      subtitle: '有些书页刚刚被人轻轻翻动',
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
            _BookCover(imageUrl: item.book.coverUrl),
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
      title: '正在阅读',
      subtitle: '最近有人从这里走进了一本书',
      children: [
        SizedBox(
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
                      _BookCover(imageUrl: book.coverUrl, large: true),
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
        ),
      ],
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

class _PublicBookCard extends StatelessWidget {
  final MingtaiPublicBook book;
  final VoidCallback onTap;

  const _PublicBookCard({required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.card.withAlpha(242),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.divider.withAlpha(150)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BookCover(imageUrl: book.coverUrl),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '《${book.title}》',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    book.author.isEmpty ? '佚名' : book.author,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _MetaPill(text: _copyrightLabel(book.copyrightStatus)),
                      _MetaPill(text: '${book.readingCount} 人阅读'),
                      _MetaPill(text: '${book.recentDiscussionCount} 条最近讨论'),
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

class _BookSection extends StatelessWidget {
  final String title;
  final List<MingtaiPublicBook> books;
  final ValueChanged<MingtaiPublicBook> onTap;

  const _BookSection({
    required this.title,
    required this.books,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: title),
        const SizedBox(height: 10),
        ...books.map(
          (book) => _PublicBookCard(book: book, onTap: () => onTap(book)),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _CommunityTabs extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _CommunityTabs({required this.selectedIndex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    const labels = ['公共划线', '想法', 'AI解读'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.card.withAlpha(225),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.divider.withAlpha(150)),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = selectedIndex == index;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => onChanged(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: selected
                      ? palette.primaryLight.withAlpha(92)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  labels[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected
                        ? palette.primaryDark
                        : palette.textSecondary,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _BookDetailHeader extends StatelessWidget {
  final MingtaiPublicBook book;
  final bool startingReading;
  final bool borrowing;
  final VoidCallback onStartReading;
  final VoidCallback onBorrow;

  const _BookDetailHeader({
    required this.book,
    required this.startingReading,
    required this.borrowing,
    required this.onStartReading,
    required this.onBorrow,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.card.withAlpha(242),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.divider.withAlpha(150)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BookCover(imageUrl: book.coverUrl, large: true),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '《${book.title}》',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  book.author.isEmpty ? '佚名' : book.author,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _MetaPill(text: _copyrightLabel(book.copyrightStatus)),
                    _MetaPill(text: '${book.annotationCount} 条批注'),
                  ],
                ),
                const SizedBox(height: 14),
                Builder(
                  builder: (context) {
                    final hasReadableContent = BookService.canReadMingtaiBook(
                      book,
                    );
                    return Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: startingReading || !hasReadableContent
                                ? null
                                : onStartReading,
                            icon: const Icon(Icons.menu_book_rounded),
                            label: Text(
                              !hasReadableContent
                                  ? '暂无可读内容'
                                  : startingReading
                                  ? '打开中...'
                                  : '开始阅读',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: borrowing || !hasReadableContent
                                ? null
                                : onBorrow,
                            icon: const Icon(Icons.library_add_outlined),
                            label: Text(
                              !hasReadableContent
                                  ? '暂无可借阅内容'
                                  : borrowing
                                  ? '借阅中...'
                                  : '借阅到书架',
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnotationCard extends StatelessWidget {
  final MingtaiFeedItem item;
  final bool expanded;
  final bool resonating;
  final bool commenting;
  final VoidCallback onResonance;
  final VoidCallback onComment;
  final VoidCallback onToggleContext;

  const _AnnotationCard({
    required this.item,
    required this.expanded,
    required this.resonating,
    required this.commenting,
    required this.onResonance,
    required this.onComment,
    required this.onToggleContext,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final contextBefore = item.metadata['contextBefore']?.toString() ?? '';
    final contextAfter = item.metadata['contextAfter']?.toString() ?? '';
    final annotation = item.annotationText.trim().isNotEmpty
        ? item.annotationText.trim()
        : _fallbackAnnotation(item.source);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: palette.card.withAlpha(242),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.divider.withAlpha(150)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.chapterTitle.isNotEmpty) ...[
            Text(
              item.chapterTitle,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
          ],
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
              color: palette.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.divider),
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
                label: resonating ? '发送中' : '共鸣',
                onTap: resonating ? null : onResonance,
              ),
              _QuietAction(
                icon: Icons.mode_comment_outlined,
                label: commenting ? '发送中' : '评论',
                onTap: commenting ? null : onComment,
              ),
              _QuietAction(
                icon: expanded ? Icons.expand_less : Icons.notes_outlined,
                label: expanded ? '收起上下文' : '展开上下文',
                onTap: onToggleContext,
              ),
              if (item.resonanceCount > 0)
                _MetaPill(text: '已有 ${item.resonanceCount} 人在这里停留过'),
              if (item.commentCount > 0)
                _MetaPill(text: '${item.commentCount} 句回应'),
            ],
          ),
        ],
      ),
    );
  }

  String _fallbackAnnotation(String source) {
    if (source == 'highlight') return '有人在这里划下了这句话。';
    if (source == 'ai_explanation') return '有人把这段交给小U解释过。';
    if (source == 'thought') return '有人在这里留下了一句想法。';
    return '有人在这里留下了一条页边笔记。';
  }
}

class _BookCover extends StatelessWidget {
  final String imageUrl;
  final bool large;

  const _BookCover({required this.imageUrl, this.large = false});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final canLoadNetwork =
        imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: large ? 70 : 50,
        height: large ? 96 : 68,
        color: palette.illustration.withAlpha(72),
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
    return Icon(
      Icons.menu_book_outlined,
      color: context.appPalette.icon,
      size: 22,
    );
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

class _BookEmptyAnnotations extends StatelessWidget {
  final int tabIndex;

  const _BookEmptyAnnotations({required this.tabIndex});

  @override
  Widget build(BuildContext context) {
    final text = tabIndex == 0
        ? '这本书暂时还没有公开划线。'
        : tabIndex == 1
        ? '这本书暂时还没有公开想法。'
        : '这本书暂时还没有公开 AI 解读。';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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
