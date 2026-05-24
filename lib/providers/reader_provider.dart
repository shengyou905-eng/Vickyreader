import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/book.dart';
import '../models/bookmark.dart';
import '../models/highlight.dart';
import '../models/user_entry.dart';
import '../services/book_service.dart';
import '../services/epub_service.dart';
import '../services/auth_service.dart';

class ReaderProvider extends ChangeNotifier {
  Book? _book;
  List<EpubChapter> _chapters = [];
  int _currentChapterIndex = 0;
  double _scrollOffset = 0.0;
  List<Highlight> _highlights = [];
  bool _isLoading = false;
  String? _selectedText;
  bool _showAiPanel = false;
  String? _scrollToText;
  List<Bookmark> _bookmarks = [];
  bool _isBookmarked = false;
  Timer? _progressSaveTimer;
  int _openBookToken = 0;
  int _readingPositionRevision = 0;
  String? _loadError;

  Book? get book => _book;
  List<EpubChapter> get chapters => _chapters;
  EpubChapter? get currentChapter =>
      _currentChapterIndex < _chapters.length
          ? _chapters[_currentChapterIndex]
          : null;
  int get currentChapterIndex => _currentChapterIndex;
  double get scrollOffset => _scrollOffset;
  List<Highlight> get highlights => _highlights;
  bool get isLoading => _isLoading;
  String? get selectedText => _selectedText;
  bool get showAiPanel => _showAiPanel;
  String? get scrollToTextTarget => _scrollToText;
  List<Bookmark> get bookmarks => _bookmarks;
  bool get isBookmarked => _isBookmarked;
  int get readingPositionRevision => _readingPositionRevision;
  String? get loadError => _loadError;

  void setScrollTarget(String? text) {
    _scrollToText = text;
  }

  void setScrollOffset(double offset) {
    _scrollOffset = offset;
  }
  double get progress =>
      _chapters.isNotEmpty ? _currentChapterIndex / _chapters.length : 0.0;

  Future<void> openBook(Book book) async {
    final token = ++_openBookToken;
    _progressSaveTimer?.cancel();
    _book = book;
    _chapters = [];
    _highlights = [];
    _bookmarks = [];
    _currentChapterIndex = 0;
    _scrollOffset = 0.0;
    _selectedText = null;
    _showAiPanel = false;
    _scrollToText = null;
    _isBookmarked = false;
    _loadError = null;
    _isLoading = true;
    notifyListeners();

    try {
      final readableBook = await BookService.prepareBookForReading(book);
      if (token != _openBookToken || _disposed) return;
      _book = readableBook;

      final chaptersFuture = readableBook.format == 'pdf'
          ? Future.value([EpubChapter(title: 'PDF 文档', content: '', index: 0)])
          : EpubService.getChapters(readableBook.id);
      final highlightsFuture = BookService.getHighlights(readableBook.id);
      final bookmarksFuture = BookService.getBookmarks(readableBook.id);
      final progressFuture = BookService.getReadingProgress(readableBook.id);

      final results = await Future.wait<Object?>([
        chaptersFuture,
        highlightsFuture,
        bookmarksFuture,
        progressFuture,
      ]);
      if (token != _openBookToken || _disposed) return;

      _chapters = results[0] as List<EpubChapter>;
      _highlights = results[1] as List<Highlight>;
      _bookmarks = results[2] as List<Bookmark>;

      final restored = _applyReadingProgress(
        results[3] as ({String chapterIndex, double scrollOffset})?,
      );
      _checkBookmarkStatus();
      _isLoading = false;
      notifyListeners();

      unawaited(_refreshRemoteReadingProgress(
        readableBook.id,
        token,
        baseChapterIndex: restored.chapterIndex,
        baseScrollOffset: restored.scrollOffset,
      ));
    } catch (e) {
      if (token != _openBookToken || _disposed) return;
      _isLoading = false;
      _loadError = '打开书籍失败：$e';
      notifyListeners();
    }
  }

