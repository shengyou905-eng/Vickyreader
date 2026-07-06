import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/ai_conversation.dart';
import 'auth_service.dart';

class AiService {
  static const Duration _connectTimeout = Duration(seconds: 60);

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

  /// 小U Agent 对话：围绕用户阅读痕迹、授权随心记和明台公开痕迹回答
  static Stream<String> xiaouAgentStream({
    required String message,
    required List<AiMessage> conversationHistory,
  }) {
    final history = conversationHistory
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    return _sseStream('/api/ai/chat', {
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
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Authorization'] = 'Bearer $token';
    request.body = jsonEncode(body);

    final client = http.Client();
    try {
      final streamed = await client.send(request).timeout(_connectTimeout);

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
          if (parsed is! Map<String, dynamic>) continue;
          if (parsed['error'] != null) {
            throw Exception(parsed['error'].toString());
          }
          final content = parsed['content'] as String?;
          if (content != null && content.isNotEmpty) yield content;
        } on FormatException {
          // skip malformed or status-only SSE chunks
        }
      }
    } on TimeoutException {
      throw Exception('这段内容有些复杂，小U思考得久了一点。请稍后重试。');
    } on SocketException {
      throw Exception('网络似乎有些慢，请稍后重试。');
    } on http.ClientException {
      throw Exception('网络连接中断，请稍后重试。');
    } finally {
      client.close();
    }
  }

  static String friendlyError(Object error) {
    final raw = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    if (raw.contains('固定引导问题') ||
        raw.contains('阅读回顾入口') ||
        raw.contains('小U已收敛')) {
      return '小U现在支持自由提问。如果这里还出现旧提示，请部署最新后端并重启服务。';
    }
    if (raw.contains('TimeoutException') || raw.contains('Future not completed')) {
      return '这段内容有些复杂，小U思考得久了一点。请稍后重试。';
    }
    if (raw.contains('SocketException') ||
        raw.contains('ClientException') ||
        raw.contains('Connection')) {
      return '网络似乎有些慢，请稍后重试。';
    }
    return raw.isEmpty ? '小U暂时没有想好，请稍后重试。' : raw;
  }
}
