import 'package:ai_reader/screens/reader/reader_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reader document navigation policy', () {
    test('allows local URLs used by Android and iOS WebViews', () {
      expect(isReaderDocumentNavigationAllowed('about:blank'), isTrue);
      expect(
        isReaderDocumentNavigationAllowed(
          'file:///var/mobile/Containers/Data/Application/book/ch_0.html',
        ),
        isTrue,
      );
      expect(
        isReaderDocumentNavigationAllowed(
          'applewebdata://reader.local/chapter/index.html',
        ),
        isTrue,
      );
      expect(
        isReaderDocumentNavigationAllowed(
          'data:text/html;charset=utf-8,%3Cp%3Etext%3C/p%3E',
        ),
        isTrue,
      );
    });

    test('blocks remote and invalid navigation', () {
      expect(
        isReaderDocumentNavigationAllowed('https://example.com/book'),
        isFalse,
      );
      expect(
        isReaderDocumentNavigationAllowed('http://example.com/book'),
        isFalse,
      );
      expect(isReaderDocumentNavigationAllowed(''), isFalse);
    });
  });
}
