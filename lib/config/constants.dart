import 'package:flutter/foundation.dart';

class AppConstants {
  static const String appName = '知读';
  static const String appTagline = '让阅读痕迹慢慢显影';

  static const int contextChars = 200;

  // Production uses the public HTTPS endpoint by default. Development and
  // staging builds can still override it with --dart-define=API_BASE_URL=...
  // Android release builds reject cleartext traffic at the platform layer.
  static const String _configuredApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.youxugarden.com',
  );
  static String get apiBaseUrl {
    final value = _configuredApiBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (value.isEmpty) {
      throw StateError(
        'API_BASE_URL is not configured. Pass it with --dart-define.',
      );
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw StateError('API_BASE_URL is invalid.');
    }
    if (kReleaseMode && uri.scheme != 'https') {
      throw StateError('Release builds require HTTPS.');
    }
    return value;
  }

  // Storage
  static const String dbName = 'ai_reader.db';
  static const int dbVersion = 13;
  static const List<String> supportedFormats = ['epub', 'txt', 'pdf'];
  static const String booksDir = 'books';

  // UI
  static const double bookCoverAspectRatio = 0.7;
  static const int bookshelfColumns = 3;
}
