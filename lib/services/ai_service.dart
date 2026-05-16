import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../models/ai_conversation.dart';

class AiService {
  static const String _apiKeyKey = 'deepseek_api_key';

  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyKey);
  }

  static Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, key);
  }

  /// Send an explanation request with context
  static Future<String> explain({
    required String selectedText,
    required String contextBefore,
    required String contextAfter,
    required String bookTitle,
    required String bookAuthor,
    List<AiMessage>? conversationHistory,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('请先在设置中配置 DeepSeek API Key');
    }

    final messages = <Map<String, String>>[];

    // System prompt
    messages.add({
      'role': 'system',
      'content': '你是一个博学的阅读助手。用户正在阅读《$bookTitle》（作者：$bookAuthor）。'
          '请根据上下文解释用户选中的文字。回答要简洁、准确、有深度。'
          '如果涉及专有名词、典故、历史事件等，请提供背景知识。'
          '用中文回答，控制在 200-400 字以内。',
    });

    // Conversation history (last 3 rounds)
    if (conversationHistory != null && conversationHistory.isNotEmpty) {
      for (final msg in conversationHistory) {
        messages.add(msg.toApiFormat());
      }
    }

    // Current query
    final query = '上下文上文：...$contextBefore...\n'
        '【选中文字】$selectedText\n'
        '上下文下文：...$contextAfter...\n\n'
        '请结合上下文解释这段文字的含义。';
    messages.add({'role': 'user', 'content': query});

    final response = await http.post(
      Uri.parse('${AppConstants.deepseekBaseUrl}/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': AppConstants.deepseekModel,
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 800,
        'stream': false,
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw Exception('AI 服务未返回有效回复');
      }
      return choices[0]['message']['content'] as String;
    } else {
      final error = jsonDecode(response.body);
      final msg = error['error']?['message'] ?? '请求失败';
      throw Exception('AI 服务错误：$msg');
    }
  }

  /// Continue a conversation (follow-up question)
  static Future<String> chat({
    required String message,
    required List<AiMessage> conversationHistory,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('请先在设置中配置 DeepSeek API Key');
    }

    final messages = <Map<String, String>>[];
    messages.add({
      'role': 'system',
      'content': '你是一个博学的阅读助手。用户正在就书中的内容向你提问。请保持回答简洁、准确。用中文回答。',
    });

    for (final msg in conversationHistory) {
      messages.add(msg.toApiFormat());
    }
    messages.add({'role': 'user', 'content': message});

    final response = await http.post(
      Uri.parse('${AppConstants.deepseekBaseUrl}/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': AppConstants.deepseekModel,
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 800,
        'stream': false,
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw Exception('AI 服务未返回有效回复');
      }
      return choices[0]['message']['content'] as String;
    } else {
      final error = jsonDecode(response.body);
      final msg = error['error']?['message'] ?? '请求失败';
      throw Exception('AI 服务错误：$msg');
    }
  }

}
