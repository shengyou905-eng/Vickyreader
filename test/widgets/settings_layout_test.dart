import 'package:ai_reader/config/theme.dart';
import 'package:ai_reader/providers/auth_provider.dart';
import 'package:ai_reader/providers/settings_provider.dart';
import 'package:ai_reader/screens/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({SettingsProvider settings, AuthProvider auth})> pumpSettings(
    WidgetTester tester, {
    Size size = const Size(360, 780),
    double textScale = 1.2,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final settings = SettingsProvider();
    await settings.loadSettings();
    final auth = AuthProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: auth),
        ],
        child: MaterialApp(
          theme: AppTheme.forTheme(AppThemeId.lavender),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    return (settings: settings, auth: auth);
  }

  testWidgets('settings remains aligned at 360px and 1.2x text scale', (
    tester,
  ) async {
    final state = await pumpSettings(tester);

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      state.settings.dispose();
      state.auth.dispose();
    });

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('账户'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(find.text('界面氛围'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();

    expect(find.text('关于'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('privacy home has four actions and nests compliance documents', (
    tester,
  ) async {
    final state = await pumpSettings(tester, size: const Size(393, 852));

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      state.settings.dispose();
      state.auth.dispose();
    });

    await tester.scrollUntilVisible(
      find.text('AI 与数据授权'),
      180,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('AI 与数据授权'), findsOneWidget);
    expect(find.text('明台隐私与公开'), findsOneWidget);
    expect(find.text('社区安全'), findsOneWidget);
    expect(find.text('隐私与数据说明'), findsOneWidget);
    expect(find.text('小U与第三方 AI'), findsNothing);
    expect(find.text('社区规范与举报'), findsNothing);

    await tester.tap(find.text('隐私与数据说明'));
    await tester.pumpAndSettle();

    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('个人信息收集清单'), findsOneWidget);
    expect(find.text('第三方服务清单'), findsOneWidget);
    expect(find.text('AI 功能与数据处理'), findsOneWidget);
    expect(find.text('账号与数据删除'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
