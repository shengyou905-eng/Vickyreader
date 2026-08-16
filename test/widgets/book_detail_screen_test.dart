import 'package:ai_reader/config/theme.dart';
import 'package:ai_reader/models/book.dart';
import 'package:ai_reader/providers/bookshelf_provider.dart';
import 'package:ai_reader/screens/bookshelf/book_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  Book book({double progress = 0}) => Book(
    id: 'book-1',
    title: '西方哲学史',
    author: '伯特兰·罗素',
    filePath: 'test.epub',
    description: '沿着哲学问题与时代背景展开的一部思想史。',
    addedAt: DateTime(2026),
    lastOpenedAt: DateTime(2026),
    readingProgress: progress,
  );

  Future<void> pumpAtWidth(
    WidgetTester tester, {
    required double width,
    required Book value,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => BookshelfProvider(),
        child: MaterialApp(
          theme: AppTheme.forTheme(AppThemeId.lavender),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: BookDetailScreen(initialBook: value),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows one book title and a clear start action at 360px', (
    tester,
  ) async {
    await pumpAtWidth(tester, width: 360, value: book());

    expect(find.text('西方哲学史'), findsOneWidget);
    expect(find.text('开始阅读'), findsOneWidget);
    expect(find.byKey(const ValueKey('book-detail-read-button')), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows progress in the continue action at iPhone width', (
    tester,
  ) async {
    await pumpAtWidth(
      tester,
      width: 393,
      value: book(progress: 0.42),
      textScale: 1.2,
    );

    expect(find.text('继续阅读 · 42%'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
