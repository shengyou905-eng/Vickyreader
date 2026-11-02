import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../l10n/app_locale_state.dart';
import 'app_http_client.dart';
import '../models/ai_conversation.dart';
import '../models/ai_explain_mode.dart';
import '../models/reading_ai_context.dart';
import 'auth_service.dart';
import 'auth_session_scope.dart';
import 'reading_history.dart';

class AiService {
  @visibleForTesting
  static http.Client Function()? clientFactoryForTesting;
  static const Duration _connectTimeout = Duration(seconds: 60);

  static List<Map<String, String>> _history(List<AiMessage> messages) =>
      messages
          .skip((messages.length - 24).clamp(0, messages.length))
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();

  /// 小U解释：逐字流式返回
  static Stream<String> explainStream({
    required String selectedText,
    required String contextBefore,
    required String paragraph,
    required String contextAfter,
    required String bookTitle,
    required String bookAuthor,
    required String chapterTitle,
    required AiExplainMode mode,
    List<AiMessage>? conversationHistory,
  }) {
    final history = _readingHistory(conversationHistory ?? []);

    return _sseStream('/api/ai/explain', {
      'selectedText': selectedText,
      'contextBefore': contextBefore,
      'paragraph': paragraph,
      'contextAfter': contextAfter,
      'bookTitle': bookTitle,
      'bookAuthor': bookAuthor,
      'chapterTitle': chapterTitle,
      'mode': mode.apiValue,
      'history': history,
    });
  }

  /// 追问：逐字流式返回
  static Stream<String> chatStream({
    required String message,
    required List<AiMessage> conversationHistory,
    ReadingAiContext? readingContext,
  }) {
    final history = _readingHistory(conversationHistory);

    return _sseStream(readingContext?.path ?? '/api/ai/explain', {
      ...?readingContext?.toJson(),
      'message': message,
      'history': history,
    });
  }

  /// 小U Agent 对话：围绕用户阅读痕迹、授权随心记和明台公开痕迹回答
  static Stream<String> xiaouAgentStream({
    required String message,
    required List<AiMessage> conversationHistory,
    String interactionMode = 'chat',
  }) {
    final history = _history(conversationHistory);

    return _sseStream('/api/ai/chat', {
      'message': message,
      'history': history,
      'interaction_mode': interactionMode,
    });
  }

  /// 「小U问我」：结合阅读痕迹提出一个开放问题。
  static Stream<String> xiaouOpeningQuestionStream({
    required List<AiMessage> conversationHistory,
    String currentBookId = '',
    String currentBookTitle = '',
  }) {
    final history = _history(
      conversationHistory.where((m) => m.content.trim().isNotEmpty).toList(),
    );
    return _sseStream('/api/ai/xiaou-asks', {
      'history': history,
      'current_book_id': currentBookId,
      'current_book_title': currentBookTitle,
    });
  }

  /// 阅读页自由提问：只使用用户指定的当前阅读上下文。
  static Stream<String> readerQuestionStream({
    required String message,
    required String scope,
    required String selectedText,
    required String pageText,
    required String chapterText,
    required String contextBefore,
    required String contextAfter,
    required String bookTitle,
    required String bookAuthor,
    required String chapterTitle,
    required List<AiMessage> conversationHistory,
  }) {
    final history = _readingHistory(conversationHistory);
    return _sseStream('/api/ai/reader-question', {
      'message': message,
      'scope': scope,
      'selectedText': selectedText,
      'pageText': pageText,
      'chapterText': chapterText,
      'contextBefore': contextBefore,
      'contextAfter': contextAfter,
      'bookTitle': bookTitle,
      'bookAuthor': bookAuthor,
      'chapterTitle': chapterTitle,
      'history': history,
    });
  }

  static List<Map<String, String>> _readingHistory(List<AiMessage> messages) =>
      selectReadingHistory(messages)
          .map(
            (message) => {
              'role': message.role,
              'content': message.content.trim(),
            },
          )
          .toList();

