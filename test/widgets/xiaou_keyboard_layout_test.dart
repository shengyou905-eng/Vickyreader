import 'package:ai_reader/config/theme.dart';
import 'package:ai_reader/screens/xiaou/widgets/xiaou_presence_orb.dart';
import 'package:ai_reader/screens/xiaou/xiaou_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildScreen({required double keyboardInset}) {
    return MaterialApp(
      theme: AppTheme.forTheme(AppThemeId.lavender),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          viewPadding: const EdgeInsets.only(bottom: 24),
          padding: EdgeInsets.only(bottom: keyboardInset == 0 ? 24 : 0),
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
        ),
        child: const XiaouHomeScreen(autoLoad: false),
      ),
    );
  }

  testWidgets('keyboard does not move the Xiaou orb', (tester) async {
    await tester.pumpWidget(buildScreen(keyboardInset: 0));
    await tester.pump();

    final orbFinder = find.byType(XiaouPresenceOrb);
    final initialRect = tester.getRect(orbFinder);
    final searchFinder = find.byType(TextField).first;

    await tester.tap(searchFinder);
    await tester.enterText(searchFinder, '第二性');
    await tester.pump();

    await tester.pumpWidget(buildScreen(keyboardInset: 280));
    await tester.pump();

    expect(tester.getRect(orbFinder), initialRect);

    await tester.enterText(searchFinder, '第二');
    await tester.pumpWidget(buildScreen(keyboardInset: 360));
    await tester.pump();

    expect(tester.getRect(orbFinder), initialRect);

    await tester.enterText(searchFinder, '');
    await tester.pumpWidget(buildScreen(keyboardInset: 0));
    await tester.pump();

    expect(tester.getRect(orbFinder), initialRect);
    expect(
      tester
          .widget<Scaffold>(find.byType(Scaffold).first)
          .resizeToAvoidBottomInset,
      isFalse,
    );
  });

  testWidgets('keyboard inset is applied only to scrollable content', (
    tester,
  ) async {
    await tester.pumpWidget(buildScreen(keyboardInset: 0));
    await tester.pump();

    final spacerFinder = find.byKey(
      const ValueKey('xiaou-scroll-bottom-inset'),
    );
    expect(tester.widget<SizedBox>(spacerFinder).height, 112);

    await tester.pumpWidget(buildScreen(keyboardInset: 320));
    await tester.pump();

    expect(tester.widget<SizedBox>(spacerFinder).height, 432);
    expect(find.text('找一句话、一本书或一个想法'), findsOneWidget);

    final readingTraces = find.text('阅读痕迹');
    final initialTop = tester.getTopLeft(readingTraces).dy;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -180));
    await tester.pump();

    expect(tester.getTopLeft(readingTraces).dy, lessThan(initialTop));
  });
}
