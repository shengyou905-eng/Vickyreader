class AppConstants {
  static const String appName = '知读';
  static const String appTagline = '让阅读痕迹慢慢显影';

  static const int contextChars = 200;

  // Self-hosted backend (生产环境必须使用 HTTPS)
  // 开发调试:
  //   Android 模拟器:  'http://10.0.2.2:3000'
  //   iOS 模拟器:      'http://localhost:3000'
  //   真机调试:         'http://<你的局域网IP>:3000'
  // 生产环境:          'https://your-domain.com'
  static const String apiBaseUrl = 'http://101.32.186.151:3000';

  // Storage
  static const String dbName = 'ai_reader.db';
  static const int dbVersion = 11;
  static const List<String> supportedFormats = ['epub', 'txt', 'pdf'];
  static const String booksDir = 'books';

  // UI
  static const double bookCoverAspectRatio = 0.7;
  static const int bookshelfColumns = 3;
}
