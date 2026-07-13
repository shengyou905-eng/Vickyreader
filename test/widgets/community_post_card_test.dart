import 'package:ai_reader/config/theme.dart';
import 'package:ai_reader/models/mingtai_community.dart';
import 'package:ai_reader/screens/mingtai/community_mingtai_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('public excerpt expands and collapses inside the post card', (
    tester,
  ) async {
    const excerpt =
        '在这种生产制度中，劳动力乃至人的肉体没有在工业经济中所赋予的那种效用和商业价值。'
        '刑罚因此不仅针对身体，也开始进入时间、秩序与日常生活。';
    final post = CommunityPost(
      id: 'post-1',
      userId: 'user-1',
      bookId: 'book-1',
      postType: 'fragment_thought',
      content: '死亡变成夸亮的意义工具。',
      quotedText: excerpt,
      chapterLabel: '第二章',
      bookTitle: '规训与惩罚',
      bookAuthor: '米歇尔·福柯',
      bookCoverUrl: '',
      nickname: '读者',
      avatarUrl: '',
      commentCount: 0,
      resonanceCount: 0,
      viewerResonated: false,
      createdAt: DateTime(2026, 7, 13),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.forTheme(AppThemeId.lavender),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CommunityPostCard(
              post: post,
              onBook: null,
              onProfile: null,
              onComments: () {},
            ),
          ),
        ),
      ),
    );

    final originalFinder = find.text('原文 · $excerpt');
    expect(find.text('展开原文'), findsOneWidget);
    expect(tester.widget<Text>(originalFinder).maxLines, 2);

    await tester.tap(find.text('展开原文'));
    await tester.pump();

    expect(find.text('收起原文'), findsOneWidget);
    expect(tester.widget<Text>(originalFinder).maxLines, isNull);
  });
}