  ({int chapterIndex, double scrollOffset}) _applyReadingProgress(
    ({String chapterIndex, double scrollOffset})? progress,
  ) {
    var chapterIndex = 0;
    var scrollOffset = 0.0;
    if (progress != null) {
      final restoredChapter = int.tryParse(progress.chapterIndex) ?? 0;
      chapterIndex = _chapters.isEmpty
          ? 0
          : restoredChapter.clamp(0, _chapters.length - 1).toInt();
      scrollOffset = progress.scrollOffset;
    }

    _currentChapterIndex = chapterIndex;
    _scrollOffset = scrollOffset;
    _readingPositionRevision++;
    return (chapterIndex: chapterIndex, scrollOffset: scrollOffset);
  }

  Future<void> _refreshRemoteReadingProgress(
    String bookId,
    int token, {
    required int baseChapterIndex,
    required double baseScrollOffset,
  }) async {
    final progress = await BookService.refreshRemoteReadingProgress(bookId)
        .catchError((_) => null);
    if (progress == null ||
        token != _openBookToken ||
        _disposed ||
        _book?.id != bookId) {
      return;
    }

    final userHasNotMoved = _currentChapterIndex == baseChapterIndex &&
        (_scrollOffset - baseScrollOffset).abs() < 0.5;
    if (!userHasNotMoved) return;

    _applyReadingProgress(progress);
    _checkBookmarkStatus();
    notifyListeners();
  }

  void goToChapter(int index, {double scrollOffset = 0.0}) {
    if (index >= 0 && index < _chapters.length) {
      _currentChapterIndex = index;
      _scrollOffset = scrollOffset;
      _readingPositionRevision++;
      _checkBookmarkStatus();
      _scheduleProgressSave();
      notifyListeners();
    }
  }

  void _checkBookmarkStatus() {
    _isBookmarked = _bookmarks.any(
      (b) => b.chapterIndex == _currentChapterIndex.toString(),
    );
  }

