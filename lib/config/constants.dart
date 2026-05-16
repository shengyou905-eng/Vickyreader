class AppConstants {
  static const String appName = '知读';
  static const String appTagline = 'AI辅助阅读';

  // DeepSeek API
  static const String deepseekBaseUrl = 'https://api.deepseek.com';
  static const String deepseekModel = 'deepseek-chat';
  static const int contextChars = 200;

  // Self-hosted backend (生产环境必须使用 HTTPS)
  // 开发调试:
  //   Android 模拟器:  'http://10.0.2.2:3000'
  //   iOS 模拟器:      'http://localhost:3000'
  //   真机调试:         'http://<你的局域网IP>:3000'
  // 生产环境:          'https://your-domain.com'
  static const String apiBaseUrl = 'http://192.168.10.9:3000';

  // Storage
  static const String dbName = 'ai_reader.db';
  static const int dbVersion = 9;
  static const List<String> supportedFormats = ['epub', 'txt', 'pdf'];
  static const String booksDir = 'books';

  // UI
  static const double bookCoverAspectRatio = 0.7;
  static const int bookshelfColumns = 3;
}
