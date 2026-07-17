import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/reader_paging_mode.dart';
import '../config/reader_typography.dart';
import '../config/theme.dart';

class SettingsProvider extends ChangeNotifier {
  double _fontSize = ReaderTypographyDefaults.fontSize;
  double _lineHeight = ReaderTypographyDefaults.lineHeight;
  double _pageMargin = ReaderTypographyDefaults.pageMargin;
  ReaderFontFamily _readerFontFamily = ReaderTypographyDefaults.fontFamily;

  double _defaultFontSize = ReaderTypographyDefaults.fontSize;
  double _defaultLineHeight = ReaderTypographyDefaults.lineHeight;
  double _defaultPageMargin = ReaderTypographyDefaults.pageMargin;
  ReaderFontFamily _defaultReaderFontFamily =
      ReaderTypographyDefaults.fontFamily;

  String _themeMode = 'light';
  AppThemeId _appThemeId = AppThemeId.lavender;
  bool _syncEnabled = false;
  ReaderPagingMode _readerPagingMode = ReaderPagingMode.vertical;
  bool _loaded = false;
  String? _activeBookId;
  String? _loadingBookId;
  Timer? _typographyPersistTimer;

  double get fontSize => _fontSize;
  double get lineHeight => _lineHeight;
  double get pageMargin => _pageMargin;
  ReaderFontFamily get readerFontFamily => _readerFontFamily;
  String get themeMode => _themeMode;
  AppThemeId get appThemeId => _appThemeId;
  bool get syncEnabled => _syncEnabled;
  ReaderPagingMode get readerPagingMode => _readerPagingMode;
  bool get isLoaded => _loaded;
  String? get activeBookId => _activeBookId;

  bool typographyReadyFor(String bookId) =>
      _activeBookId == bookId && _loadingBookId == null;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _defaultFontSize =
        prefs.getDouble('reader_default_font_size') ??
        ReaderTypographyDefaults.fontSize;
    _defaultLineHeight =
        prefs.getDouble('reader_default_line_height') ??
        ReaderTypographyDefaults.lineHeight;
    _defaultPageMargin =
        prefs.getDouble('reader_default_page_margin') ??
        ReaderTypographyDefaults.pageMargin;
    _defaultReaderFontFamily = ReaderFontFamily.fromStorage(
      prefs.getString('reader_default_font_family'),
    );

    _themeMode = prefs.getString('themeMode') ?? 'light';
    _appThemeId = AppThemeId.fromStorage(prefs.getString('app_theme_id'));
    _syncEnabled = prefs.getBool('syncEnabled') ?? false;
    _readerPagingMode = ReaderPagingMode.fromStorage(
      prefs.getString('reader_paging_mode') ??
          prefs.getString('reader_layout_mode'),
    );

