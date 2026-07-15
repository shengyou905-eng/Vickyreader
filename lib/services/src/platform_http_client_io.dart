import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:cupertino_http/cupertino_http.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createPlatformHttpClient() {
  if (Platform.isIOS || Platform.isMacOS) {
    return CupertinoClient.defaultSessionConfiguration();
  }

  if (Platform.isAndroid) {
    try {
      final engine = CronetEngine.build(
        cacheMode: CacheMode.memory,
        cacheMaxSize: 4 * 1024 * 1024,
        enableBrotli: true,
        enableHttp2: true,
        userAgent: 'ZhiDu/1.0',
      );
      return CronetClient.fromCronetEngine(engine, closeEngine: true);
    } catch (_) {
      // Older Android devices may not provide Cronet. Keep the app usable
      // with the socket client instead of failing during startup.
    }
  }

  return IOClient(HttpClient()..userAgent = 'ZhiDu/1.0');
}
