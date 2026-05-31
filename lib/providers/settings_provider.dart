import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/reader_paging_mode.dart';
import '../config/theme.dart';

class SettingsProvider extends ChangeNotifier {
  double _fontSize = 18.0;
  double _lineHeight = 1.6;
  String _themeMode = 'light'; // 'light', 'sepia', 'dark'
  AppThemeId _appThemeId = AppThemeId.lavender;
  bool _syncEnabled = false;
  ReaderPagingMode _readerPagingMode = ReaderPagingMode.vertical;
  bool _loaded = false;

  double get fontSize => _fontSize;
  double get lineHeight => _lineHeight;
  String get themeMode => _themeMode;
  AppThemeId get appThemeId => _appThemeId;
  bool get syncEnabled => _syncEnabled;
  ReaderPagingMode get readerPagingMode => _readerPagingMode;
  bool get isLoaded => _loaded;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _fontSize = prefs.getDouble('fontSize') ?? 18.0;
    _lineHeight = prefs.getDouble('lineHeight') ?? 1.6;
    _themeMode = prefs.getString('themeMode') ?? 'light';
    _appThemeId = AppThemeId.fromStorage(prefs.getString('app_theme_id'));
    _syncEnabled = prefs.getBool('syncEnabled') ?? false;
    _readerPagingMode = ReaderPagingMode.fromStorage(
      prefs.getString('reader_paging_mode') ??
          prefs.getString('reader_layout_mode'),
    );
    _loaded = true;
    notifyListeners();
  }

  Future<void> setFontSize(double size) async {
    _fontSize = size;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fontSize', size);
    notifyListeners();
  }

  Future<void> setLineHeight(double height) async {
    _lineHeight = height;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('lineHeight', height);
    notifyListeners();
  }

  Future<void> setThemeMode(String mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', mode);
    notifyListeners();
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('syncEnabled', enabled);
    notifyListeners();
  }

  Future<void> setReaderPagingMode(ReaderPagingMode mode) async {
    _readerPagingMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reader_paging_mode', mode.storageValue);
    notifyListeners();
  }

  Color get backgroundColor {
    switch (_themeMode) {
      case 'sepia':
        return const Color(0xFFF5ECD7);
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
      default:
        return const Color(0xFF1A1A1A);
    }
  }
}
