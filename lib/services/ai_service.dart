import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/ai_conversation.dart';
import 'auth_service.dart';

class AiService {
  /// 小U解释：逐字流式返回
  static Stream<String> explainStream({
    required String selectedText,
    required String contextBefore,
    required String contextAfter,
    required String bookTitle,
    required String bookAuthor,
    List<AiMessage>? conversationHistory,
  }) {
    final history = (conversationHistory ?? [])
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    return _sseStream('/api/ai/explain', {
      'selectedText': selectedText,
      'contextBefore': contextBefore,
      'contextAfter': contextAfter,
      'bookTitle': bookTitle,
      'bookAuthor': bookAuthor,
      'history': history,
    });
  }

  /// 追问：逐字流式返回
  static Stream<String> chatStream({
    required String message,
    required List<AiMessage> conversationHistory,
  }) {
    final history = conversationHistory
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    return _sseStream('/api/ai/explain', {
      'message': message,
      'history': history,
    });
  }

  /// 连接后端 SSE，逐 chunk yield
  static Stream<String> _sseStream(
    String path,
    Map<String, dynamic> body,
  ) async* {
    final token = AuthService.token;
    if (token == null || token.isEmpty) {
      throw Exception('请先登录');
    }

    final request = http.Request(
      'POST',
      Uri.parse('${AppConstants.apiBaseUrl}$path'),
    );
    request.headers['Content-Type'] = 'application/json';
    request.headers['Authorization'] = 'Bearer $token';
    request.body = jsonEncode(body);

    final streamed = await request.send().timeout(const Duration(seconds: 10));

    if (streamed.statusCode != 200) {
      final errorBody = await streamed.stream.bytesToString();
      String errorMsg = '请求失败 (${streamed.statusCode})';
      try {
        final parsed = jsonDecode(errorBody);
        if (parsed['error'] != null) errorMsg = parsed['error'].toString();
      } catch (_) {}
      throw Exception(errorMsg);
    }

    await for (final line in streamed.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6).trim();
      if (data == '[DONE]') return;
      try {
        final parsed = jsonDecode(data);
        if (parsed['error'] != null) {
          throw Exception(parsed['error'].toString());
        }
        final content = parsed['content'] as String?;
        if (content != null && content.isNotEmpty) yield content;
      } catch (e) {
        if (e is Exception && e.toString().contains('error')) rethrow;
        // skip malformed SSE chunks
      }
    }
  }
}
