import 'package:ai_reader/config/theme.dart';
import 'package:ai_reader/screens/reader/widgets/reader_question_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reader question sheet offers all available reading scopes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.forTheme(AppThemeId.lavender),
        home: Scaffold(
          body: ReaderQuestionSheet(
            readerContext: const ReaderQuestionContext(
              bookTitle: '规训与惩罚',
              bookAuthor: '福柯',
              chapterTitle: '第一章',
              selectedText: '惩罚是一种权力技术。',
              pageText: '这是当前页可见的文字。',
              chapterText: '这是当前章节的完整上下文。',
              contextBefore: '前文',
              contextAfter: '后文',
            ),
            initialScope: ReaderQuestionScope.selection,
            onSaveFirstAnswer: (_, _, _) async => 'entry-id',
            onSaveFollowUp: (_, _, _) async {},
          ),
        ),
      ),
    );

    expect(find.text('所选文字'), findsOneWidget);
    expect(find.text('当前页'), findsOneWidget);
    expect(find.text('本章'), findsOneWidget);
    expect(find.text('惩罚是一种权力技术。'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('本章'));
    await tester.pump();
    expect(find.text('这是当前章节的完整上下文。'), findsOneWidget);
  });
}
