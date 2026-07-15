import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/constants.dart';
import 'app_http_client.dart';
import 'auth_service.dart';

class PrivacyService {
  static const _timeout = Duration(seconds: 20);
  static final Map<String, bool> _aiConsentCache = {};

  static Future<bool> hasAiConsent({bool force = false}) async {
    await AuthService.init();
    final userId = AuthService.userId;
    if (userId == null || userId.isEmpty) return false;
    if (!force && _aiConsentCache[userId] == true) return true;
    final data = await _send('GET', '/api/auth/ai-consent');
    final consented = data['consented'] == true;
    _aiConsentCache[userId] = consented;
    return consented;
  }

  static Future<void> acceptAiConsent() async {
    final data = await _send(
      'POST',
      '/api/auth/ai-consent',
      body: const {'accepted': true},
    );
    final userId = AuthService.userId;
    if (userId != null) _aiConsentCache[userId] = data['consented'] == true;
  }

  static Future<void> revokeAiConsent() async {
    await _send('DELETE', '/api/auth/ai-consent');
    final userId = AuthService.userId;
    if (userId != null) _aiConsentCache[userId] = false;
  }

  static Future<Map<String, dynamic>> getCommunityGuidelines() {
    return _send('GET', '/api/mingtai/community/guidelines');
  }

  static Future<void> acceptCommunityGuidelines(int version) async {
    await _send(
      'POST',
      '/api/mingtai/community/guidelines/accept',
      body: {'accepted': true, 'version': version},
    );
  }

  static Future<Map<String, dynamic>> getCommunityPrivacy() async {
    final data = await _send('GET', '/api/mingtai/community/privacy');
    return Map<String, dynamic>.from(data['settings'] as Map? ?? const {});
  }

  static Future<Map<String, dynamic>> updateCommunityPrivacy(
    Map<String, bool> settings,
  ) async {
    final data = await _send(
      'PUT',
      '/api/mingtai/community/privacy',
      body: settings,
    );
    return Map<String, dynamic>.from(data['settings'] as Map? ?? const {});
  }

  static Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
    String details = '',
  }) async {
    await _send(
      'POST',
      '/api/mingtai/community/reports',
      body: {
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason,
        'details': details,
      },
    );
  }

  static Future<void> setBlocked(String userId, bool blocked) {
    return _send(
      blocked ? 'POST' : 'DELETE',
      '/api/mingtai/community/profiles/$userId/block',
    ).then((_) {});
  }

  static Future<List<Map<String, dynamic>>> getBlockedUsers() async {
    final data = await _send('GET', '/api/mingtai/community/blocks');
    return (data['users'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  static Future<void> deleteAccount(String password) async {
    await _send('DELETE', '/api/auth/account', body: {'password': password});
  }

  static Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    await AuthService.init();
    final token = AuthService.token?.trim() ?? '';
    if (token.isEmpty) throw Exception('请先登录');
    final uri = Uri.parse('${AppConstants.apiBaseUrl}$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json; charset=utf-8',
    };
    late http.Response response;
    switch (method) {
      case 'POST':
        response = await AppHttp.client
            .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
            .timeout(_timeout);
        break;
      case 'PUT':
        response = await AppHttp.client
            .put(uri, headers: headers, body: jsonEncode(body ?? const {}))
            .timeout(_timeout);
        break;
      case 'DELETE':
        response = await AppHttp.client
            .delete(
              uri,
              headers: headers,
              body: body == null ? null : jsonEncode(body),
            )
            .timeout(_timeout);
        break;
      default:
        response = await AppHttp.client
            .get(uri, headers: headers)
            .timeout(_timeout);
        break;
    }
    Map<String, dynamic> data = const {};
    if (response.body.trim().isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        data['error']?.toString() ?? '请求失败 (${response.statusCode})',
      );
    }
    return data;
  }
}
