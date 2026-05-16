import 'package:flutter_test/flutter_test.dart';
import 'package:ai_reader/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const AiReaderApp());
    expect(find.text('知读'), findsOneWidget);
  });
}
