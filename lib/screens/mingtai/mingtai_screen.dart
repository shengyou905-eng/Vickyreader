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
  List<MingtaiPublicBook> _books = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final firstLoad = _books.isEmpty;
    if (!mounted) return;
    setState(() {
      _loading = firstLoad;
      _refreshing = !firstLoad;
      _error = null;
    });

    try {
      final books = await BookService.getMingtaiBooks(limit: 50);
      if (!mounted) return;
      setState(() {
        _books = books;
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _books = const [];
        _loading = false;
        _refreshing = false;
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
      _load();
    }
  }

  void _openBook(MingtaiPublicBook book) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MingtaiBookDetailScreen(bookId: book.id),
      ),
    );
  }

  List<MingtaiPublicBook> get _recommendedBooks => _books.take(3).toList();

  List<MingtaiPublicBook> get _popularBooks {
    final books = [..._books];
    books.sort((a, b) => b.readingCount.compareTo(a.readingCount));
    return books.take(3).toList();
  }

  List<MingtaiPublicBook> get _latestBooks => _books.take(5).toList();

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
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
                      children: [
                        const _MingtaiIntroCard(),
                        const SizedBox(height: 20),
                        if (_error != null)
                          _QuietError(message: _error!, onRetry: _load)
                        else if (_books.isEmpty)
                          const _QuietEmpty()
                        else ...[
                          _BookSection(
                            title: '推荐书籍',
                            books: _recommendedBooks,
                            onTap: _openBook,
                          ),
                          _BookSection(
                            title: '热门阅读',
                            books: _popularBooks,
                            onTap: _openBook,
                          ),
                          _BookSection(
                            title: '最新公开',
                            books: _latestBooks,
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

  const MingtaiBookDetailScreen({
    super.key,
    required this.bookId,
  });

  @override
  State<MingtaiBookDetailScreen> createState() =>
      _MingtaiBookDetailScreenState();
}

class _MingtaiBookDetailScreenState extends State<MingtaiBookDetailScreen> {
  MingtaiBookDetail? _detail;
  final Set<String> _expandedIds = {};
  final Set<String> _resonatingIds = {};
  int _selectedCommunityTab = 0;
  bool _loading = true;
  bool _startingReading = false;
  bool _borrowing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _detail == null;
      _error = null;
    });
    try {
      final detail = await BookService.getMingtaiBookDetail(widget.bookId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
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
        SnackBar(
          content: Text('借阅失败：$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _borrowing = false);
    }
  }

  Future<void> _startReading() async {
    final book = _detail?.book;
    if (book == null || _startingReading) return;
    if (book.fileUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('这本明台书缺少文件，请从书架重新发布覆盖'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _startingReading = true);
    try {
      final readerBook = BookService.readableBookFromMingtai(book);
      final readerProvider = context.read<ReaderProvider>();
      unawaited(readerProvider.openBook(readerBook));
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ReaderScreen()),
      );
    } finally {
      if (mounted) setState(() => _startingReading = false);
    }
  }

  Future<void> _sendResonance(MingtaiFeedItem item) async {
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('写一句共鸣'),
        content: TextField(
          controller: controller,
          maxLength: 280,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '这条批注让你想到什么？',
          ),
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

    setState(() => _resonatingIds.add(item.id));
    try {
      await BookService.createMingtaiResonance(
        annotationId: item.id,
        content: content,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('共鸣已留下'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('发送失败：$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _resonatingIds.remove(item.id));
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
      highlights.sort((a, b) => b.resonanceCount.compareTo(a.resonanceCount));
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
                          onResonance: () => _sendResonance(item),
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
                          color: AppTheme.dividerColor,
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
            '公共阅读书斋',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 12),
          Text(
            '以书为入口，\n公开的批注只出现在书页边缘。',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w700,
              height: 1.45,
            ),
          ),
          SizedBox(height: 14),
          Text(
            '没有关注、热榜、点赞或普通评论区。发布前必须选择版权状态，私有内容不会默认公开。',
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

class _PublicBookCard extends StatelessWidget {
  final MingtaiPublicBook book;
  final VoidCallback onTap;

  const _PublicBookCard({
    required this.book,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(238),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.dividerColor.withAlpha(120)),
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
          (book) => _PublicBookCard(
            book: book,
            onTap: () => onTap(book),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _CommunityTabs extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _CommunityTabs({
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const labels = ['热门划线', '想法', 'AI解读'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(220),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.dividerColor.withAlpha(120)),
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
                      ? AppTheme.primaryLight.withAlpha(36)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  labels[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? AppTheme.primaryDark : AppTheme.textSecondary,
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(238),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.dividerColor.withAlpha(120)),
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
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: startingReading || book.fileUrl.isEmpty
                        ? null
                        : onStartReading,
                    icon: const Icon(Icons.menu_book_rounded),
                    label: Text(
                      book.fileUrl.isEmpty
                          ? '缺少书籍文件'
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
                    onPressed: borrowing || book.fileUrl.isEmpty ? null : onBorrow,
                    icon: const Icon(Icons.library_add_outlined),
                    label: Text(
                      book.fileUrl.isEmpty
                          ? '缺少书籍文件'
                          : borrowing
                              ? '借阅中...'
                              : '借阅到书架',
                    ),
                  ),
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
  final VoidCallback onResonance;
  final VoidCallback onToggleContext;

  const _AnnotationCard({
    required this.item,
    required this.expanded,
    required this.resonating,
    required this.onResonance,
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
                label: resonating ? '发送中' : '共鸣',
                onTap: resonating ? null : onResonance,
              ),
              _QuietAction(
                icon: expanded ? Icons.expand_less : Icons.notes_outlined,
                label: expanded ? '收起上下文' : '展开上下文',
                onTap: onToggleContext,
              ),
              if (item.resonanceCount > 0)
                _MetaPill(text: '已有 ${item.resonanceCount} 人在这里停留过'),
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
  final bool large;

  const _BookCover({
    required this.imageUrl,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final canLoadNetwork =
        imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: large ? 70 : 50,
        height: large ? 96 : 68,
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

class _MetaPill extends StatelessWidget {
  final String text;

  const _MetaPill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withAlpha(20),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 11,
        ),
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
        '明台还没有公开书籍。\n点击右上角按钮，可以选择自己的书发布到明台。',
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
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 13,
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
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 13,
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
      '明台以书为锚点，不做关注、点赞、热榜和无限瀑布流。',
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
