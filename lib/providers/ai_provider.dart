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

  Future<String?> explain({
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
      final context = EpubService.getContext(
          chapterContent, selectedText, 200);

      final result = await AiService.explain(
        selectedText: selectedText,
        contextBefore: context.before,
        contextAfter: context.after,
        bookTitle: bookTitle,
        bookAuthor: bookAuthor,
        conversationHistory: _messages.length > 6
            ? _messages.sublist(_messages.length - 6)
            : _messages,
      );

      // Save to history
      final userMsg = AiMessage(
        role: 'user',
        content: '解释：「$selectedText」',
        timestamp: DateTime.now(),
      );
      final aiMsg = AiMessage(
        role: 'assistant',
        content: result,
        timestamp: DateTime.now().add(const Duration(seconds: 1)),
      );

      if (_bookId != null) {
        await BookService.insertAiMessage(_bookId!, userMsg);
        await BookService.insertAiMessage(_bookId!, aiMsg);
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

      _messages.add(userMsg);
      _messages.add(aiMsg);
      // Keep only last 20 messages
      if (_messages.length > 20) {
        _messages = _messages.sublist(_messages.length - 20);
      }

      _isLoading = false;
      notifyListeners();
      return result;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<String?> sendFollowUp(String question) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await AiService.chat(
        message: question,
        conversationHistory: _messages,
      );

      final userMsg = AiMessage(
        role: 'user',
        content: question,
        timestamp: DateTime.now(),
      );
      final aiMsg = AiMessage(
        role: 'assistant',
        content: result,
        timestamp: DateTime.now().add(const Duration(seconds: 1)),
      );

      if (_bookId != null) {
        await BookService.insertAiMessage(_bookId!, userMsg);
        await BookService.insertAiMessage(_bookId!, aiMsg);
      }

      _messages.add(userMsg);
      _messages.add(aiMsg);
      if (_messages.length > 20) {
        _messages = _messages.sublist(_messages.length - 20);
      }

      _isLoading = false;
      notifyListeners();
      return result;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
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