  /// 连接后端 SSE，逐 chunk yield
  static Stream<String> _sseStream(String path, Map<String, dynamic> body) {
    final scope = AuthSessionScope.capture();
    late StreamController<String> output;
    http.Client? client;
    StreamSubscription<String>? subscription;
    var cancelled = false;
    void fail(Object error) {
      if (!cancelled && !output.isClosed) {
        output.addError(Exception(friendlyError(error)));
        unawaited(output.close());
      }
      client?.close();
    }

    void identityChanged() {
      if (!scope.isCurrent) {
        fail(const StaleAuthSession());
        unawaited(subscription?.cancel());
      }
    }

    output = StreamController<String>(
      onListen: () async {
        AuthSessionScope.changes.addListener(identityChanged);
        try {
          scope.requireOwner();
          final token = AuthService.token;
          if (token == null || token.isEmpty) throw Exception('请先登录');
          final request = http.Request(
            'POST',
            Uri.parse('${AppConstants.apiBaseUrl}$path'),
          );
          request.headers.addAll({
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
            'Authorization': 'Bearer $token',
            'X-Request-ID': const Uuid().v4(),
          });
          request.body = jsonEncode({
            ...body,
            'response_language': AppLocaleState.languageCode,
          });
          client = clientFactoryForTesting?.call() ?? AppHttp.createClient();
          final streamed = await client!.send(request).timeout(_connectTimeout);
          scope.check();
          if (cancelled) {
            await streamed.stream.listen((_) {}).cancel();
            return;
          }
          if (streamed.statusCode != 200) {
            final errorBody = await streamed.stream.bytesToString().timeout(
              _connectTimeout,
            );
            var message = '请求失败 (${streamed.statusCode})';
            try {
              final value = jsonDecode(errorBody);
              if (value is Map && value['error'] != null) {
                message = value['error'].toString();
              }
            } on FormatException {
              /* Non-JSON proxy response. */
            }
            throw Exception(message);
          }
          subscription =
              decodeStream(
                streamed.stream,
                requireCompletion:
                    streamed.headers['x-zhidu-ai-protocol'] == '2',
              ).listen(
                (chunk) {
                  if (scope.isCurrent && !cancelled && !output.isClosed) {
                    output.add(chunk);
                  }
                },
                onError: fail,
                onDone: () {
                  if (!scope.isCurrent) {
                    fail(const StaleAuthSession());
                    return;
                  }
                  if (!cancelled && !output.isClosed) unawaited(output.close());
                  client?.close();
                },
                cancelOnError: true,
              );
        } catch (error) {
          fail(error);
        }
      },
      onCancel: () async {
        AuthSessionScope.changes.removeListener(identityChanged);
        cancelled = true;
        client?.close();
        await subscription?.cancel();
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
    );
    return output.stream;
  }

  @visibleForTesting
  static Stream<String> decodeStream(
    Stream<List<int>> bytes, {
    bool requireCompletion = true,
  }) {
    var completed = false;
    var hasContent = false;
    var size = 0;
    var receivedBytes = 0;
    var terminal = false;
    late StreamController<String> output;
    StreamSubscription<String>? subscription;
    void finish([Object? error]) {
      if (terminal) return;
      terminal = true;
      if (error != null) output.addError(error);
      unawaited(output.close());
      unawaited(subscription?.cancel());
    }

    final bounded = bytes.map((chunk) {
      receivedBytes += chunk.length;
      if (receivedBytes > 2 * 1024 * 1024) {
        throw const FormatException('AI stream exceeds budget');
      }
      return chunk;
    });
    output = StreamController<String>(
      onListen: () {
        subscription = bounded
            .timeout(const Duration(seconds: 75))
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (line) {
                if (terminal) return;
                try {
                  if (line.length > 256000) {
                    throw const FormatException('AI frame exceeds budget');
                  }
                  if (!line.startsWith('data:')) return;
                  final data = line.substring(5).trim();
                  if (data == '[DONE]') {
                    if (!hasContent || (requireCompletion && !completed)) {
                      throw Exception('回答未完整完成，未保存为成功记录。');
                    }
                    finish();
                    return;
                  }
                  final parsed = jsonDecode(data);
                  if (parsed is! Map<String, dynamic>) {
                    throw const FormatException('Invalid AI event');
                  }
                  if (parsed['error'] != null) {
                    throw Exception(parsed['error'].toString());
                  }
                  if (parsed['status'] == 'completed') {
                    if (parsed['finish_reason'] != 'stop') {
                      throw const FormatException('Invalid completion');
                    }
                    completed = true;
                  }
                  final content = parsed['content'];
                  if (content != null) {
                    if (content is! String || completed) {
                      throw const FormatException('Invalid AI content');
                    }
                    size += content.length;
                    if (size > 64000) {
                      throw const FormatException('AI response exceeds budget');
                    }
                    if (content.isNotEmpty) {
                      hasContent = true;
                      output.add(content);
                    }
                  }
                } catch (error) {
                  finish(error);
                }
              },
              onError: finish,
              onDone: () => finish(Exception('回答连接中断，未保存为成功记录。')),
            );
      },
      onCancel: () {
        terminal = true;
        return subscription?.cancel();
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
    );
    return output.stream;
  }

  static String friendlyError(Object error) {
    final raw = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    if (raw.contains('固定引导问题') ||
        raw.contains('阅读回顾入口') ||
        raw.contains('小U已收敛')) {
      return '小U现在支持自由提问。如果这里还出现旧提示，请部署最新后端并重启服务。';
    }
    if (raw.contains('TimeoutException') ||
        raw.contains('Future not completed')) {
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
