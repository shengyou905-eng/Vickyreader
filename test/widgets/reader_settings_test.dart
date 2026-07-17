import 'package:ai_reader/config/reader_typography.dart';
import 'package:ai_reader/config/theme.dart';
import 'package:ai_reader/providers/settings_provider.dart';
import 'package:ai_reader/screens/reader/widgets/reader_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reading typography panel scrolls on a small phone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.loadSettings();
    await settings.activateBook('small-phone-book');
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      settings.dispose();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: ReaderSettings()),
        ),
      ),
    );

    expect(find.text('阅读排版'), findsOneWidget);
    expect(find.text('文楷'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('纸张背景'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview follows the active typography and paper settings', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.loadSettings();
    await settings.activateBook('live-preview-book');
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: ReaderSettings()),
        ),
      ),
    );

    settings.setReaderFontFamily(ReaderFontFamily.serif);
    settings.setFontSize(22);
    settings.setLineHeight(1.9);
    settings.setPageMargin(30);
    await settings.setThemeMode('green');
    await tester.pump();

    final preview = tester.widget<Text>(
      find.byKey(const ValueKey('reader-settings-preview-text')),
    );
    expect(preview.style?.fontFamily, 'SourceHanSerifCN');
    expect(preview.style?.fontSize, 22);
    expect(preview.style?.height, 1.9);
    expect(preview.style?.color, settings.textColor);

    final previewCard = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('reader-settings-preview-card')),
    );
    final decoration = previewCard.decoration! as BoxDecoration;
    final padding = previewCard.padding! as EdgeInsets;
    expect(decoration.color, settings.backgroundColor);
    expect(padding.left, greaterThan(20));
    expect(padding.right, greaterThan(20));
    await settings.flushTypographyPersistence();
  });

  testWidgets('font choices stay within a narrow phone width', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.loadSettings();
    await settings.activateBook('narrow-phone-book');
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      settings.dispose();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: ReaderSettings()),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('reader-font-system')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-font-serif')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-font-wenkai')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('font cards update selection and preview immediately', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.loadSettings();
    await settings.activateBook('font-preview-book');
    var styleChangeCount = 0;
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: ReaderSettings(
              onReaderStyleChanged: () => styleChangeCount++,
            ),
          ),
        ),
      ),
    );

    expect(settings.readerFontFamily, ReaderFontFamily.system);
    await tester.tap(find.text('宋体'));
    await tester.pump();
    expect(settings.readerFontFamily, ReaderFontFamily.serif);
    expect(styleChangeCount, 1);
    final songPreview = tester.widget<Text>(find.text('山川入卷').at(1));
    expect(songPreview.style?.fontFamily, 'SourceHanSerifCN');

    await tester.tap(find.text('文楷'));
    await tester.pump();
    expect(settings.readerFontFamily, ReaderFontFamily.wenkai);
    expect(styleChangeCount, 2);
    final wenkaiPreview = tester.widget<Text>(find.text('山川入卷').at(2));
    expect(wenkaiPreview.style?.fontFamily, 'LXGWWenKaiLite');

    await tester.tap(find.text('默认'));
    await tester.pump();
    expect(settings.readerFontFamily, ReaderFontFamily.system);
    expect(styleChangeCount, 3);
    final systemPreview = tester.widget<Text>(find.text('山川入卷').at(0));
    expect(systemPreview.style?.fontFamily, isNull);
    await settings.flushTypographyPersistence();
  });

  testWidgets('bundled Song and WenKai font files are available', (
    tester,
  ) async {
    final song = await rootBundle.load(
      'assets/fonts/SourceHanSerifCN-Regular.otf',
    );
    final wenkai = await rootBundle.load(
      'assets/fonts/LXGWWenKaiLite-Regular.ttf',
    );

    expect(song.lengthInBytes, greaterThan(1000000));
    expect(wenkai.lengthInBytes, greaterThan(1000000));
  });
}
