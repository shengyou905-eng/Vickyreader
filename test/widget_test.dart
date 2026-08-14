import 'package:flutter_test/flutter_test.dart';
import 'package:ai_reader/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App can launch in English', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'locale_code': 'en'});
    await tester.pumpWidget(const AiReaderApp());
    await tester.pumpAndSettle();
    expect(find.text('ReadU'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Xiaou'), findsOneWidget);
    expect(find.text('Free Notes'), findsOneWidget);
    expect(find.text('Mingtai'), findsOneWidget);
  });
}
