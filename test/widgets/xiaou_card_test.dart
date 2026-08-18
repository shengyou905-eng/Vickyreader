import 'package:ai_reader/config/theme.dart';
import 'package:ai_reader/screens/xiaou/widgets/xiaou_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'AI explanation card opens the complete draggable reading layer',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.forTheme(AppThemeId.lavender),
          home: const Scaffold(
            body: XiaouCard(
              source: 'ai_explanation',
              originalText: '权力不是某个人拥有的东西，而是一张关系网。',
              aiUnderstanding: '**重点**是权力通过关系持续发生。',
              aiTags: '小U解释, 小U解读, 权力, 权力',
              bookTitle: '规训与惩罚',
              chapterTitle: '第三章',
              createdAt: '2026-07-13T08:00:00Z',
              followUpCount: 2,
              latestFollowUpQuestion: '这和规训有什么关系？',
            ),
          ),
        ),
      );

      expect(find.text('展开完整解读'), findsOneWidget);
      expect(find.textContaining('**'), findsNothing);
      expect(find.text('小U解释'), findsNothing);
      expect(find.text('小U解读'), findsOneWidget);
      expect(find.text('权力'), findsOneWidget);
      expect(find.textContaining('2 次追问'), findsOneWidget);

      await tester.tap(find.text('展开完整解读'));
      await tester.pumpAndSettle();

      expect(find.text('选中的原文'), findsOneWidget);
      expect(find.text('小U的解读'), findsOneWidget);
      expect(find.textContaining('《规训与惩罚》'), findsOneWidget);
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    },
  );

  testWidgets('reader question card keeps its own source and detail title', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.forTheme(AppThemeId.lavender),
        home: const Scaffold(
          body: XiaouCard(
            entryId: 'question-entry',
            source: 'ai_question',
            originalText: '惩罚是一种权力技术。',
            userNote: '这句话里的技术是什么意思？',
            aiUnderstanding: '这里的技术不是器械，而是一套组织权力的方法。',
            bookTitle: '规训与惩罚',
            chapterTitle: '第一章',
          ),
        ),
      ),
    );

    expect(find.text('问小U'), findsOneWidget);
    expect(find.text('展开完整解读'), findsOneWidget);

    await tester.tap(find.text('展开完整解读'));
    await tester.pumpAndSettle();
    expect(find.text('问小U'), findsWidgets);
  });

  testWidgets('highlight card expands its original passage independently', (
    tester,
  ) async {
    const original =
        '这是一段足够长的划线原文，用来确认阅读痕迹卡片会先保持克制的三行预览，用户仍然可以自行展开并读完完整的句子，而不会跳转到别的页面。原文展开只影响这一段文字，不会改变书籍筛选、卡片排序或当前阅读位置。';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.forTheme(AppThemeId.lavender),
        home: const Scaffold(
          body: XiaouCard(
            source: 'highlight',
            originalText: original,
            bookTitle: '规训与惩罚',
            chapterTitle: '第一章',
          ),
        ),
      ),
    );

    final passage = find.text(original);
    expect((tester.widget<Text>(passage)).maxLines, 3);
    expect(find.text('展开原文'), findsOneWidget);

    await tester.tap(find.text('展开原文'));
    await tester.pumpAndSettle();

    expect((tester.widget<Text>(passage)).maxLines, isNull);
    expect(find.text('收起原文'), findsOneWidget);
  });
}
