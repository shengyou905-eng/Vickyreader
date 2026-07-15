import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'app_http_client.dart';

class AppImageCache {
  AppImageCache._();

  static final BaseCacheManager manager = CacheManager(
    Config(
      'zhiduNetworkImages',
      stalePeriod: const Duration(days: 14),
      maxNrOfCacheObjects: 240,
      fileService: HttpFileService(httpClient: AppHttp.client),
    ),
  );
}
