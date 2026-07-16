import 'package:ai_reader/config/theme.dart';
import 'package:ai_reader/providers/settings_provider.dart';
import 'package:ai_reader/screens/reader/widgets/reader_settings.dart';
import 'package:flutter/material.dart';
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

    expect(find.text('纸张'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
