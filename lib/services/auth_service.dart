import 'bmob_api.dart';

class AuthService {
  static final BmobApi _api = BmobApi.instance;

  static Future<void> init() async {
    await _api.init();
  }

  static bool get isLoggedIn => _api.isLoggedIn;
  static String? get userId => _api.userId;
  static String? get email => _api.email;
  static String? get token => _api.token;
  static bool get hasPassword => _api.hasPassword;
  static bool get appleLinked => _api.appleLinked;

  static Future<Map<String, dynamic>?> signUp(
    String email,
    String password,
  ) async {
    final result = await _api.signUp(email, password);
    return result;
  }

  static Future<Map<String, dynamic>?> signIn(
    String email,
    String password,
  ) async {
    final result = await _api.signIn(email, password);
    return result;
  }

  static Future<void> signOut() async {
    await _api.signOut();
  }

  static Future<Map<String, dynamic>> prepareAppleAuth() {
    return _api.prepareAppleAuth();
  }

  static Future<Map<String, dynamic>> completeAppleAuth({
    required Map<String, dynamic> credential,
    required bool bind,
  }) {
    return _api.completeAppleAuth(credential: credential, bind: bind);
  }
}
