import 'package:ai_reader/config/theme.dart';
import 'package:ai_reader/screens/xiaou/widgets/xiaou_swipe_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('right swipe only reveals actions and never executes them', (
    tester,
  ) async {
    var importantCount = 0;
    var deleteCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.forTheme(AppThemeId.lavender),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 160,
              child: XiaouSwipeActions(
                isImportant: false,
                onToggleImportant: () => importantCount++,
                onDelete: () => deleteCount++,
                child: const ColoredBox(
                  color: Colors.white,
                  child: Center(child: Text('阅读痕迹')),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.text('阅读痕迹'), const Offset(170, 0));
    await tester.pumpAndSettle();

    expect(find.text('标记重要'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(importantCount, 0);
    expect(deleteCount, 0);

    await tester.tap(find.text('标记重要'));
    await tester.pumpAndSettle();
    expect(importantCount, 1);
    expect(deleteCount, 0);
  });
}
