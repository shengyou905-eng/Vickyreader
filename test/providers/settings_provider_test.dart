import 'package:ai_reader/config/reader_paging_mode.dart';
import 'package:ai_reader/config/reader_typography.dart';
import 'package:ai_reader/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reader typography is stored independently for each book', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.loadSettings();

    await settings.activateBook('book-a');
    settings.setReaderFontFamily(ReaderFontFamily.wenkai);
    settings.setFontSize(22);
    settings.setLineHeight(1.9);
    settings.setPageMargin(28);
    await Future<void>.delayed(const Duration(milliseconds: 320));

    await settings.activateBook('book-b');
    expect(settings.readerFontFamily, ReaderFontFamily.system);
    expect(settings.fontSize, ReaderTypographyDefaults.fontSize);
    expect(settings.lineHeight, ReaderTypographyDefaults.lineHeight);
    expect(settings.pageMargin, ReaderTypographyDefaults.pageMargin);

    await settings.activateBook('book-a');
    expect(settings.readerFontFamily, ReaderFontFamily.wenkai);
    expect(settings.fontSize, 22);
    expect(settings.lineHeight, 1.9);
    expect(settings.pageMargin, 28);

    await settings.resetTypography();
    expect(settings.readerFontFamily, ReaderFontFamily.system);
    expect(settings.fontSize, ReaderTypographyDefaults.fontSize);
    settings.dispose();
  });

  test(
    'factory defaults do not inherit obsolete global typography keys',
    () async {
      SharedPreferences.setMockInitialValues({
        'fontSize': 16.0,
        'lineHeight': 2.0,
      });
      final settings = SettingsProvider();
      await settings.loadSettings();

      expect(settings.fontSize, ReaderTypographyDefaults.fontSize);
      expect(settings.lineHeight, ReaderTypographyDefaults.lineHeight);
      expect(settings.pageMargin, ReaderTypographyDefaults.pageMargin);
      settings.dispose();
    },
  );

  test('all reader font choices persist when the book is reopened', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.loadSettings();
    await settings.activateBook('font-book');

    for (final family in ReaderFontFamily.values) {
      settings.setReaderFontFamily(family);
      await settings.flushTypographyPersistence();

      await settings.activateBook('another-book');
      await settings.activateBook('font-book');
      expect(settings.readerFontFamily, family);
    }
    settings.dispose();
  });

  test(
    'forced flush persists pending typography without waiting for debounce',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.loadSettings();
      await settings.activateBook('flush-book');
      settings.setReaderFontFamily(ReaderFontFamily.serif);
      settings.setFontSize(21);
      settings.setLineHeight(1.8);
      settings.setPageMargin(26);

      await settings.flushTypographyPersistence();

      final restored = SettingsProvider();
      await restored.loadSettings();
      await restored.activateBook('flush-book');
      expect(restored.readerFontFamily, ReaderFontFamily.serif);
      expect(restored.fontSize, 21);
      expect(restored.lineHeight, 1.8);
      expect(restored.pageMargin, 26);
      restored.dispose();
      settings.dispose();
    },
  );

  test(
    'reset restores typography, paging mode and paper to factory defaults',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.loadSettings();
      await settings.activateBook('reset-book');
      settings.setReaderFontFamily(ReaderFontFamily.wenkai);
      settings.setFontSize(26);
      settings.setLineHeight(2.2);
      settings.setPageMargin(36);
      await settings.setReaderPagingMode(ReaderPagingMode.horizontal);
      await settings.setThemeMode('green');

      await settings.resetReaderSettings();

      expect(settings.readerFontFamily, ReaderTypographyDefaults.fontFamily);
      expect(settings.fontSize, ReaderTypographyDefaults.fontSize);
      expect(settings.lineHeight, ReaderTypographyDefaults.lineHeight);
      expect(settings.pageMargin, ReaderTypographyDefaults.pageMargin);
      expect(settings.readerPagingMode, ReaderPagingMode.vertical);
      expect(settings.themeMode, 'light');

      final restored = SettingsProvider();
      await restored.loadSettings();
      await restored.activateBook('reset-book');
      expect(restored.readerFontFamily, ReaderTypographyDefaults.fontFamily);
      expect(restored.fontSize, ReaderTypographyDefaults.fontSize);
      expect(restored.lineHeight, ReaderTypographyDefaults.lineHeight);
      expect(restored.pageMargin, ReaderTypographyDefaults.pageMargin);
      expect(restored.readerPagingMode, ReaderPagingMode.vertical);
      expect(restored.themeMode, 'light');
      restored.dispose();
      settings.dispose();
    },
  );
}
