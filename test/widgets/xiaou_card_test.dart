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
}
