import 'package:ai_reader/config/theme.dart';
import 'package:ai_reader/screens/reader/widgets/selection_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selection menu exposes ask XiaoU without overflowing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var asked = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.forTheme(AppThemeId.lavender),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SelectionMenu(
              onExplain: () {},
              onAsk: () => asked = true,
              onHighlight: (_) {},
              onNote: () {},
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('解读'), findsOneWidget);
    expect(find.text('提问'), findsOneWidget);
    expect(find.text('想法'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('提问'));
    expect(asked, isTrue);
  });
}
