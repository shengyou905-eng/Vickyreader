import 'dart:ui';

/// Keeps non-widget services aligned with the locale selected in Settings.
class AppLocaleState {
  AppLocaleState._();

  static String _languageCode = _platformLanguageCode();

  static String get languageCode => _languageCode;
  static bool get isEnglish => _languageCode == 'en';

  static void sync(String setting) {
    _languageCode = switch (setting) {
      'zh' => 'zh',
      'en' => 'en',
      _ => _platformLanguageCode(),
    };
  }

  static String _platformLanguageCode() {
    return PlatformDispatcher.instance.locale.languageCode == 'zh'
        ? 'zh'
        : 'en';
  }
}
