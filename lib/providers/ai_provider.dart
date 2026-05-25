import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/ai_conversation.dart';
import '../models/user_entry.dart';
import '../services/auth_service.dart';
import '../services/ai_service.dart';
import '../services/book_service.dart';
import '../services/epub_service.dart';

class AiProvider extends ChangeNotifier {
  List<AiMessage> _messages = [];
  bool _isLoading = false;
  String? _error;
  String? _bookId;

  List<AiMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadHistory(String bookId) async {
    _bookId = bookId;
    _messages = await BookService.getAiMessages(bookId);
    notifyListeners();
  }

  Future<void> explain({
    required String selectedText,
    required String bookTitle,
    required String bookAuthor,
    required String chapterContent,
    required String chapterIndex,
    String chapterTitle = '',
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final context = EpubService.getContext(chapterContent, selectedText, 200);

      // 先加用户消息
      final userMsg = AiMessage(
        role: 'user',
        content: '「$selectedText」',
        timestamp: DateTime.now(),
      );
      _messages.add(userMsg);

      // 加占位 AI 消息，逐字更新
      final aiMsg = AiMessage(
        role: 'assistant',
        content: '',
        timestamp: DateTime.now().add(const Duration(seconds: 1)),
      );
      _messages.add(aiMsg);
      notifyListeners();

      final history = _messages.length > 6
          ? _messages.sublist(_messages.length - 6)
          : _messages;
      // 去掉刚加的占位消息
      final historyWithoutLast =
          history.where((m) => m.content.isNotEmpty).toList();

      final buffer = StringBuffer();
      final stream = AiService.explainStream(
        selectedText: selectedText,
        contextBefore: context.before,
        contextAfter: context.after,
        bookTitle: bookTitle,
        bookAuthor: bookAuthor,
        conversationHistory: historyWithoutLast,
      );

      await for (final chunk in stream) {
        buffer.write(chunk);
        // 替换最后一条消息的内容
        _messages[_messages.length - 1] = AiMessage(
          role: 'assistant',
          content: buffer.toString(),
          timestamp: aiMsg.timestamp,
        );
        notifyListeners();
      }

      final result = buffer.toString();

      // 保存到本地
      if (_bookId != null) {
        await BookService.insertAiMessage(_bookId!, userMsg);
        await BookService.insertAiMessage(
          _bookId!,
          AiMessage(
            role: 'assistant',
            content: result,
            timestamp: aiMsg.timestamp,
          ),
        );
        await BookService.insertUserEntry(
          UserEntry(
            id: const Uuid().v4(),
            userId: AuthService.userId ?? '',
            source: 'ai_explanation',
            bookId: _bookId!,
            bookTitle: bookTitle,
            chapterIndex: chapterIndex,
            chapterTitle: chapterTitle,
            originalText: selectedText,
            aiExplanation: result,
            autoTags: const ['小U解释'],
            autoSummary: _summaryOf(result),
            metadataJson: jsonEncode({'book_author': bookAuthor}),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
      }

      // 修剪历史长度
      if (_messages.length > 20) {
        _messages = _messages.sublist(_messages.length - 20);
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      // 删掉空的 AI 消息
      if (_messages.isNotEmpty && _messages.last.content.isEmpty) {
        _messages.removeLast();
      }
      notifyListeners();
    }
  }

  Future<void> sendFollowUp(String question) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final userMsg = AiMessage(
        role: 'user',
        content: question,
        timestamp: DateTime.now(),
      );
      _messages.add(userMsg);

      final aiMsg = AiMessage(
        role: 'assistant',
        content: '',
        timestamp: DateTime.now().add(const Duration(seconds: 1)),
      );
      _messages.add(aiMsg);
      notifyListeners();

      final history = _messages
          .where((m) => m.content.isNotEmpty)
          .toList();
      history.removeLast(); // 去掉刚加的占位

      final buffer = StringBuffer();
      final stream = AiService.chatStream(
        message: question,
        conversationHistory: history,
      );

      await for (final chunk in stream) {
        buffer.write(chunk);
        _messages[_messages.length - 1] = AiMessage(
          role: 'assistant',
          content: buffer.toString(),
          timestamp: aiMsg.timestamp,
        );
        notifyListeners();
      }

      final result = buffer.toString();

      if (_bookId != null) {
        await BookService.insertAiMessage(_bookId!, userMsg);
        await BookService.insertAiMessage(
          _bookId!,
          AiMessage(
            role: 'assistant',
            content: result,
            timestamp: aiMsg.timestamp,
          ),
        );
      }

      if (_messages.length > 20) {
        _messages = _messages.sublist(_messages.length - 20);
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      if (_messages.isNotEmpty && _messages.last.content.isEmpty) {
        _messages.removeLast();
      }
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearMessages() {
    _messages.clear();
    notifyListeners();
  }

  String _summaryOf(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 80) return compact;
    return '${compact.substring(0, 80)}...';
  }
}
