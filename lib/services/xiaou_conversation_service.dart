import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/constants.dart';
import '../models/xiaou_conversation.dart';
import 'app_http_client.dart';
import 'auth_service.dart';

class XiaouConversationService {
  XiaouConversationService._();

  static const _timeout = Duration(seconds: 20);

  static Future<List<XiaouConversationSummary>> list({int limit = 40}) async {
    final uri = Uri.parse(
      '${AppConstants.apiBaseUrl}/api/xiaou/conversations',
    ).replace(queryParameters: {'limit': limit.toString()});
    final data = await _send('GET', uri);
    final rows = data['conversations'] as List? ?? const [];
    return rows
        .whereType<Map>()
        .map(
          (row) =>
              XiaouConversationSummary.fromJson(Map<String, dynamic>.from(row)),
        )
        .where((conversation) => conversation.id.isNotEmpty)
        .toList(growable: false);
  }

  static Future<XiaouConversationSummary> create({
    String kind = 'chat',
    String title = '',
    String bookId = '',
    String bookTitle = '',
  }) async {
    final data = await _send(
      'POST',
      Uri.parse('${AppConstants.apiBaseUrl}/api/xiaou/conversations'),
      body: {
        'kind': kind == 'xiaou_asks' ? 'xiaou_asks' : 'chat',
        'title': title,
        'book_id': bookId,
        'book_title': bookTitle,
      },
    );
    return XiaouConversationSummary.fromJson(
      Map<String, dynamic>.from(data['conversation'] as Map? ?? const {}),
    );
  }

  static Future<XiaouConversationThread> get(String conversationId) async {
    final safeId = Uri.encodeComponent(conversationId);
    final data = await _send(
      'GET',
      Uri.parse('${AppConstants.apiBaseUrl}/api/xiaou/conversations/$safeId'),
    );
    return XiaouConversationThread.fromJson(
      Map<String, dynamic>.from(data['conversation'] as Map? ?? const {}),
    );
  }

  static Future<void> appendMessage({
    required String conversationId,
    required String role,
    required String content,
    String status = 'completed',
  }) async {
    final safeId = Uri.encodeComponent(conversationId);
    await _send(
      'POST',
      Uri.parse(
        '${AppConstants.apiBaseUrl}/api/xiaou/conversations/$safeId/messages',
      ),
      body: {'role': role, 'content': content, 'status': status},
    );
  }

  static Future<void> delete(String conversationId) async {
    final safeId = Uri.encodeComponent(conversationId);
    await _send(
      'DELETE',
      Uri.parse('${AppConstants.apiBaseUrl}/api/xiaou/conversations/$safeId'),
      allowEmpty: true,
    );
  }

  static Future<Map<String, dynamic>> _send(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    bool allowEmpty = false,
  }) async {
    await AuthService.init();
    final token = AuthService.token?.trim() ?? '';
    if (token.isEmpty) throw Exception('请先登录');

    late final http.Response response;
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    switch (method) {
      case 'GET':
        response = await AppHttp.client
            .get(uri, headers: headers)
            .timeout(_timeout);
      case 'POST':
        response = await AppHttp.client
            .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
            .timeout(_timeout);
      case 'DELETE':
        response = await AppHttp.client
            .delete(uri, headers: headers)
            .timeout(_timeout);
      default:
        throw UnsupportedError('Unsupported method: $method');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.trim().isEmpty) return const {};
      return Map<String, dynamic>.from(
        jsonDecode(response.body) as Map? ?? const {},
      );
    }
    if (allowEmpty && response.statusCode == 204) return const {};
    throw Exception(_error(response));
  }

  static String _error(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map && data['error'] != null) {
        return data['error'].toString();
      }
    } catch (_) {}
    return '请求失败 (HTTP ${response.statusCode})';
  }
}
