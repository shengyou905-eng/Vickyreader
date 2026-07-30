import 'package:ai_reader/services/first_use_guide_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FirstUseGuideService.resetSessionForTesting();
  });

  test('only one guide can claim a single app session', () async {
    expect(
      await FirstUseGuideService.claim(FirstUseGuide.readerLongPress),
      isTrue,
    );
    expect(
      await FirstUseGuideService.claim(FirstUseGuide.xiaouPresence),
      isFalse,
    );
  });

  test('completed guide stays hidden in a new session', () async {
    await FirstUseGuideService.complete(FirstUseGuide.readerLongPress);
    FirstUseGuideService.resetSessionForTesting();

    expect(
      await FirstUseGuideService.claim(FirstUseGuide.readerLongPress),
      isFalse,
    );
    expect(
      await FirstUseGuideService.claim(FirstUseGuide.xiaouPresence),
      isTrue,
    );
  });

  test('reset makes completed guides available again', () async {
    await FirstUseGuideService.complete(FirstUseGuide.mingtaiIntroduction);
    await FirstUseGuideService.resetAll();

    expect(
      await FirstUseGuideService.claim(FirstUseGuide.mingtaiIntroduction),
      isTrue,
    );
  });
}
