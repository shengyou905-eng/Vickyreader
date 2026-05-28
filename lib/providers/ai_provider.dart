import 'dart:async';
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
  String? _loadingText;
  StreamSubscription<String>? _activeSubscription;
  Completer<void>? _activeCompleter;
  int _activeGeneration = 0;
  bool _cancelRequested = false;

  List<AiMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get loadingText => _loadingText;

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
    final generation = _startGeneration('小U正在阅读这一段…');
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

      final completed = await _consumeStream(
        stream: stream,
        buffer: buffer,
        aiTimestamp: aiMsg.timestamp,
        generation: generation,
      );
      if (!completed) return;

      final result = buffer.toString();
      if (result.trim().isEmpty) {
        throw Exception('小U暂时没有想好，请稍后重试。');
      }

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

      _finishGeneration(generation);
    } catch (e) {
      if (!_isActiveGeneration(generation)) return;
      _error = AiService.friendlyError(e);
      _isLoading = false;
      _loadingText = null;
      // 删掉空的 AI 消息
      _removeEmptyAssistantTail();
      notifyListeners();
    } finally {
      if (_isActiveGeneration(generation)) {
        _activeSubscription = null;
        _activeCompleter = null;
      }
    }
  }

  Future<void> sendFollowUp(String question) async {
    final generation = _startGeneration('正在组织语言…');
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

      final completed = await _consumeStream(
        stream: stream,
        buffer: buffer,
        aiTimestamp: aiMsg.timestamp,
        generation: generation,
      );
      if (!completed) return;

      final result = buffer.toString();
      if (result.trim().isEmpty) {
        throw Exception('小U暂时没有想好，请稍后重试。');
      }

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

      _finishGeneration(generation);
    } catch (e) {
      if (!_isActiveGeneration(generation)) return;
      _error = AiService.friendlyError(e);
      _isLoading = false;
      _loadingText = null;
      _removeEmptyAssistantTail();
      notifyListeners();
    } finally {
      if (_isActiveGeneration(generation)) {
        _activeSubscription = null;
        _activeCompleter = null;
      }
    }
  }

  int _startGeneration(String loadingText) {
    _activeSubscription?.cancel();
    final completer = _activeCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _activeSubscription = null;
    _activeCompleter = null;
    _cancelRequested = false;
    _isLoading = true;
    _error = null;
    _loadingText = loadingText;
    _activeGeneration += 1;
    return _activeGeneration;
  }

  bool _isActiveGeneration(int generation) {
    return generation == _activeGeneration && !_cancelRequested;
  }

  Future<bool> _consumeStream({
    required Stream<String> stream,
    required StringBuffer buffer,
    required DateTime aiTimestamp,
    required int generation,
  }) async {
    if (!_isActiveGeneration(generation)) return false;
    final completer = Completer<void>();
    _activeCompleter = completer;
    _activeSubscription = stream.listen(
      (chunk) {
        if (!_isActiveGeneration(generation)) return;
        if (buffer.isEmpty) {
          _loadingText = '正在组织语言…';
        }
        buffer.write(chunk);
        _messages[_messages.length - 1] = AiMessage(
          role: 'assistant',
          content: buffer.toString(),
          timestamp: aiTimestamp,
        );
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );
    await completer.future;
    return _isActiveGeneration(generation);
  }

  void _finishGeneration(int generation) {
    if (!_isActiveGeneration(generation)) return;
    _isLoading = false;
    _loadingText = null;
    _activeSubscription = null;
    _activeCompleter = null;
    notifyListeners();
  }

  Future<void> cancelGeneration() async {
    if (!_isLoading && _activeSubscription == null) return;
    _cancelRequested = true;
    _activeGeneration += 1;
    _isLoading = false;
    _loadingText = null;
    _removeEmptyAssistantTail();
    final completer = _activeCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    final subscription = _activeSubscription;
    _activeSubscription = null;
    _activeCompleter = null;
    notifyListeners();
    await subscription?.cancel();
  }

  void _removeEmptyAssistantTail() {
    if (_messages.isNotEmpty &&
        _messages.last.role == 'assistant' &&
        _messages.last.content.isEmpty) {
      _messages.removeLast();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearMessages() {
    _cancelRequested = true;
    _activeGeneration += 1;
    _activeSubscription?.cancel();
    final completer = _activeCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _activeSubscription = null;
    _activeCompleter = null;
    _isLoading = false;
    _error = null;
    _loadingText = null;
    _messages.clear();
    notifyListeners();
  }

  String _summaryOf(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 80) return compact;
    return '${compact.substring(0, 80)}...';
  }
}
