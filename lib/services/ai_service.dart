import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/ai_conversation.dart';
import 'auth_service.dart';

class AiService {
  /// 小U解释：选中文字 → 后端 /api/ai/explain（SSE 流式）
  static Future<String> explain({
    required String selectedText,
    required String contextBefore,
    required String contextAfter,
    required String bookTitle,
    required String bookAuthor,
    List<AiMessage>? conversationHistory,
  }) async {
    final history = (conversationHistory ?? [])
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    return _streamFromBackend('/api/ai/explain', {
      'selectedText': selectedText,
      'contextBefore': contextBefore,
      'contextAfter': contextAfter,
      'bookTitle': bookTitle,
      'bookAuthor': bookAuthor,
      'history': history,
    });
  }

  /// 追问：延续解释对话 → 后端 /api/ai/explain（message 模式）
  static Future<String> chat({
    required String message,
    required List<AiMessage> conversationHistory,
  }) async {
    final history = conversationHistory
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    return _streamFromBackend('/api/ai/explain', {
      'message': message,
      'history': history,
    });
  }

  /// 发送 POST 到后端，收集 SSE 流式响应为完整字符串
  static Future<String> _streamFromBackend(
    String path,
    Map<String, dynamic> body,
  ) async {
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

    final buffer = StringBuffer();
    final completer = Completer<String>();

    streamed.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (!line.startsWith('data: ')) return;
        final data = line.substring(6).trim();
        if (data == '[DONE]') {
          completer.complete(buffer.toString());
          return;
        }
        try {
          final parsed = jsonDecode(data);
          if (parsed['error'] != null) {
            completer.completeError(Exception(parsed['error'].toString()));
            return;
          }
          final content = parsed['content'] as String?;
          if (content != null) buffer.write(content);
        } catch (_) {
          // skip malformed SSE chunks
        }
      },
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(buffer.toString());
      },
    );

    return completer.future.timeout(const Duration(seconds: 60));
  }
}
