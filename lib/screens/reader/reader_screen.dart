import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../config/reader_paging_mode.dart';
import '../../config/theme.dart';
import '../../models/highlight.dart';
import '../../providers/reader_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/auth_service.dart';
import '../../services/epub_service.dart';
import '../../services/mingtai_community_api.dart';
import '../../utils/ai_consent_gate.dart';
import '../../utils/community_safety.dart';
import '../mingtai/community_mingtai_screen.dart';
import 'widgets/ai_explanation_card.dart';
import 'widgets/reader_settings.dart';
import 'widgets/selection_menu.dart';
import 'widgets/pdf_reader.dart';
import 'widgets/reader_document_html.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late WebViewController _webViewController;
  bool _showControls = true;
  bool _ignoreChapterMessages = false;
  bool _isExiting = false;
  bool _hasWebSelection = false;
  bool? _controlsBeforeAi;
  String? _webViewLoadError;
  String? _loadedChapterKey;
  int _appliedReadingPositionRevision = -1;
  DateTime _lastChapterBoundaryAt = DateTime.fromMillisecondsSinceEpoch(0);
  double? _pendingRestoreRatio;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted || _webViewLoadError == null) return;
            setState(() => _webViewLoadError = null);
          },
          onPageFinished: (_) => _onPageReady(),
          onWebResourceError: (error) {
            if (!mounted ||
                error.isForMainFrame != true ||
                error.errorCode == -999 ||
                error.errorCode == -3) {
              return;
            }
            setState(() {
              _webViewLoadError = '正文载入失败：${error.description}';
            });
          },
          onNavigationRequest: (request) {
            if (isReaderDocumentNavigationAllowed(request.url)) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..addJavaScriptChannel('FlutterBridge', onMessageReceived: _onJsMessage);
  }

  void _onPageReady() {
    if (!mounted) return;
    if (_webViewLoadError != null) {
      setState(() => _webViewLoadError = null);
    }
    _ignoreChapterMessages = false;
    final reader = context.read<ReaderProvider>();
    final settings = context.read<SettingsProvider>();
    _applyReaderStyles(settings);
    final pendingRatio = _pendingRestoreRatio;
    if (pendingRatio != null) {
      _pendingRestoreRatio = null;
      _restoreScrollRatio(pendingRatio);
    } else if (reader.scrollOffset != 0) {
      _restoreScrollOffset(reader.scrollOffset, settings);
    }
    final target = reader.scrollToTextTarget;
    if (target != null) {
      _webViewController.runJavaScript("scrollToText('${_jsEscape(target)}')");
      reader.setScrollTarget(null);
    }
  }

  void _restoreScrollOffset(double offset, SettingsProvider settings) {
    if (offset == 0) return;
    final horizontal = settings.readerPagingMode == ReaderPagingMode.horizontal;
    final axis = horizontal ? 'Left' : 'Top';
    final size = horizontal ? 'Width' : 'Height';
    final target = offset < 0
        ? "Math.max(0, s.scroll$size - s.client$size)"
        : offset.toString();
    _webViewController.runJavaScript(
      "(function(){var s=document.getElementById('readSurface');"
      "if(!s)return;"
      "requestAnimationFrame(function(){"
      "s.scroll$axis=$target;"
      "setTimeout(function(){s.scroll$axis=$target;},80);"
      "});"
      "})();",
    );
  }

  void _restoreScrollRatio(double ratio) {
    final clamped = ratio.clamp(0.0, 1.0).toStringAsFixed(6);
    _webViewController.runJavaScript(
      "(function(){"
      "if(!window.scrollToRatio)return;"
      "requestAnimationFrame(function(){"
      "window.scrollToRatio($clamped);"
      "setTimeout(function(){window.scrollToRatio($clamped);},120);"
      "});"
      "})();",
    );
  }

  Future<double?> _captureScrollRatio() async {
    try {
      final result = await _webViewController.runJavaScriptReturningResult(
        "(function(){"
        "if(window.readerPositionRatio)return window.readerPositionRatio();"
        "var s=document.getElementById('readSurface');"
        "if(!s)return 0;"
        "var horizontal=s.getAttribute('data-paging')==='horizontal';"
        "var max=horizontal?"
        "Math.max(0,s.scrollWidth-s.clientWidth):"
        "Math.max(0,s.scrollHeight-s.clientHeight);"
        "if(max<=0)return 0;"
        "return (horizontal?s.scrollLeft:s.scrollTop)/max;"
        "})();",
      );
      if (result is num) {
        return result.toDouble().clamp(0.0, 1.0).toDouble();
      }
      final parsed = double.tryParse(result.toString());
      return parsed?.clamp(0.0, 1.0).toDouble();
    } catch (_) {
      return null;
    }
  }

  void _applyReaderStyles(SettingsProvider settings) {
    final css =
        '''
      document.documentElement.style.setProperty('--font-size', '${settings.fontSize}px');
      document.documentElement.style.setProperty('--line-height', '${settings.lineHeight}');
      document.documentElement.style.setProperty('--bg-color', '${_colorToHex(settings.backgroundColor)}');
      document.documentElement.style.setProperty('--text-color', '${_colorToHex(settings.textColor)}');
    ''';
    _webViewController.runJavaScript(css);
  }

  String _colorToHex(Color color) {
    final r = (color.r * 255)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0');
    final g = (color.g * 255)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0');
    final b = (color.b * 255)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0');
    return '#$r$g$b';
  }

  String _jsEscape(String s) {
    return s
        .replaceAll("\\", "\\\\")
        .replaceAll("'", "\\'")
        .replaceAll('"', '\\"')
        .replaceAll("\n", "\\n")
        .replaceAll("\r", "\\r");
  }

  void _onJsMessage(JavaScriptMessage message) {
    final text = message.message;
    if (text.startsWith('SELECT|')) {
      final selectedText = text.substring(7);
      _hasWebSelection = selectedText.isNotEmpty;
      context.read<ReaderProvider>().selectText(selectedText);
    } else if (text.startsWith('CHAPTER|')) {
      if (_ignoreChapterMessages) return;
      final offset = int.tryParse(text.substring(8)) ?? 0;
      if (offset > 0) {
        final reader = context.read<ReaderProvider>();
        final newIdx = reader.currentChapterIndex + offset;
        if (newIdx < reader.chapters.length &&
            newIdx != reader.currentChapterIndex) {
          reader.goToChapter(newIdx);
          _loadChapter();
        }
      }
    } else if (text.startsWith('SCROLL|')) {
      final offset = double.tryParse(text.substring(7)) ?? 0;
      context.read<ReaderProvider>().updateScrollOffset(offset);
    } else if (text.startsWith('BOUNDARY|')) {
      _handleChapterBoundary(text.substring(9));
    } else if (text.startsWith('TAP|')) {
      _toggleControls();
    } else if (text.startsWith('NAV|')) {
      _handleNav(text.substring(4));
    }
  }

  Future<void> _handleNav(String href) async {
    final reader = context.read<ReaderProvider>();
    final book = reader.book;
    if (book == null) return;

    final matchedIndex = _chapterIndexForHref(reader, href);
    if (matchedIndex >= 0) {
      reader.goToChapter(matchedIndex);
      _loadChapter();
      return;
    }

    final targetHref = href.split('#').first;
    if (targetHref.trim().isEmpty) {
      final anchor = href.contains('#') ? href.split('#').last : '';
      if (anchor.trim().isNotEmpty) {
        _webViewController.runJavaScript(
          "scrollToAnchor('${_jsEscape(anchor)}')",
        );
      }
      return;
    }

    final spine = await EpubService.getSpine(book.id);
    for (int i = 0; i < spine.length; i++) {
      if (spine[i].endsWith(targetHref) ||
          targetHref.endsWith(spine[i].split('/').last)) {
        if (i < reader.chapters.length) {
          reader.goToChapter(i);
          _loadChapter();
        }
        return;
      }
    }
  }

  int _chapterIndexForHref(ReaderProvider reader, String rawHref) {
    final target = _normalizeNavHref(rawHref);
    if (target.isEmpty) return -1;

    final targetBase = _hrefBaseName(target);
    for (var i = 0; i < reader.chapters.length; i++) {
      final chapterHref = _normalizeNavHref(reader.chapters[i].href);
      if (chapterHref.isEmpty) continue;
      final chapterBase = _hrefBaseName(chapterHref);
      if (chapterHref == target ||
          chapterHref.endsWith('/$target') ||
          target.endsWith('/$chapterHref') ||
          (targetBase.isNotEmpty && targetBase == chapterBase)) {
        return i;
      }
    }
    return -1;
  }

  String _normalizeNavHref(String href) {
    var value = href.trim();
    if (value.isEmpty) return '';
    try {
      value = Uri.decodeComponent(value);
    } catch (_) {
      // Some EPUB files contain non-encoded percent characters in hrefs.
    }
    value = value.split('#').first.split('?').first.replaceAll('\\', '/');
    while (value.startsWith('./')) {
      value = value.substring(2);
    }
    while (value.startsWith('/')) {
      value = value.substring(1);
    }
    return value.toLowerCase();
  }

  String _hrefBaseName(String href) {
    return p.basename(_normalizeNavHref(href)).toLowerCase();
  }

  Future<void> _loadChapter() async {
    final reader = context.read<ReaderProvider>();
    final targetIndex = reader.currentChapterIndex;
    final chapter = await reader.ensureChapterLoaded(targetIndex);
    if (!mounted) return;
    if (chapter == null) return;
    if (reader.currentChapterIndex != targetIndex) return;
    if (reader.book == null) return;
    _loadedChapterKey = _chapterLoadKey(reader);
    _appliedReadingPositionRevision = reader.readingPositionRevision;

    final settings = context.read<SettingsProvider>();
    final chapterIdx = targetIndex.toString();
    final chapterHighlights = reader.highlights
        .where((h) => h.chapterIndex == chapterIdx)
        .toList();

    final html = _buildChapterHtml(
      chapter.title,
      chapter.content,
      settings,
      highlights: chapterHighlights,
    );
    final filePath = await EpubService.getChapterFilePath(
      reader.book!.id,
      targetIndex,
    );
    if (!mounted ||
        context.read<ReaderProvider>().currentChapterIndex != targetIndex) {
      return;
    }
    final baseDir = Uri.directory(p.dirname(filePath)).toString();
    _webViewController.loadHtmlString(html, baseUrl: baseDir);
  }

  String? _chapterLoadKey(ReaderProvider reader) {
    final bookId = reader.book?.id;
    final chapter = reader.currentChapter;
    if (bookId == null || chapter == null) return null;
    return '$bookId:${reader.currentChapterIndex}:${chapter.index}:${chapter.content.length}';
  }

  bool _scheduleChapterLoadIfNeeded(ReaderProvider reader) {
    final key = _chapterLoadKey(reader);
    if (key == null || key == _loadedChapterKey) return false;
    _loadedChapterKey = key;
    _appliedReadingPositionRevision = reader.readingPositionRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadChapter();
    });
    return true;
  }

  void _scheduleScrollRestoreIfNeeded(
    ReaderProvider reader,
    SettingsProvider settings,
  ) {
    if (reader.currentChapter == null ||
        reader.readingPositionRevision == _appliedReadingPositionRevision) {
      return;
    }
    final offset = reader.scrollOffset;
    _appliedReadingPositionRevision = reader.readingPositionRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restoreScrollOffset(offset, settings);
    });
  }

  String _buildChapterHtml(
    String title,
    String content,
    SettingsProvider settings, {
    List<Highlight> highlights = const [],
    List<Map<String, String>> nextChapters = const [],
  }) {
    final media = MediaQuery.of(context);
    return ReaderDocumentHtml.build(
      title: title,
      content: content,
      settings: settings,
      highlights: highlights,
      pagingMode: settings.readerPagingMode,
      topInset: media.padding.top + 64,
      bottomInset: media.padding.bottom + 72,
      nextChapters: nextChapters,
    );
  }

  void _goNextChapter() {
    final reader = context.read<ReaderProvider>();
    if (reader.currentChapterIndex < reader.chapters.length - 1) {
      reader.goToChapter(reader.currentChapterIndex + 1);
      _loadChapter();
    }
  }

  void _goPrevChapter() {
    final reader = context.read<ReaderProvider>();
    if (reader.currentChapterIndex > 0) {
      reader.goToChapter(reader.currentChapterIndex - 1);
      _loadChapter();
    }
  }

  void _handleChapterBoundary(String direction) {
    final now = DateTime.now();
    if (now.difference(_lastChapterBoundaryAt).inMilliseconds < 450) {
      return;
    }

    final reader = context.read<ReaderProvider>();
    if (reader.selectedText != null || _hasWebSelection) return;

    if (direction == 'next' &&
        reader.currentChapterIndex < reader.chapters.length - 1) {
      _lastChapterBoundaryAt = now;
      reader.goToChapter(reader.currentChapterIndex + 1);
      _loadChapter();
    } else if (direction == 'prev' && reader.currentChapterIndex > 0) {
      _lastChapterBoundaryAt = now;
      reader.goToChapter(reader.currentChapterIndex - 1, scrollOffset: -1);
      _loadChapter();
    }
  }

  void _toggleControls() {
    if (context.read<ReaderProvider>().showAiPanel) return;
    setState(() => _showControls = !_showControls);
  }

  void _showSettings() async {
    final modalContext = context;
    final settingsProvider = modalContext.read<SettingsProvider>();
    final readerProvider = modalContext.read<ReaderProvider>();
    final pagingBefore = settingsProvider.readerPagingMode;
    final positionRatioFuture = _captureScrollRatio();
    showModalBottomSheet(
      context: modalContext,
      builder: (_) => const ReaderSettings(),
    ).then((_) async {
      final positionRatioBefore = await positionRatioFuture;
      if (!mounted) return;
      _applyReaderStyles(settingsProvider);
      if (settingsProvider.readerPagingMode != pagingBefore) {
        final book = readerProvider.book;
        if (book != null && book.format != 'pdf') {
          _ignoreChapterMessages = true;
          _pendingRestoreRatio = positionRatioBefore;
          _loadChapter();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _isExiting,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        _exitReader();
      },
      child: Scaffold(
        body: Consumer2<ReaderProvider, SettingsProvider>(
          builder: (context, reader, settings, _) {
            if (reader.isLoading) {
              return _buildLoading(reader.loadingMessage);
            }
            if (reader.loadError != null) {
              return _buildLoadError(reader.loadError!);
            }

            final isPdf = reader.book?.format == 'pdf';
            if (!isPdf) {
              final chapterChanged = _scheduleChapterLoadIfNeeded(reader);
              if (!chapterChanged) {
                _scheduleScrollRestoreIfNeeded(reader, settings);
              }
            }
            if (!isPdf && reader.selectedText == null && _hasWebSelection) {
              _hasWebSelection = false;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _webViewController.runJavaScript(
                  'window.clearSelection && window.clearSelection();',
                );
              });
            }

            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: isPdf
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            PdfReaderWidget(
                              key: ValueKey(settings.readerPagingMode),
                              scrollDirection:
                                  settings.readerPagingMode ==
                                      ReaderPagingMode.horizontal
                                  ? Axis.horizontal
                                  : Axis.vertical,
                            ),
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: 48,
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTap: _toggleControls,
                              ),
                            ),
                          ],
                        )
                      : WebViewWidget(controller: _webViewController),
                ),

                if (!isPdf && _webViewLoadError != null)
                  ColoredBox(
                    color: settings.backgroundColor,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded, size: 44),
                            const SizedBox(height: 16),
                            Text(
                              _webViewLoadError!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: settings.textColor),
                            ),
                            const SizedBox(height: 18),
                            TextButton.icon(
                              onPressed: () {
                                setState(() => _webViewLoadError = null);
                                _loadChapter();
                              },
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('重新载入正文'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                if (reader.selectedText != null && !reader.showAiPanel)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: SelectionMenu(
                      onExplain: () {
                        unawaited(_beginAiExplanation(reader));
                      },
                      onHighlight: (color) async {
                        final chapter = reader.currentChapter;
                        if (chapter != null) {
                          final plainText = EpubService.getPlainText(
                            chapter.content,
                          );
                          final selectedText = reader.selectedText!;
                          final startIdx = _findSelectedTextOffset(
                            plainText,
                            selectedText,
                          );
                          final textContext = startIdx >= 0
                              ? EpubService.getContext(
                                  chapter.content,
                                  selectedText,
                                  200,
                                )
                              : (before: '', after: '');
                          await reader.addHighlight(
                            selectedText: selectedText,
                            contextBefore: textContext.before,
                            contextAfter: textContext.after,
                            startOffset: startIdx >= 0 ? startIdx : 0,
                            endOffset: startIdx >= 0
                                ? startIdx + selectedText.length
                                : selectedText.length,
                            color: color,
                          );
                          _webViewController.runJavaScript(
                            "wrapSelection('$color', '${_jsEscape(selectedText)}')",
                          );
                          _hasWebSelection = false;
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('已由小U整理'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        }
                        reader.clearSelection();
                      },
                      onNote: () => _showNoteDialog(reader),
                      onDismiss: () => _clearReaderSelection(reader),
                    ),
                  ),

                if (reader.showAiPanel)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: (MediaQuery.of(context).size.height * 0.4).clamp(
                      310.0,
                      430.0,
                    ),
                    child: AiExplanationCard(
                      onClose: () => _closeAiExplanation(reader),
                    ),
                  ),

                if (_showControls) _buildTopBar(reader),
                if (_showControls) _buildBottomBar(reader),
              ],
            );
          },
        ),
      ),
    );
  }

  void _exitReader() {
    if (_isExiting) return;

    final reader = context.read<ReaderProvider>();
    reader.cancelScheduledSave();
    unawaited(reader.saveProgress().catchError((_) {}));

    if (!mounted) return;
    setState(() => _isExiting = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  int _findSelectedTextOffset(String plainText, String selectedText) {
    final direct = plainText.indexOf(selectedText);
    if (direct >= 0) return direct;

    final normalized = _normalizeWithIndexMap(plainText);
    final normalizedSelected = selectedText
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalizedSelected.isEmpty) return -1;

    final normalizedIndex = normalized.text.indexOf(normalizedSelected);
    if (normalizedIndex < 0 || normalizedIndex >= normalized.indexMap.length) {
      return -1;
    }
    return normalized.indexMap[normalizedIndex];
  }

  ({String text, List<int> indexMap}) _normalizeWithIndexMap(String text) {
    final buffer = StringBuffer();
    final indexMap = <int>[];
    var previousWasSpace = true;

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      final isSpace = RegExp(r'\s').hasMatch(char);
      if (isSpace) {
        if (!previousWasSpace) {
          buffer.write(' ');
          indexMap.add(i);
          previousWasSpace = true;
        }
      } else {
        buffer.write(char);
        indexMap.add(i);
        previousWasSpace = false;
      }
    }

    return (text: buffer.toString().trim(), indexMap: indexMap);
  }

  void _clearReaderSelection(ReaderProvider reader) {
    reader.clearSelection();
    _hasWebSelection = false;
    _webViewController.runJavaScript(
      'window.clearSelection && window.clearSelection();',
    );
  }

  Future<void> _beginAiExplanation(ReaderProvider reader) async {
    if (reader.selectedText == null || reader.showAiPanel) return;
    if (!await AiConsentGate.ensure(context) || !mounted) return;

    _controlsBeforeAi ??= _showControls;
    if (_showControls && mounted) {
      setState(() => _showControls = false);
    }
    _hasWebSelection = false;
    reader.showAiExplanation();

    try {
      await _webViewController.runJavaScript(
        'window.freezeSelectionForAi && window.freezeSelectionForAi();',
      );
    } catch (_) {
      // The selected text is retained by ReaderProvider even if the WebView
      // cannot create the temporary visual marker.
    }
  }

  void _closeAiExplanation(ReaderProvider reader) {
    reader.clearSelection();
    _hasWebSelection = false;
    unawaited(
      _webViewController
          .runJavaScript(
            'window.releaseAiSelection && window.releaseAiSelection();',
          )
          .catchError((_) {}),
    );

    final restoreControls = _controlsBeforeAi;
    _controlsBeforeAi = null;
    if (restoreControls != null &&
        mounted &&
        _showControls != restoreControls) {
      setState(() => _showControls = restoreControls);
    }
  }

  String _bookTitleForDisplay(ReaderProvider reader) {
    final title = reader.book?.title.trim() ?? '';
    final normalizedTitle = title.toLowerCase();
    if (title.isNotEmpty &&
        normalizedTitle != 'unknown title' &&
        normalizedTitle != 'untitled') {
      return title;
    }

    final filePath = reader.book?.filePath ?? '';
    final fallback = p.basenameWithoutExtension(filePath).trim();
    return fallback.isNotEmpty ? fallback : '未命名书籍';
  }

  Widget _buildTopBar(ReaderProvider reader) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        color: context.read<SettingsProvider>().backgroundColor.withAlpha(230),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _exitReader,
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _bookTitleForDisplay(reader),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (reader.currentChapter != null)
                    Text(
                      reader.currentChapter!.title,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                reader.isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                color: reader.isBookmarked ? AppTheme.primary : null,
              ),
              onPressed: () => reader.toggleBookmark(),
            ),
            IconButton(
              icon: const Icon(Icons.text_fields),
              onPressed: _showSettings,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'toc') _showTableOfContents(reader);
                if (value == 'bookmarks') {
                  Navigator.of(context).pushNamed('/bookmarks');
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'toc', child: Text('目录')),
                const PopupMenuItem(value: 'bookmarks', child: Text('书签')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(ReaderProvider reader) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 8,
          top: 8,
        ),
        color: context.read<SettingsProvider>().backgroundColor.withAlpha(230),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: reader.currentChapterIndex > 0 ? _goPrevChapter : null,
            ),
            Text(
              '${reader.currentChapterIndex + 1} / ${reader.chapters.length}',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: reader.currentChapterIndex < reader.chapters.length - 1
                  ? _goNextChapter
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadError(String message) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _exitReader,
            ),
            const Spacer(),
            const Icon(Icons.error_outline, size: 44, color: AppTheme.primary),
            const SizedBox(height: 16),
            const Text(
              '书籍打开失败',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  void _showTableOfContents(ReaderProvider reader) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '目录',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: reader.chapters.length,
                itemBuilder: (_, i) => ListTile(
                  dense: true,
                  title: Text(
                    reader.chapters[i].title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: i == reader.currentChapterIndex
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: i == reader.currentChapterIndex
                          ? AppTheme.primary
                          : AppTheme.textPrimary,
                    ),
                  ),
                  onTap: () {
                    reader.goToChapter(i);
                    _loadChapter();
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showNoteDialog(ReaderProvider reader) async {
    final book = reader.book;
    final selectedText = reader.selectedText?.trim() ?? '';
    if (book == null || selectedText.isEmpty) return;
    await AuthService.init();
    if (!mounted) return;
    final chapterTitle = reader.currentChapter?.title.trim() ?? '';
    final chapterLabel = chapterTitle.isNotEmpty
        ? chapterTitle
        : '第 ${reader.currentChapterIndex + 1} 章';
    final readingPosition =
        '${reader.currentChapterIndex}:${reader.scrollOffset.toStringAsFixed(3)}';
    final readingProgress = reader.progress.clamp(0.0, 1.0).toDouble();
    final messenger = ScaffoldMessenger.of(context);
    final result = await showModalBottomSheet<ReaderThoughtDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReaderThoughtSheet(
        bookTitle: book.title,
        chapterLabel: chapterLabel,
        selectedText: selectedText,
        canPublish: AuthService.isLoggedIn,
      ),
    );
    if (result == null) {
      _clearReaderSelection(reader);
      return;
    }

    final entryId = await reader.addThought(content: result.content);
    if (!mounted) return;
    if (!result.isPublic) {
      _clearReaderSelection(reader);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('想法已留给自己'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    if (!await ensureCommunityGuidelines(context) || !mounted) {
      _clearReaderSelection(reader);
      messenger.showSnackBar(const SnackBar(content: Text('想法已保存为私密，尚未公开到明台')));
      return;
    }

    try {
      const api = MingtaiCommunityApi();
      final communityBook = await api.resolveBook(
        title: book.title,
        author: book.author,
        description: book.description ?? '',
      );
      final post = await api.createPost(
        bookId: communityBook.id,
        type: 'fragment_thought',
        content: result.content,
        quotedText: selectedText,
        chapterLabel: chapterLabel,
        readingPosition: readingPosition,
        readingProgress: readingProgress,
        source: 'reader_selection',
        sourceEntryId: entryId ?? '',
      );
      if (!mounted) return;
      _clearReaderSelection(reader);
      messenger.showSnackBar(
        SnackBar(
          content: const Text('已发布到明台'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: '查看',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CommunityBookScreen(
                  bookId: post.bookId,
                  focusPostId: post.id,
                ),
              ),
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _clearReaderSelection(reader);
      messenger.showSnackBar(
        SnackBar(content: Text('想法已保存为私密，公开失败：${_readerError(error)}')),
      );
    }
  }
}

@visibleForTesting
bool isReaderDocumentNavigationAllowed(String rawUrl) {
  final url = rawUrl.trim();
  if (url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return switch (uri.scheme.toLowerCase()) {
    'about' || 'file' || 'data' || 'applewebdata' => true,
    _ => false,
  };
}

class ReaderThoughtDraft {
  final String content;
  final bool isPublic;

  const ReaderThoughtDraft({required this.content, required this.isPublic});
}

class ReaderThoughtSheet extends StatefulWidget {
  final String bookTitle;
  final String chapterLabel;
  final String selectedText;
  final bool canPublish;

  const ReaderThoughtSheet({
    super.key,
    required this.bookTitle,
    required this.chapterLabel,
    required this.selectedText,
    required this.canPublish,
  });

  @override
  State<ReaderThoughtSheet> createState() => _ReaderThoughtSheetState();
}

class _ReaderThoughtSheetState extends State<ReaderThoughtSheet> {
  final _controller = TextEditingController();
  bool _isPublic = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final content = _controller.text.trim();
    if (content.isEmpty) {
      setState(() => _error = '先写下你的想法');
      return;
    }
    if (_isPublic && content.length < 5) {
      setState(() => _error = '公开想法至少需要 5 个字');
      return;
    }
    Navigator.pop(
      context,
      ReaderThoughtDraft(content: content, isPublic: _isPublic),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.divider,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '写下想法',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  '《${widget.bookTitle}》 · ${widget.chapterLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: palette.primaryLight.withValues(alpha: 0.12),
                  child: Text(
                    '“${widget.selectedText}”',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13,
                      height: 1.55,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 7,
                  decoration: const InputDecoration(
                    hintText: '这段文字让你想到什么？',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 14),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('仅自己')),
                    ButtonSegment(value: true, label: Text('公开到明台')),
                  ],
                  selected: {_isPublic},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) {
                    final next = value.first;
                    if (next && !widget.canPublish) {
                      setState(() => _error = '登录后才能公开到明台');
                      return;
                    }
                    setState(() {
                      _isPublic = next;
                      _error = null;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  _isPublic ? '只会公开这段短摘录和你的想法，电子书文件不会上传。' : '保存在私人阅读记录中。',
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _submit,
                      child: Text(_isPublic ? '发布' : '保存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _readerError(Object error) {
  final message = error.toString().replaceFirst('Exception: ', '').trim();
  return message.isEmpty ? '请稍后重试' : message;
}
