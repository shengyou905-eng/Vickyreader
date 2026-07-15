import 'package:http/http.dart' as http;

import 'src/platform_http_client_stub.dart'
    if (dart.library.io) 'src/platform_http_client_io.dart'
    as platform;

/// Shared HTTP entry point for API calls and short-lived transfer clients.
///
/// iOS/macOS use Foundation's URL loading system and Android uses Cronet so
/// requests follow the platform VPN and proxy configuration.
class AppHttp {
  AppHttp._();

  static final http.Client client = platform.createPlatformHttpClient();

  static http.Client createClient() => platform.createPlatformHttpClient();
}