  Future<void> toggleBookmark() async {
    if (_book == null || currentChapter == null) return;
    final chapterIdx = _currentChapterIndex.toString();

    if (_isBookmarked) {
      // Remove bookmark
      final existing = _bookmarks.where((b) => b.chapterIndex == chapterIdx).toList();
      for (final bm in existing) {
        await BookService.deleteBookmark(bm.id);
        _bookmarks.remove(bm);
      }
      _isBookmarked = false;
    } else {
      // Add bookmark
      final plainText = EpubService.getPlainText(currentChapter!.content);
      final snippet = plainText.length > 30 ? plainText.substring(0, 30) : plainText;
      final bm = Bookmark(
        id: const Uuid().v4(),
        userId: _getUserId(),
        bookId: _book!.id,
        chapterIndex: chapterIdx,
        chapterTitle: currentChapter!.title,
        snippet: snippet,
        scrollOffset: _scrollOffset,
        progress: progress,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
      await BookService.insertBookmark(bm);
      _bookmarks.insert(0, bm);
      _isBookmarked = true;
    }
    notifyListeners();
  }

  void updateScrollOffset(double offset) {
    setScrollOffset(offset);
    _scheduleProgressSave();
  }

  Future<void> saveProgress() async {
    if (_book != null) {
      final now = DateTime.now().toUtc().toIso8601String();
      await BookService.saveReadingProgress(
        _book!.id,
        _currentChapterIndex.toString(),
        _scrollOffset,
        userId: _getUserId(),
        updatedAt: now,
      );
      await BookService.updateBook(
        _book!.copyWith(
          readingProgress: progress,
          lastOpenedAt: DateTime.now(),
          updatedAt: now,
        ),
      );
    }
  }

  void selectText(String text) {
    _selectedText = text;
    notifyListeners();
  }

  void clearSelection() {
    _selectedText = null;
    _showAiPanel = false;
    notifyListeners();
  }

  void toggleAiPanel() {
    _showAiPanel = !_showAiPanel;
    notifyListeners();
  }

  void showAiExplanation() {
    _showAiPanel = true;
    notifyListeners();
  }

  Future<void> addHighlight({
    required String selectedText,
    required String contextBefore,
    required String contextAfter,
    required int startOffset,
    required int endOffset,
    String color = '#B39DDB',
  }) async {
    if (_book == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final h = Highlight(
      id: const Uuid().v4(),
      userId: _getUserId(),
      bookId: _book!.id,
      chapterIndex: _currentChapterIndex.toString(),
      selectedText: selectedText,
      contextBefore: contextBefore,
      contextAfter: contextAfter,
      startOffset: startOffset,
      endOffset: endOffset,
      color: color,
      createdAt: DateTime.now(),
      updatedAt: now,
    );
    await BookService.insertHighlight(h);
    await BookService.insertUserEntry(
      UserEntry(
        id: const Uuid().v4(),
        userId: _getUserId(),
        source: 'highlight',
        bookId: _book!.id,
        bookTitle: _book!.title,
        chapterIndex: _currentChapterIndex.toString(),
        chapterTitle: currentChapter?.title ?? '',
        originalText: selectedText,
        autoTags: const ['划线'],
        metadataJson: jsonEncode({
          'color': color,
          'startOffset': startOffset,
          'endOffset': endOffset,
          'contextBefore': contextBefore,
          'contextAfter': contextAfter,
          'book_author': _book!.author,
          'book_cover': _book!.coverPath ?? '',
        }),
        createdAt: DateTime.now(),
        updatedAt: now,
      ),
    );
    _highlights.insert(0, h);
    notifyListeners();
  }

  Future<void> addThought({required String content}) async {
    if (_book == null || content.trim().isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final selectedText = _selectedText ?? '';
    final chapterTitle = currentChapter?.title ?? '';

    await BookService.insertNote(
      id: const Uuid().v4(),
      bookId: _book!.id,
      chapterIndex: _currentChapterIndex.toString(),
      selectedText: selectedText.isEmpty ? null : selectedText,
      chapterTitle: chapterTitle,
      content: content.trim(),
      userId: _getUserId(),
    );
    await BookService.insertUserEntry(
      UserEntry(
        id: const Uuid().v4(),
        userId: _getUserId(),
        source: 'thought',
        bookId: _book!.id,
        bookTitle: _book!.title,
        chapterIndex: _currentChapterIndex.toString(),
        chapterTitle: chapterTitle,
        originalText: selectedText,
        userInput: content.trim(),
        autoTags: const ['想法'],
        metadataJson: jsonEncode({
          'book_author': _book!.author,
          'book_cover': _book!.coverPath ?? '',
        }),
        createdAt: DateTime.now(),
        updatedAt: now,
      ),
    );
  }

  Future<void> updateHighlightNote(String id, String note) async {
    await BookService.updateHighlightNote(id, note);
    final idx = _highlights.indexWhere((h) => h.id == id);
    if (idx >= 0) {
      _highlights[idx] = Highlight(
        id: _highlights[idx].id,
        userId: _highlights[idx].userId,
        bookId: _highlights[idx].bookId,
        chapterIndex: _highlights[idx].chapterIndex,
        selectedText: _highlights[idx].selectedText,
        contextBefore: _highlights[idx].contextBefore,
        contextAfter: _highlights[idx].contextAfter,
        startOffset: _highlights[idx].startOffset,
        endOffset: _highlights[idx].endOffset,
        color: _highlights[idx].color,
        note: note,
        createdAt: _highlights[idx].createdAt,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
      notifyListeners();
    }
  }

  Future<void> deleteHighlight(String id) async {
    await BookService.deleteHighlight(id);
    _highlights.removeWhere((h) => h.id == id);
    notifyListeners();
  }

  bool _disposed = false;

  String _getUserId() {
    return AuthService.userId ?? '';
  }

  void _scheduleProgressSave() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(const Duration(seconds: 2), () {
      if (!_disposed) {
        saveProgress();
      }
    });
  }

  void cancelScheduledSave() {
    _progressSaveTimer?.cancel();
  }

  @override
  void dispose() {
    _progressSaveTimer?.cancel();
    _disposed = true;
    saveProgress(); // fire-and-forget: persists progress before disposal
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}
