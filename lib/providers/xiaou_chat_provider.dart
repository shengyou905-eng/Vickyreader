import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../services/auth_service.dart';

class ChatMessage {
  final String role;
  final String content;
  final bool isStreaming;

  const ChatMessage({
    required this.role,
    required this.content,
    this.isStreaming = false,
  });
}

class XiaouChatProvider extends ChangeNotifier {
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String? _error;
  StreamSubscription? _streamSub;

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  String? get error => _error;

  void addWelcomeMessage() {
    if (_messages.isEmpty) {
      _messages.add(const ChatMessage(
        role: 'assistant',
        content: '我是小U，你的阅读伙伴。\n\n我了解你读过的书、划过的线、写下的想法。想聊聊什么？',
      ));
      notifyListeners();
    }
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _isLoading) return;

    _error = null;
    _isLoading = true;

    _messages.add(ChatMessage(role: 'user', content: text.trim()));
    final aiMsg = ChatMessage(role: 'assistant', content: '', isStreaming: true);
    _messages.add(aiMsg);
    notifyListeners();

    try {
      final token = AuthService.token;
      if (token == null || token.isEmpty) {
        throw Exception('未登录');
      }

      final history = _messages
          .where((m) => !m.isStreaming)
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();
      history.removeLast();

      final request = http.Request(
        'POST',
        Uri.parse('${AppConstants.apiBaseUrl}/api/ai/chat'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.headers['Authorization'] = 'Bearer $token';
      request.body = jsonEncode({
        'message': text.trim(),
        'history': history,
      });

      final streamed = await request.send();
      if (streamed.statusCode != 200) {
        throw Exception('请求失败 (${streamed.statusCode})');
      }

      final buffer = StringBuffer();
      _streamSub = streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (!line.startsWith('data: ')) return;
          final data = line.substring(6).trim();
          if (data == '[DONE]') {
            _finalizeStream(buffer.toString());
            return;
          }
          try {
            final parsed = jsonDecode(data);
            if (parsed['error'] != null) {
              _handleError(parsed['error'].toString());
              return;
            }
            final content = parsed['content'] as String?;
            if (content != null) {
              buffer.write(content);
              _messages.last = ChatMessage(
                role: 'assistant',
                content: buffer.toString(),
                isStreaming: true,
              );
              notifyListeners();
            }
          } catch (_) {
            // skip malformed chunks
          }
        },
        onError: (e) => _handleError(e.toString()),
        onDone: () {
          if (buffer.isNotEmpty && _messages.isNotEmpty && _messages.last.isStreaming) {
            _finalizeStream(buffer.toString());
          }
        },
      );
    } catch (e) {
      _handleError(e.toString());
    }
  }

  void _finalizeStream(String content) {
    if (_messages.isNotEmpty) {
      _messages.last = ChatMessage(role: 'assistant', content: content);
    }
    _isLoading = false;
    notifyListeners();
  }

  void _handleError(String msg) {
    _error = msg;
    _isLoading = false;
    if (_messages.isNotEmpty && _messages.last.content.isEmpty) {
      _messages.removeLast();
    }
    _streamSub?.cancel();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }
}