    final bookId = _activeBookId;
    if (bookId == null) {
      _useDefaultTypography();
    } else {
      _loadBookTypography(prefs, bookId);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> activateBook(String bookId) async {
    if (typographyReadyFor(bookId)) return;
    await flushTypographyPersistence();
    _loadingBookId = bookId;
    final prefs = await SharedPreferences.getInstance();
    if (_loadingBookId != bookId) return;
    _activeBookId = bookId;
    _loadBookTypography(prefs, bookId);
    _loadingBookId = null;
    notifyListeners();
  }

  void setReaderFontFamily(ReaderFontFamily family) {
    if (_readerFontFamily == family) return;
    _readerFontFamily = family;
    notifyListeners();
    _scheduleTypographyPersistence();
  }

  void setFontSize(double size) {
    if (_fontSize == size) return;
    _fontSize = size;
    notifyListeners();
    _scheduleTypographyPersistence();
  }

  void setLineHeight(double height) {
    if (_lineHeight == height) return;
    _lineHeight = height;
    notifyListeners();
    _scheduleTypographyPersistence();
  }

  void setPageMargin(double margin) {
    if (_pageMargin == margin) return;
    _pageMargin = margin;
    notifyListeners();
    _scheduleTypographyPersistence();
  }

  Future<void> resetTypography() async {
    _typographyPersistTimer?.cancel();
    _useDefaultTypography();
    notifyListeners();

    final bookId = _activeBookId;
    if (bookId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final prefix = _bookTypographyPrefix(bookId);
    await Future.wait([
      prefs.remove('${prefix}font_family'),
      prefs.remove('${prefix}font_size'),
      prefs.remove('${prefix}line_height'),
      prefs.remove('${prefix}page_margin'),
    ]);
  }

  Future<void> resetReaderSettings() async {
    _typographyPersistTimer?.cancel();
    _readerFontFamily = ReaderTypographyDefaults.fontFamily;
    _fontSize = ReaderTypographyDefaults.fontSize;
    _lineHeight = ReaderTypographyDefaults.lineHeight;
    _pageMargin = ReaderTypographyDefaults.pageMargin;
    _readerPagingMode = ReaderPagingMode.vertical;
    _themeMode = 'light';
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final writes = <Future<bool>>[
      prefs.setString(
        'reader_paging_mode',
        ReaderPagingMode.vertical.storageValue,
      ),
      prefs.setString('themeMode', 'light'),
    ];
    final bookId = _activeBookId;
    if (bookId == null) {
      _defaultReaderFontFamily = ReaderTypographyDefaults.fontFamily;
      _defaultFontSize = ReaderTypographyDefaults.fontSize;
      _defaultLineHeight = ReaderTypographyDefaults.lineHeight;
      _defaultPageMargin = ReaderTypographyDefaults.pageMargin;
      writes.addAll([
        prefs.setString(
          'reader_default_font_family',
          ReaderTypographyDefaults.fontFamily.storageValue,
        ),
        prefs.setDouble(
          'reader_default_font_size',
          ReaderTypographyDefaults.fontSize,
        ),
        prefs.setDouble(
          'reader_default_line_height',
          ReaderTypographyDefaults.lineHeight,
        ),
        prefs.setDouble(
          'reader_default_page_margin',
          ReaderTypographyDefaults.pageMargin,
        ),
      ]);
    } else {
      final prefix = _bookTypographyPrefix(bookId);
      writes.addAll([
        prefs.setString(
          '${prefix}font_family',
          ReaderTypographyDefaults.fontFamily.storageValue,
        ),
        prefs.setDouble(
          '${prefix}font_size',
          ReaderTypographyDefaults.fontSize,
        ),
        prefs.setDouble(
          '${prefix}line_height',
          ReaderTypographyDefaults.lineHeight,
        ),
        prefs.setDouble(
          '${prefix}page_margin',
          ReaderTypographyDefaults.pageMargin,
        ),
      ]);
    }
    await Future.wait(writes);
  }

  Future<void> flushTypographyPersistence() async {
    final bookId = _activeBookId;
    if (bookId == null) return;
    _typographyPersistTimer?.cancel();
    await _persistBookTypography(bookId);
  }

  /// Reserved for a later "apply to all books" action.
  /// Existing per-book overrides are cleared so the current typography becomes
  /// the new default for every book.
  Future<void> applyTypographyToAllBooks() async {
    _typographyPersistTimer?.cancel();
    _defaultReaderFontFamily = _readerFontFamily;
    _defaultFontSize = _fontSize;
    _defaultLineHeight = _lineHeight;
    _defaultPageMargin = _pageMargin;

    final prefs = await SharedPreferences.getInstance();
    final bookKeys = prefs
        .getKeys()
        .where((key) => key.startsWith('reader.book.'))
        .toList(growable: false);
    for (final key in bookKeys) {
      await prefs.remove(key);
    }
    await Future.wait([
      prefs.setString(
        'reader_default_font_family',
        _defaultReaderFontFamily.storageValue,
      ),
      prefs.setDouble('reader_default_font_size', _defaultFontSize),
      prefs.setDouble('reader_default_line_height', _defaultLineHeight),
      prefs.setDouble('reader_default_page_margin', _defaultPageMargin),
    ]);
  }

  Future<void> setThemeMode(String mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', mode);
  }

  Future<void> setAppThemeId(AppThemeId themeId) async {
    if (_appThemeId == themeId) return;
    _appThemeId = themeId;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_theme_id', themeId.storageValue);
  }

  Future<void> setSyncEnabled(bool enabled) async {
    _syncEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('syncEnabled', enabled);
  }

  Future<void> setReaderPagingMode(ReaderPagingMode mode) async {
    _readerPagingMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reader_paging_mode', mode.storageValue);
  }

  void _loadBookTypography(SharedPreferences prefs, String bookId) {
    final prefix = _bookTypographyPrefix(bookId);
    _readerFontFamily = ReaderFontFamily.fromStorage(
      prefs.getString('${prefix}font_family') ??
          _defaultReaderFontFamily.storageValue,
    );
    _fontSize = prefs.getDouble('${prefix}font_size') ?? _defaultFontSize;
    _lineHeight = prefs.getDouble('${prefix}line_height') ?? _defaultLineHeight;
    _pageMargin = prefs.getDouble('${prefix}page_margin') ?? _defaultPageMargin;
  }

  void _useDefaultTypography() {
    _readerFontFamily = _defaultReaderFontFamily;
    _fontSize = _defaultFontSize;
    _lineHeight = _defaultLineHeight;
    _pageMargin = _defaultPageMargin;
  }

  void _scheduleTypographyPersistence() {
    final bookId = _activeBookId;
    if (bookId == null) return;
    _typographyPersistTimer?.cancel();
    _typographyPersistTimer = Timer(
      const Duration(milliseconds: 240),
      () => unawaited(_persistBookTypography(bookId)),
    );
  }

  Future<void> _persistBookTypography(String bookId) async {
    if (_activeBookId != bookId) return;
    final prefs = await SharedPreferences.getInstance();
    final prefix = _bookTypographyPrefix(bookId);
    await Future.wait([
      prefs.setString('${prefix}font_family', _readerFontFamily.storageValue),
      prefs.setDouble('${prefix}font_size', _fontSize),
      prefs.setDouble('${prefix}line_height', _lineHeight),
      prefs.setDouble('${prefix}page_margin', _pageMargin),
    ]);
  }

  String _bookTypographyPrefix(String bookId) {
    final encoded = base64Url.encode(utf8.encode(bookId)).replaceAll('=', '');
    return 'reader.book.$encoded.';
  }

  Color get backgroundColor {
    switch (_themeMode) {
      case 'sepia':
        return const Color(0xFFF5ECD7);
      case 'green':
        return const Color(0xFFEAF4E3);
      case 'dark':
        return const Color(0xFF1A1A1A);
      default:
        return Colors.white;
    }
  }

  Color get textColor {
    switch (_themeMode) {
      case 'dark':
        return const Color(0xFFD0D0D0);
      case 'green':
        return const Color(0xFF223229);
      default:
        return const Color(0xFF1A1A1A);
    }
  }

  @override
  void dispose() {
    _typographyPersistTimer?.cancel();
    super.dispose();
  }
}
