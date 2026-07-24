import 'package:ai_reader/utils/latest_request_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only the latest request token remains current', () {
    final guard = LatestRequestGuard();

    final first = guard.begin();
    final second = guard.begin();

    expect(guard.isCurrent(first), isFalse);
    expect(guard.isCurrent(second), isTrue);
  });

  test('invalidate prevents an in-flight request from applying', () {
    final guard = LatestRequestGuard();
    final request = guard.begin();

    guard.invalidate();

    expect(guard.isCurrent(request), isFalse);
  });
}
