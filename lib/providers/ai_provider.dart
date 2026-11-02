import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/ai_conversation.dart';
import '../models/ai_explain_mode.dart';
import '../models/reading_ai_context.dart';
import '../models/user_entry.dart';
import '../l10n/app_locale_state.dart';
import '../services/auth_service.dart';
import '../services/auth_session_scope.dart';
import '../services/ai_service.dart';
import '../services/book_service.dart';
import '../services/epub_service.dart';
import '../services/reading_history.dart';

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
  final Map<String, String> _explanationCache = {};
  String? _activeExplanationEntryId;
  ReadingAiContext? _readingContext;
  List<AiMessage> _readingHistory = [];
  String? _sessionUserId;
  AuthSessionScope? _session;

  AiProvider() {
    AuthSessionScope.changes.addListener(_identityChanged);
  }

  void _identityChanged() {
    _bookId = null;
    _session = null;
    _sessionUserId = null;
    _explanationCache.clear();
    clearMessages();
  }

  @override
  void dispose() {
    AuthSessionScope.changes.removeListener(_identityChanged);
    _activeGeneration++;
    _activeSubscription?.cancel();
    final pending = _activeCompleter;
    if (pending != null && !pending.isCompleted) pending.complete();
    super.dispose();
  }

  List<AiMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get loadingText => _loadingText;

  Future<void> loadHistory(String bookId) async {
    final session = AuthSessionScope.capture();
    await cancelGeneration();
    session.check();
    final generation = ++_activeGeneration;
    _bookId = bookId;
    _activeExplanationEntryId = null;
    _readingContext = null;
    _readingHistory = [];
    final messages = await BookService.getAiMessages(bookId, session: session);
    session.check();
    if (generation != _activeGeneration) return;
    _messages = messages;
    notifyListeners();
  }

  Future<void> explain({
    required String selectedText,
    required String bookTitle,
    required String bookAuthor,
    required String chapterContent,
    required String chapterIndex,
    String chapterTitle = '',
    AiExplainMode mode = AiExplainMode.auto,
    Map<String, dynamic> selectionAnchor = const {},
  }) async {
    if (_isLoading) return;
    _activeExplanationEntryId = null;
    _readingHistory = [];
    _sessionUserId = AuthService.userId;
    _session = AuthSessionScope.capture();
    final generation = _startGeneration(
      AppLocaleState.isEnglish ? _englishLoadingText(mode) : mode.loadingText,
    );
    notifyListeners();

    try {
      _session!.requireOwner();
      final context = EpubService.getReadingContext(
        chapterContent,
        selectedText,
        selectionAnchor: selectionAnchor,
      );
      _readingContext = ReadingAiContext({
        'selectedText': selectedText,
        'bookTitle': bookTitle,
        'bookAuthor': bookAuthor,
        'chapterTitle': chapterTitle,
        'mode': mode.apiValue,
        'contextBefore': context.before,
        'paragraph': context.paragraph,
        'contextAfter': context.after,
      });
      final cacheKey = jsonEncode([
        readingPromptVersion,
        AuthService.userId ?? '',
        AppLocaleState.languageCode,
        _bookId ?? '',
        chapterIndex,
        mode.apiValue,
        bookTitle,
        bookAuthor,
        chapterTitle,
        selectedText,
        context.paragraph,
        context.before,
        context.after,
      ]);
      final cached = _explanationCache[cacheKey];

      final userMsg = AiMessage(
        role: 'user',
        content: '「$selectedText」\n${mode.fullLabel}',
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

      if (cached != null && cached.trim().isNotEmpty) {
        _messages[_messages.length - 1] = AiMessage(
          role: 'assistant',
          content: cached,
          timestamp: aiMsg.timestamp,
        );
        await _persistExplanation(
          generation: generation,
          userMessage: userMsg,
          assistantTimestamp: aiMsg.timestamp,
          result: cached,
          bookTitle: bookTitle,
          bookAuthor: bookAuthor,
          chapterIndex: chapterIndex,
          chapterTitle: chapterTitle,
          selectedText: selectedText,
          mode: mode,
        );
        _finishGeneration(generation);
        return;
      }

      final buffer = StringBuffer();
      final stream = AiService.explainStream(
        selectedText: selectedText,
        contextBefore: context.before,
        paragraph: context.paragraph,
        contextAfter: context.after,
        bookTitle: bookTitle,
        bookAuthor: bookAuthor,
        chapterTitle: chapterTitle,
        mode: mode,
        conversationHistory: const [],
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
      _explanationCache[cacheKey] = result;
      if (_explanationCache.length > 24) {
        _explanationCache.remove(_explanationCache.keys.first);
      }

      await _persistExplanation(
        generation: generation,
        userMessage: userMsg,
        assistantTimestamp: aiMsg.timestamp,
        result: result,
        bookTitle: bookTitle,
        bookAuthor: bookAuthor,
        chapterIndex: chapterIndex,
        chapterTitle: chapterTitle,
        selectedText: selectedText,
        mode: mode,
      );

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
    if (_isLoading ||
        _readingContext == null ||
        _activeExplanationEntryId == null) {
      return;
    }
    final entryId = _activeExplanationEntryId;
    final generation = _startGeneration(
      AppLocaleState.isEnglish ? 'Xiaou is organizing an answer…' : '正在组织语言…',
    );
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

      final buffer = StringBuffer();
      final stream = AiService.chatStream(
        message: question,
        conversationHistory: _readingHistory,
        readingContext: _readingContext,
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
        await BookService.insertAiMessage(_bookId!, userMsg, session: _session);
        if (!_isActiveGeneration(generation)) return;
        await BookService.insertAiMessage(
          _bookId!,
          AiMessage(
            role: 'assistant',
            content: result,
            timestamp: aiMsg.timestamp,
          ),
          session: _session,
        );
      }
      if (entryId != null && entryId.isNotEmpty) {
        if (!_isActiveGeneration(generation)) return;
        await BookService.insertUserEntryFollowUp(
          entryId: entryId,
          question: question,
          answer: result,
          session: _session,
        );
      }

      if (!_isActiveGeneration(generation)) return;
      _readingHistory = selectReadingHistory([
        ..._readingHistory,
        userMsg,
        AiMessage(
          role: 'assistant',
          content: result,
          timestamp: aiMsg.timestamp,
        ),
      ]);
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

  String _englishLoadingText(AiExplainMode mode) {
    return switch (mode) {
      AiExplainMode.auto => 'Xiaou is finding the difficult part…',
      AiExplainMode.plain => 'Xiaou is finding a clearer way to say it…',
      AiExplainMode.structure => 'Xiaou is unpacking the structure…',
      AiExplainMode.concept => 'Xiaou is clarifying the concepts…',
      AiExplainMode.argument => 'Xiaou is tracing the argument…',
    };
  }

  Future<void> _persistExplanation({
    required int generation,
    required AiMessage userMessage,
    required DateTime assistantTimestamp,
    required String result,
    required String bookTitle,
    required String bookAuthor,
    required String chapterIndex,
    required String chapterTitle,
    required String selectedText,
    required AiExplainMode mode,
  }) async {
    final session = _session;
    if (session == null || !_isActiveGeneration(generation)) return;
    session.requireOwner();
    final bookId = _bookId;
    if (bookId == null) return;
    final owner = _sessionUserId ?? '';
    final evidence = _readingContext?.withAnswer(result);
    await BookService.insertAiMessage(bookId, userMessage, session: session);
    session.check();
    await BookService.insertAiMessage(
      bookId,
      AiMessage(
        role: 'assistant',
        content: result,
        timestamp: assistantTimestamp,
      ),
      session: session,
    );
    final localEntryId = const Uuid().v4();
    session.check();
    final savedEntryId = await BookService.insertUserEntry(
      UserEntry(
        id: localEntryId,
        userId: owner,
        source: 'ai_explanation',
        bookId: bookId,
        bookTitle: bookTitle,
        chapterIndex: chapterIndex,
        chapterTitle: chapterTitle,
        originalText: selectedText,
        aiExplanation: result,
        autoTags: ['小U解释', mode.fullLabel],
        autoSummary: _summaryOf(result),
        metadataJson: jsonEncode({
          'book_author': bookAuthor,
          'explain_mode': mode.apiValue,
          'reading_ai_context': evidence?.toJson(),
        }),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      ),
      session: session,
    );
    if (_isActiveGeneration(generation)) {
      _activeExplanationEntryId = savedEntryId;
      _readingContext = evidence;
      _readingHistory = [
        userMessage,
        AiMessage(
          role: 'assistant',
          content: result,
          timestamp: assistantTimestamp,
        ),
      ];
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
    return generation == _activeGeneration &&
        !_cancelRequested &&
        (_session?.isCurrent ?? false) &&
        _sessionUserId == AuthService.userId;
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
        _isLoading == false) {
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
    _activeExplanationEntryId = null;
    _readingContext = null;
    _readingHistory = [];
    _messages.clear();
    notifyListeners();
  }

  String _summaryOf(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 80) return compact;
    return '${compact.substring(0, 80)}...';
  }
}
