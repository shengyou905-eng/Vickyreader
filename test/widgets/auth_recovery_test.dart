import 'package:ai_reader/config/theme.dart';
import 'package:ai_reader/l10n/l10n.dart';
import 'package:ai_reader/providers/auth_provider.dart';
import 'package:ai_reader/screens/auth/auth_screen.dart';
import 'package:ai_reader/screens/auth/password_reset_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget testApp(Widget home, {AuthProvider? auth}) {
    final child = MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.forTheme(AppThemeId.lavender),
      home: home,
    );
    return auth == null
        ? child
        : ChangeNotifierProvider.value(value: auth, child: child);
  }

  testWidgets('login exposes the forgot-password flow', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthProvider();
    addTearDown(auth.dispose);
    await tester.pumpWidget(testApp(const AuthScreen(), auth: auth));
    await tester.pump();

    expect(find.text('忘记密码？'), findsOneWidget);
    await tester.tap(find.text('忘记密码？'));
    await tester.pumpAndSettle();

    expect(find.text('找回密码'), findsWidgets);
    expect(find.textContaining('30 分钟'), findsOneWidget);
    expect(find.text('发送重置邮件'), findsOneWidget);
  });

  testWidgets('reset screen rejects mismatched passwords before networking', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(const ResetPasswordScreen(token: 'one-time-token')),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '新密码'),
      'password-one',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '再次输入新密码'),
      'password-two',
    );
    await tester.tap(find.text('重置密码'));
    await tester.pump();

    expect(find.text('两次输入的密码不一致'), findsOneWidget);
  });
}
