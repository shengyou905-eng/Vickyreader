import 'package:ai_reader/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiService backend error mapping', () {
    test('maps timeouts to a readable message', () {
      expect(
        AiService.friendlyError(
          Exception('TimeoutException: Future not completed'),
        ),
        contains('思考得久'),
      );
    });

    test('does not expose raw fixed-prompt legacy errors', () {
      expect(
        AiService.friendlyError(Exception('请使用固定引导问题')),
        contains('支持自由提问'),
      );
    });
  });
}
