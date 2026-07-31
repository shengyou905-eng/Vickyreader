import 'package:ai_reader/config/theme.dart';
import 'package:ai_reader/screens/xiaou/topic_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final items = <Map<String, dynamic>>[
    {
      'book_title': '一间自己的房间',
      'original_text': '一个人必须有自己的房间，才能安静地写作。',
      'user_note': '这里谈的不只是空间，也是在谈主体性。',
      'ai_tags': '主体性',
      'created_at': '2026-07-30T08:00:00.000Z',
    },
  ];

  for (final themeId in [AppThemeId.lavender, AppThemeId.sage]) {
    testWidgets('topic page renders with ${themeId.label} theme', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.forTheme(themeId),
          home: XiaouTopicScreen(tag: '主体性', items: items),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('主体性'), findsOneWidget);
      expect(find.text('一间自己的房间'), findsOneWidget);
      expect(find.textContaining('1 条摘录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
