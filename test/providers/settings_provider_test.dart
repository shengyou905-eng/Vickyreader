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
}
