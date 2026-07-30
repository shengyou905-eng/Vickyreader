import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum FirstUseGuide { readerLongPress, xiaouPresence, mingtaiIntroduction }

class FirstUseGuideService {
  static const _keyPrefix = 'first_use_guide_v1_';
  static FirstUseGuide? _claimedThisSession;

  static String _key(FirstUseGuide guide) => '$_keyPrefix${guide.name}';

  static Future<bool> claim(FirstUseGuide guide) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_key(guide)) == true) return false;
    if (_claimedThisSession != null && _claimedThisSession != guide) {
      return false;
    }
    _claimedThisSession ??= guide;
    return true;
  }

  static Future<void> complete(FirstUseGuide guide) async {
    _claimedThisSession ??= guide;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(guide), true);
  }

  static Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final guide in FirstUseGuide.values) {
      await prefs.remove(_key(guide));
    }
    _claimedThisSession = null;
  }

  @visibleForTesting
  static void resetSessionForTesting() {
    _claimedThisSession = null;
  }
}
