import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../config/reader_paging_mode.dart';
import '../../config/reader_typography.dart';
import '../../config/theme.dart';
import '../../l10n/l10n.dart';
import '../../models/highlight.dart';
import '../../models/user_entry.dart';
import '../../providers/reader_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/auth_service.dart';
import '../../services/book_service.dart';
import '../../services/epub_service.dart';
import '../../services/first_use_guide_service.dart';
import '../../services/mingtai_community_api.dart';
import '../../services/reader_font_service.dart';
import '../../utils/ai_consent_gate.dart';
import '../../utils/community_safety.dart';
import '../../widgets/first_use_guides.dart';
import '../mingtai/community_mingtai_screen.dart';
import 'widgets/ai_explanation_card.dart';
import 'widgets/reader_settings.dart';
import 'widgets/reader_question_sheet.dart';
import 'widgets/selection_menu.dart';
import 'widgets/pdf_reader.dart';
import 'widgets/reader_document_html.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  late WebViewController _webViewController;
  bool _showControls = true;
  bool _ignoreChapterMessages = false;
  bool _isExiting = false;
  bool _hasWebSelection = false;
  bool _aiPanelExpanded = false;
  bool? _controlsBeforeAi;
  String? _webViewLoadError;
  String? _loadedChapterKey;
  int _appliedReadingPositionRevision = -1;
  DateTime _lastChapterBoundaryAt = DateTime.fromMillisecondsSinceEpoch(0);
  double? _pendingRestoreRatio;
  String? _activatingTypographyBookId;
  SettingsProvider? _settingsProvider;
  bool _readerDocumentReady = false;
  String? _readerDocumentBookId;
  int _chapterLoadGeneration = 0;
  int _nextPerformanceRequestId = 0;
  int? _pendingFullDocumentRequestId;
  _PendingChapterIntent? _pendingChapterIntent;
  final Map<int, _ChapterPerformanceTrace> _performanceTraces = {};
  final Map<String, ReaderChapterMarkup> _chapterMarkupCache = {};
  final Map<ReaderFontFamily, ReaderFontAsset?> _sessionFontAssets = {};
  final Set<ReaderFontFamily> _resolvedSessionFonts = {};
  List<UserEntry> _currentParagraphThoughts = const [];
  String? _paragraphThoughtsChapterKey;
  bool _showLongPressGuide = false;
  bool _awaitingLongPressSelection = false;
  bool _showSelectionGuideTip = false;
  bool _readerGuideChecked = false;
  Timer? _selectionGuideTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initWebView();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settingsProvider = context.read<SettingsProvider>();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    final settings = _settingsProvider;
    if (settings != null) {
      unawaited(settings.flushTypographyPersistence().catchError((_) {}));
    }
  }

  void _initWebView() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            _readerDocumentReady = false;
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
              _webViewLoadError = context.l10n.readerContentLoadFailed(
                error.description,
              );
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
    _webViewController = controller;
    final platformController = controller.platform;
    if (platformController is AndroidWebViewController) {
      unawaited(platformController.setAllowFileAccess(true));
    }
  }

  void _onPageReady() {
    if (!mounted) return;
    if (_webViewLoadError != null) {
      setState(() => _webViewLoadError = null);
    }
    _ignoreChapterMessages = false;
    final reader = context.read<ReaderProvider>();
    _readerDocumentReady = true;
    _readerDocumentBookId = reader.book?.id;
    final settings = context.read<SettingsProvider>();
    unawaited(_applyReaderStyles(settings));
    unawaited(_refreshParagraphThoughtMarkers(reader));
    final performanceRequestId = _pendingFullDocumentRequestId;
    if (performanceRequestId != null) {
      _pendingFullDocumentRequestId = null;
      unawaited(
        _webViewController.runJavaScript(
          'window.readerReportInitialReady && '
          'window.readerReportInitialReady($performanceRequestId);',
        ),
      );
    }
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
    unawaited(_maybeShowLongPressGuide());
  }

  Future<void> _maybeShowLongPressGuide() async {
    if (_readerGuideChecked || !mounted) return;
    final reader = context.read<ReaderProvider>();
    if (reader.book?.format == 'pdf' || !_readerDocumentReady) return;
    _readerGuideChecked = true;
    final shouldShow = await FirstUseGuideService.claim(
      FirstUseGuide.readerLongPress,
    );
    if (!mounted || !shouldShow) return;
    setState(() => _showLongPressGuide = true);
  }

  void _tryLongPressGuide() {
    setState(() {
      _showLongPressGuide = false;
      _awaitingLongPressSelection = true;
    });
  }

  Future<void> _dismissLongPressGuide() async {
    await FirstUseGuideService.complete(FirstUseGuide.readerLongPress);
    if (!mounted) return;
    setState(() {
      _showLongPressGuide = false;
      _awaitingLongPressSelection = false;
      _showSelectionGuideTip = false;
    });
  }

  void _completeLongPressGesture() {
    if (!_awaitingLongPressSelection || !mounted) return;
    _selectionGuideTimer?.cancel();
    setState(() {
      _awaitingLongPressSelection = false;
      _showSelectionGuideTip = true;
    });
    unawaited(FirstUseGuideService.complete(FirstUseGuide.readerLongPress));
    _selectionGuideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _showSelectionGuideTip = false);
    });
  }

  void _hideSelectionGuideTip() {
    _selectionGuideTimer?.cancel();
    if (!_showSelectionGuideTip || !mounted) return;
    setState(() => _showSelectionGuideTip = false);
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

  Future<void> _applyReaderStyles(
    SettingsProvider settings, {
    bool preservePosition = false,
  }) async {
    var family = settings.readerFontFamily;
    var fontAsset = await _fontAssetFor(family);
    if (family != settings.readerFontFamily) {
      family = settings.readerFontFamily;
      fontAsset = await _fontAssetFor(family);
    }
    if (!mounted) return;
    final cssFamily = _jsEscape(family.cssStack);
    final fontFaceFamily = _jsEscape(fontAsset?.cssFamily ?? '');
    final escapedFontUri = _jsEscape(fontAsset?.uri ?? '');
    final fontFormat = _jsEscape(fontAsset?.format ?? '');
    final preserve = preservePosition ? 'true' : 'false';
    final css =
        '''
      (function() {
        var root = document.documentElement;
        if (!root) return;
        var ratio = ($preserve && window.readerPositionRatio)
          ? window.readerPositionRatio()
          : null;
        var fontUrl = '$escapedFontUri';
        var fontStyle = document.getElementById('reader-font-face');
        if (fontUrl) {
          if (!fontStyle) {
            fontStyle = document.createElement('style');
            fontStyle.id = 'reader-font-face';
            document.head.appendChild(fontStyle);
          }
          if (fontStyle.dataset.family !== '$fontFaceFamily' ||
              fontStyle.dataset.url !== fontUrl) {
            fontStyle.textContent = '@font-face {' +
              'font-family: "$fontFaceFamily";' +
              'src: url("' + fontUrl + '") format("$fontFormat");' +
              'font-weight: 400; font-style: normal; font-display: swap;}';
            fontStyle.dataset.family = '$fontFaceFamily';
            fontStyle.dataset.url = fontUrl;
          }
          window.readerFontFaceFamily = '$fontFaceFamily';
        } else if (fontStyle) {
          fontStyle.remove();
          window.readerFontFaceFamily = '';
        }
        root.style.setProperty('--reader-font-family', '$cssFamily');
        root.style.setProperty('--font-size', '${settings.fontSize}px');
        root.style.setProperty('--line-height', '${settings.lineHeight}');
        root.style.setProperty('--page-pad-x', '${settings.pageMargin}px');
        root.style.setProperty('--bg-color', '${_colorToHex(settings.backgroundColor)}');
        root.style.setProperty('--text-color', '${_colorToHex(settings.textColor)}');
        var surface = document.getElementById('readSurface');
         if (surface) {
           surface.setAttribute(
             'data-paging',
             '${settings.readerPagingMode.storageValue}'
           );
         }
         if (window.readerSyncViewport) {
           window.readerSyncViewport(false);
         }
         if (ratio !== null && window.scrollToRatio) {
          var restore = function() {
            requestAnimationFrame(function() { window.scrollToRatio(ratio); });
          };
          if (fontUrl && document.fonts && document.fonts.load) {
            document.fonts.load('1em "$fontFaceFamily"').then(restore, restore);
          } else if (document.fonts && document.fonts.ready) {
            document.fonts.ready.then(restore, restore);
          } else {
            restore();
          }
        }
        if (fontUrl && document.fonts && document.fonts.load) {
          document.fonts.load('1em "$fontFaceFamily"').then(function(faces) {
            FlutterBridge.postMessage(
              'FONT_STATUS|$fontFaceFamily|' +
              ((faces && faces.length) ? 'loaded' : 'fallback')
            );
          }, function() {
            FlutterBridge.postMessage('FONT_STATUS|$fontFaceFamily|fallback');
          });
        } else {
          FlutterBridge.postMessage('FONT_STATUS|system|loaded');
        }
      })();
    ''';
    await _webViewController.runJavaScript(css);
  }

  Future<ReaderFontAsset?> _fontAssetFor(ReaderFontFamily family) async {
    if (_resolvedSessionFonts.contains(family)) {
      return _sessionFontAssets[family];
    }
    try {
      final asset = await ReaderFontService.ensureFont(family);
      _resolvedSessionFonts.add(family);
      _sessionFontAssets[family] = asset;
      return asset;
    } catch (error, stackTrace) {
      // Keep the platform fallback stack usable if a bundled font cannot load.
      debugPrint('[ReaderFont] resolve failed family=${family.name}: $error');
      debugPrintStack(stackTrace: stackTrace);
      _resolvedSessionFonts.add(family);
      _sessionFontAssets[family] = null;
      return null;
    }
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
    if (text.startsWith('PERF|')) {
      final parts = text.split('|');
      if (parts.length >= 3) {
        final requestId = int.tryParse(parts[2]);
        if (requestId != null) {
          _recordPerformanceStage(requestId, parts[1]);
        }
      }
    } else if (text.startsWith('FONT_STATUS|')) {
      final parts = text.split('|');
      if (parts.length >= 3) {
        debugPrint('[ReaderFont] family=${parts[1]} status=${parts[2]}');
      }
    } else if (text.startsWith('SELECT|')) {
      final selectedText = text.substring(7);
      _hasWebSelection = selectedText.isNotEmpty;
      context.read<ReaderProvider>().selectText(selectedText);
      if (selectedText.isNotEmpty) _completeLongPressGesture();
    } else if (text.startsWith('THOUGHT_MARKER|')) {
      final paragraphIndex = int.tryParse(text.substring(15));
      if (paragraphIndex != null) {
        unawaited(_showParagraphThoughts(paragraphIndex));
      }
    } else if (text.startsWith('CHAPTER|')) {
      if (_ignoreChapterMessages) return;
      final offset = int.tryParse(text.substring(8)) ?? 0;
      if (offset > 0) {
        final reader = context.read<ReaderProvider>();
        final newIdx = reader.currentChapterIndex + offset;
        if (newIdx < reader.chapters.length &&
            newIdx != reader.currentChapterIndex) {
          _navigateToChapter(newIdx, reason: 'continuous_chapter');
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
      _navigateToChapter(matchedIndex, reason: 'epub_link');
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
          _navigateToChapter(i, reason: 'epub_spine_link');
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

  Future<void> _loadChapter({bool forceFullDocument = false}) async {
    final reader = context.read<ReaderProvider>();
    final targetIndex = reader.currentChapterIndex;
    final generation = ++_chapterLoadGeneration;
    final performanceRequestId = _performanceRequestForLoad(targetIndex);
    final chapter = await reader.ensureChapterLoaded(targetIndex);
    if (!mounted || generation != _chapterLoadGeneration) return;
    if (chapter == null) return;
    if (reader.currentChapterIndex != targetIndex) return;
    if (reader.book == null) return;
    _recordPerformanceStage(performanceRequestId, 'CHAPTER_DATA_READY');
    _loadedChapterKey = _chapterLoadKey(reader);
    _appliedReadingPositionRevision = reader.readingPositionRevision;

    final settings = context.read<SettingsProvider>();
    final fontAsset = await _fontAssetFor(settings.readerFontFamily);
    if (!mounted || generation != _chapterLoadGeneration) return;
    final chapterIdx = chapter.sourceIndex.toString();
    final chapterHighlights = reader.highlights
        .where((h) => h.chapterIndex == chapterIdx)
        .toList();
    final preparedChapter = _chapterMarkupFor(
      bookId: reader.book!.id,
      chapterIndex: targetIndex,
      title: chapter.title,
      content: chapter.content,
      highlights: chapterHighlights,
    );
    _recordPerformanceStage(performanceRequestId, 'CHAPTER_MARKUP_READY');
    if (!mounted ||
        generation != _chapterLoadGeneration ||
        context.read<ReaderProvider>().currentChapterIndex != targetIndex) {
      return;
    }

    final canReuseDocument =
        !forceFullDocument &&
        _readerDocumentReady &&
        _readerDocumentBookId == reader.book!.id;
    if (canReuseDocument) {
      final updateResult = await _webViewController
          .runJavaScriptReturningResult(
            ReaderDocumentHtml.buildUpdateScript(
              chapter: preparedChapter,
              requestId: performanceRequestId,
              pagingMode: settings.readerPagingMode,
              scrollToEnd: reader.scrollOffset < 0,
            ),
          );
      if (!mounted || generation != _chapterLoadGeneration) return;
      final updated = updateResult == true || updateResult.toString() == 'true';
      if (updated) {
        unawaited(_refreshParagraphThoughtMarkers(reader));
        return;
      }
    }

    final html = _buildChapterHtml(
      chapter.title,
      chapter.content,
      settings,
      highlights: chapterHighlights,
      readerFontAsset: fontAsset,
      preparedChapter: preparedChapter,
    );
    final filePath = await EpubService.getChapterFilePath(
      reader.book!.id,
      targetIndex,
    );
    if (!mounted || generation != _chapterLoadGeneration) return;
    final booksResourceRoot = p.dirname(p.dirname(filePath));
    final baseDir = Uri.directory(booksResourceRoot).toString();
    _readerDocumentReady = false;
    _pendingFullDocumentRequestId = performanceRequestId;
    await _webViewController.loadHtmlString(html, baseUrl: baseDir);
  }

  ReaderChapterMarkup _chapterMarkupFor({
    required String bookId,
    required int chapterIndex,
    required String title,
    required String content,
    required List<Highlight> highlights,
  }) {
    final highlightSignature = highlights
        .map((highlight) => '${highlight.id}:${highlight.updatedAt}')
        .join(',');
    final key = '$bookId:$chapterIndex:${content.hashCode}:$highlightSignature';
    final cached = _chapterMarkupCache[key];
    if (cached != null) return cached;
    final prepared = ReaderDocumentHtml.prepareChapter(
      title: title,
      content: content,
      highlights: highlights,
    );
    _chapterMarkupCache[key] = prepared;
    return prepared;
  }

  Future<void> _precacheAdjacentChapterMarkup(int centerIndex) async {
    if (!mounted) return;
    final reader = context.read<ReaderProvider>();
    final bookId = reader.book?.id;
    if (bookId == null) return;
    final indexes = [centerIndex - 1, centerIndex + 1]
        .where((index) => index >= 0 && index < reader.chapters.length)
        .toList(growable: false);
    final chapters = await Future.wait(indexes.map(reader.preloadChapter));
    if (!mounted || context.read<ReaderProvider>().book?.id != bookId) return;
    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      if (chapter == null) continue;
      final chapterIndex = indexes[i];
      final chapterHighlights = reader.highlights
          .where(
            (highlight) =>
                highlight.chapterIndex == chapter.sourceIndex.toString(),
          )
          .toList(growable: false);
      _chapterMarkupFor(
        bookId: bookId,
        chapterIndex: chapterIndex,
        title: chapter.title,
        content: chapter.content,
        highlights: chapterHighlights,
      );
    }
    if (_chapterMarkupCache.length > 8) {
      final retainedPrefixes = indexes
          .followedBy([centerIndex])
          .map((index) => '$bookId:$index:')
          .toList(growable: false);
      _chapterMarkupCache.removeWhere(
        (key, _) => !retainedPrefixes.any(key.startsWith),
      );
    }
  }

  String? _chapterLoadKey(ReaderProvider reader) {
    final bookId = reader.book?.id;
    final chapter = reader.currentChapter;
    if (bookId == null || chapter == null) return null;
    // A locally created highlight is patched into the existing document with
    // `wrapSelection`. Including highlights here would reload the chapter and
    // reset the reading surface while the user is still at their selection.
    return '$bookId:${reader.currentChapterIndex}:${chapter.index}:'
        '${chapter.content.length}';
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

  bool _scheduleTypographyActivationIfNeeded(
    ReaderProvider reader,
    SettingsProvider settings,
  ) {
    final bookId = reader.book?.id;
    if (bookId == null || settings.typographyReadyFor(bookId)) return false;
    if (_activatingTypographyBookId == bookId) return true;
    _activatingTypographyBookId = bookId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await settings.activateBook(bookId);
      if (!mounted || context.read<ReaderProvider>().book?.id != bookId) return;
      _activatingTypographyBookId = null;
      setState(() => _loadedChapterKey = null);
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
    ReaderFontAsset? readerFontAsset,
    ReaderChapterMarkup? preparedChapter,
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
      readerFontAsset: readerFontAsset,
      preparedChapter: preparedChapter,
    );
  }

  int _startPerformanceTrace(
    int targetIndex, {
    required String reason,
    DateTime? startedAt,
  }) {
    final requestId = ++_nextPerformanceRequestId;
    _performanceTraces[requestId] = _ChapterPerformanceTrace(
      requestId: requestId,
      chapterIndex: targetIndex,
      reason: reason,
      startedAt: startedAt ?? DateTime.now(),
    );
    _recordPerformanceStage(requestId, 'CHAPTER_TAP');
    if (_performanceTraces.length > 16) {
      final oldest = _performanceTraces.keys.reduce(
        (left, right) => left < right ? left : right,
      );
      _performanceTraces.remove(oldest);
    }
    return requestId;
  }

  int _performanceRequestForLoad(int targetIndex) {
    final pending = _pendingChapterIntent;
    if (pending != null && pending.chapterIndex == targetIndex) {
      _pendingChapterIntent = null;
      return pending.performanceRequestId;
    }
    return _startPerformanceTrace(targetIndex, reason: 'state_restore');
  }

  void _recordPerformanceStage(int requestId, String stage) {
    final trace = _performanceTraces[requestId];
    if (trace == null || trace.stages.containsKey(stage)) return;
    final elapsed = DateTime.now().difference(trace.startedAt).inMilliseconds;
    trace.stages[stage] = elapsed;
    debugPrint(
      '[ReaderPerf] request=$requestId chapter=${trace.chapterIndex} '
      'reason=${trace.reason} stage=$stage elapsed=${elapsed}ms',
    );
    if (stage == 'BODY_VISIBLE') {
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        if (!mounted) return;
        unawaited(_precacheAdjacentChapterMarkup(trace.chapterIndex));
      });
    }
  }

  void _navigateToChapter(
    int chapterIndex, {
    double scrollOffset = 0,
    required String reason,
  }) {
    final reader = context.read<ReaderProvider>();
    if (chapterIndex < 0 ||
        chapterIndex >= reader.chapters.length ||
        chapterIndex == reader.currentChapterIndex) {
      return;
    }
    final requestId = _startPerformanceTrace(chapterIndex, reason: reason);
    _pendingChapterIntent = _PendingChapterIntent(
      chapterIndex: chapterIndex,
      performanceRequestId: requestId,
    );
    reader.goToChapter(chapterIndex, scrollOffset: scrollOffset);
  }

  void _goNextChapter() {
    final reader = context.read<ReaderProvider>();
    if (reader.currentChapterIndex < reader.chapters.length - 1) {
      _navigateToChapter(reader.currentChapterIndex + 1, reason: 'next_button');
    }
  }

  void _goPrevChapter() {
    final reader = context.read<ReaderProvider>();
    if (reader.currentChapterIndex > 0) {
      _navigateToChapter(
        reader.currentChapterIndex - 1,
        reason: 'previous_button',
      );
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
      _navigateToChapter(
        reader.currentChapterIndex + 1,
        reason: 'next_boundary',
      );
    } else if (direction == 'prev' && reader.currentChapterIndex > 0) {
      _lastChapterBoundaryAt = now;
      _navigateToChapter(
        reader.currentChapterIndex - 1,
        scrollOffset: -1,
        reason: 'previous_boundary',
      );
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
      isScrollControlled: true,
      useSafeArea: true,
      // ReaderSettings owns the drag gesture so iOS does not let the outer
      // modal sheet intercept a vertical scroll before the content can move.
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => ReaderSettings(
        onReaderStyleChanged: () {
          unawaited(
            _applyReaderStyles(settingsProvider, preservePosition: true),
          );
        },
      ),
    ).then((_) async {
      final positionRatioBefore = await positionRatioFuture;
      await settingsProvider.flushTypographyPersistence();
      if (!mounted) return;
      await _applyReaderStyles(settingsProvider);
      if (settingsProvider.readerPagingMode != pagingBefore) {
        if (readerProvider.book?.format != 'pdf' &&
            positionRatioBefore != null) {
          _restoreScrollRatio(positionRatioBefore);
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
            final typographyPending =
                reader.book?.format != 'pdf' &&
                _scheduleTypographyActivationIfNeeded(reader, settings);
            if (reader.isLoading) {
              return _buildLoading(reader.loadingMessage);
            }
            if (reader.loadError != null) {
              return _buildLoadError(reader.loadError!);
            }
            if (typographyPending) {
              return _buildLoading(context.l10n.restoringTypography);
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
                                _loadChapter(forceFullDocument: true);
                              },
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(context.l10n.reloadContent),
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
                        _hideSelectionGuideTip();
                        unawaited(_beginAiExplanation(reader));
                      },
                      onAsk: () {
                        _hideSelectionGuideTip();
                        unawaited(
                          _showReaderQuestion(reader, fromSelection: true),
                        );
                      },
                      onHighlight: (color) async {
                        _hideSelectionGuideTip();
                        final chapter = reader.currentChapter;
                        if (chapter != null) {
                          final scrollRatio = await _captureScrollRatio();
                          if (!mounted) return;
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
                          if (scrollRatio != null) {
                            _restoreScrollRatio(scrollRatio);
                          }
                          _hasWebSelection = false;
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(context.l10n.organizedByXiaou),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        }
                        reader.clearSelection();
                      },
                      onNote: () {
                        _hideSelectionGuideTip();
                        unawaited(_showNoteDialog(reader));
                      },
                      onDismiss: () {
                        _hideSelectionGuideTip();
                        _clearReaderSelection(reader);
                      },
                    ),
                  ),

                if (_showSelectionGuideTip) const ReaderSelectionGuideTip(),

                if (reader.showAiPanel)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeInOutCubic,
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: _aiPanelExpanded
                        ? MediaQuery.of(context).size.height -
                              MediaQuery.of(context).padding.top -
                              8
                        : (MediaQuery.of(context).size.height * 0.4).clamp(
                            310.0,
                            430.0,
                          ),
                    child: AiExplanationCard(
                      isExpanded: _aiPanelExpanded,
                      onToggleExpanded: () {
                        setState(() => _aiPanelExpanded = !_aiPanelExpanded);
                      },
                      onClose: () => _closeAiExplanation(reader),
                    ),
                  ),

                if (_showControls) _buildTopBar(reader),
                if (_showControls) _buildBottomBar(reader),
                if (_showLongPressGuide)
                  ReaderLongPressGuide(
                    onTry: _tryLongPressGuide,
                    onDismiss: _dismissLongPressGuide,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _exitReader() async {
    if (_isExiting) return;

    setState(() => _isExiting = true);

    final reader = context.read<ReaderProvider>();
    reader.cancelScheduledSave();
    unawaited(reader.saveProgress().catchError((_) {}));
    await (_settingsProvider ?? context.read<SettingsProvider>())
        .flushTypographyPersistence()
        .catchError((_) {});

    if (!mounted) return;
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

  String? _paragraphThoughtsKey(ReaderProvider reader) {
    final bookId = reader.book?.id;
    final chapterIndex = reader.currentChapter?.sourceIndex;
    if (bookId == null || chapterIndex == null) return null;
    return '$bookId:$chapterIndex:${AuthService.userId ?? ''}';
  }

  Future<void> _refreshParagraphThoughtMarkers(ReaderProvider reader) async {
    final key = _paragraphThoughtsKey(reader);
    if (key == null) return;
    final bookId = reader.book!.id;
    final chapterIndex = reader.currentChapter!.sourceIndex.toString();
    try {
      final entries = await BookService.getLocalUserEntries(
        bookId: bookId,
        source: 'thought',
        userId: AuthService.userId ?? '',
      );
      if (!mounted || _paragraphThoughtsKey(reader) != key) return;
      final currentChapterThoughts = entries
          .where(
            (entry) =>
                entry.chapterIndex == chapterIndex &&
                _paragraphIndexForThought(entry) != null,
          )
          .toList(growable: false);
      _currentParagraphThoughts = currentChapterThoughts;
      _paragraphThoughtsChapterKey = key;
      if (!_readerDocumentReady) return;
      final counts = <int, int>{};
      for (final entry in currentChapterThoughts) {
        final paragraphIndex = _paragraphIndexForThought(entry);
        if (paragraphIndex != null) {
          counts.update(
            paragraphIndex,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
      }
      final markers = counts.entries
          .map(
            (entry) => <String, int>{
              'paragraphIndex': entry.key,
              'count': entry.value,
            },
          )
          .toList(growable: false);
      await _webViewController.runJavaScript(
        'window.readerSetThoughtMarkers && '
        'window.readerSetThoughtMarkers(${jsonEncode(markers)});',
      );
    } catch (error) {
      debugPrint('[ReaderThoughtMarker] refresh failed: $error');
    }
  }

  int? _paragraphIndexForThought(UserEntry entry) {
    final raw = entry.metadataJson.trim();
    if (raw.isEmpty) return null;
    try {
      final metadata = jsonDecode(raw);
      if (metadata is! Map) return null;
      final value = metadata['paragraph_index'];
      return switch (value) {
        int value => value,
        num value => value.toInt(),
        String value => int.tryParse(value),
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  Future<_ReaderParagraphAnchor?> _captureReaderParagraphAnchor() async {
    try {
      final raw = await _webViewController.runJavaScriptReturningResult(
        'window.readerSelectionAnchor ? window.readerSelectionAnchor() : "";',
      );
      var value = raw.toString();
      if (value.isEmpty || value == 'null') return null;
      dynamic decoded = jsonDecode(value);
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is! Map) return null;
      final index = switch (decoded['paragraphIndex']) {
        int value => value,
        num value => value.toInt(),
        String value => int.tryParse(value),
        _ => null,
      };
      if (index == null || index < 0) return null;
      return _ReaderParagraphAnchor(
        paragraphIndex: index,
        paragraphText: decoded['paragraphText']?.toString() ?? '',
      );
    } catch (error) {
      debugPrint('[ReaderThoughtMarker] selection anchor unavailable: $error');
      return null;
    }
  }

  Future<void> _showParagraphThoughts(int paragraphIndex) async {
    final reader = context.read<ReaderProvider>();
    final key = _paragraphThoughtsKey(reader);
    if (key == null) return;
    if (_paragraphThoughtsChapterKey != key) {
      await _refreshParagraphThoughtMarkers(reader);
    }
    if (!mounted || _paragraphThoughtsChapterKey != key) return;
    final thoughts = _currentParagraphThoughts
        .where((entry) => _paragraphIndexForThought(entry) == paragraphIndex)
        .toList(growable: false);
    if (thoughts.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReaderParagraphThoughtsSheet(thoughts: thoughts),
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
    if (_aiPanelExpanded && mounted) {
      setState(() => _aiPanelExpanded = false);
    }
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
    if (_aiPanelExpanded && mounted) {
      setState(() => _aiPanelExpanded = false);
    }
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

  Future<void> _showReaderQuestion(
    ReaderProvider reader, {
    bool fromSelection = false,
  }) async {
    final book = reader.book;
    final chapter = reader.currentChapter;
    if (book == null || chapter == null || book.format == 'pdf') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.pageTextUnavailable)),
        );
      }
      return;
    }
    if (!await AiConsentGate.ensure(context) || !mounted) return;

    final selectedText = fromSelection
        ? (reader.selectedText?.trim() ?? '')
        : '';
    final plainText = EpubService.getPlainText(
      chapter.content,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    final ratio = await _captureScrollRatio() ?? 0.5;
    if (!mounted) return;
    var pageText = await _captureVisibleReaderText();
    if (!mounted) return;
    if (pageText.isEmpty) {
      pageText = _textWindowAtRatio(plainText, ratio, 5000);
    }
    final chapterText = _textWindowAtRatio(plainText, ratio, 24000);
    var contextBefore = '';
    var contextAfter = '';
    if (selectedText.isNotEmpty) {
      final selectedOffset = _findSelectedTextOffset(plainText, selectedText);
      if (selectedOffset >= 0) {
        final beforeStart = (selectedOffset - 2600).clamp(0, selectedOffset);
        contextBefore = plainText.substring(beforeStart, selectedOffset);
        final afterStart = (selectedOffset + selectedText.length).clamp(
          0,
          plainText.length,
        );
        final afterEnd = (afterStart + 2600).clamp(
          afterStart,
          plainText.length,
        );
        contextAfter = plainText.substring(afterStart, afterEnd);
      }
    }

    final initialScope = selectedText.isNotEmpty
        ? ReaderQuestionScope.selection
        : ReaderQuestionScope.page;
    final questionContext = ReaderQuestionContext(
      bookTitle: _bookTitleForDisplay(reader),
      bookAuthor: book.author,
      chapterTitle: chapter.title,
      selectedText: selectedText,
      pageText: pageText,
      chapterText: chapterText,
      contextBefore: contextBefore,
      contextAfter: contextAfter,
    );

    final controlsBefore = _showControls;
    if (selectedText.isNotEmpty) {
      try {
        await _webViewController.runJavaScript(
          'window.freezeSelectionForAi && window.freezeSelectionForAi();',
        );
      } catch (_) {}
      reader.clearSelection();
      _hasWebSelection = false;
    }
    if (_showControls && mounted) setState(() => _showControls = false);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReaderQuestionSheet(
        readerContext: questionContext,
        initialScope: initialScope,
        onSaveFirstAnswer: (question, answer, scope) {
          final recordText = questionContext.previewFor(scope);
          return reader.addAiQuestion(
            question: question,
            answer: answer,
            scope: scope.apiValue,
            contextText: recordText.length > 6000
                ? '${recordText.substring(0, 6000)}……'
                : recordText,
            pageText: pageText.length > 4000
                ? '${pageText.substring(0, 4000)}……'
                : pageText,
          );
        },
        onSaveFollowUp: (entryId, question, answer) async {
          await BookService.insertUserEntryFollowUp(
            entryId: entryId,
            question: question,
            answer: answer,
          );
        },
      ),
    );

    if (!mounted) return;
    if (selectedText.isNotEmpty) {
      unawaited(
        _webViewController
            .runJavaScript(
              'window.releaseAiSelection && window.releaseAiSelection();',
            )
            .catchError((_) {}),
      );
    }
    if (_showControls != controlsBefore) {
      setState(() => _showControls = controlsBefore);
    }
  }

  Future<String> _captureVisibleReaderText() async {
    try {
      final result = await _webViewController.runJavaScriptReturningResult(
        'window.readerVisibleText ? window.readerVisibleText() : "";',
      );
      if (result is String) {
        final raw = result.trim();
        if (raw.startsWith('"') && raw.endsWith('"')) {
          final decoded = jsonDecode(raw);
          return decoded?.toString().trim() ?? '';
        }
        return raw;
      }
      return result.toString().trim();
    } catch (_) {
      return '';
    }
  }

  String _textWindowAtRatio(String text, double ratio, int maxChars) {
    if (text.length <= maxChars) return text;
    final safeRatio = ratio.clamp(0.0, 1.0).toDouble();
    final center = (text.length * safeRatio).round();
    final start = (center - maxChars ~/ 2).clamp(0, text.length - maxChars);
    return text.substring(start, start + maxChars);
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
    return fallback.isNotEmpty ? fallback : context.l10n.untitledBook;
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
                PopupMenuItem(
                  value: 'toc',
                  child: Text(context.l10n.tableOfContents),
                ),
                PopupMenuItem(
                  value: 'bookmarks',
                  child: Text(context.l10n.bookmarks),
                ),
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
            Text(
              context.l10n.readerOpenFailed,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final palette = sheetContext.appPalette;
        final visuals = sheetContext.appVisuals;
        final height = MediaQuery.sizeOf(sheetContext).height * 0.72;
        return SafeArea(
          top: false,
          child: Container(
            height: height,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  child: Container(
                    width: 34,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.divider,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  context.l10n.tableOfContents,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.separated(
                    itemCount: reader.chapters.length,
                    separatorBuilder: (_, _) => Divider(
                      color: palette.divider.withValues(alpha: 0.7),
                      height: 1,
                    ),
                    itemBuilder: (_, i) {
                      final isCurrent = i == reader.currentChapterIndex;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(
                            visuals.controlRadius,
                          ),
                          onTap: () {
                            _navigateToChapter(i, reason: 'table_of_contents');
                            Navigator.pop(sheetContext);
                          },
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 52),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? palette.selectedBackground.withValues(
                                      alpha: 0.56,
                                    )
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(
                                visuals.controlRadius,
                              ),
                              border: isCurrent
                                  ? Border(
                                      left: BorderSide(
                                        color: palette.primary,
                                        width: 3,
                                      ),
                                    )
                                  : null,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                reader.chapters[i].title,
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.45,
                                  fontWeight: isCurrent
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: isCurrent
                                      ? palette.primaryDeep
                                      : palette.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showNoteDialog(ReaderProvider reader) async {
    final book = reader.book;
    final selectedText = reader.selectedText?.trim() ?? '';
    if (book == null || selectedText.isEmpty) return;
    final paragraphAnchor = await _captureReaderParagraphAnchor();
    if (!mounted) return;
    await AuthService.init();
    if (!mounted) return;
    final chapterTitle = reader.currentChapter?.title.trim() ?? '';
    final chapterLabel = chapterTitle.isNotEmpty
        ? chapterTitle
        : context.l10n.chapterNumber(reader.currentChapterIndex + 1);
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

    final entryId = await reader.addThought(
      content: result.content,
      anchorMetadata: paragraphAnchor?.toMetadata() ?? const {},
    );
    await _refreshParagraphThoughtMarkers(reader);
    if (!mounted) return;
    if (!result.isPublic) {
      _clearReaderSelection(reader);
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.l10n.thoughtSavedPrivate),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    if (!await ensureCommunityGuidelines(context) || !mounted) {
      _clearReaderSelection(reader);
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.thoughtSavedPrivateNotShared)),
      );
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
          content: Text(context.l10n.publishedToMingtai),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: context.l10n.view,
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
        SnackBar(
          content: Text(
            context.l10n.thoughtPrivatePublishFailed(
              _readerError(error, context.l10n.pleaseTryAgain),
            ),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _selectionGuideTimer?.cancel();
    final settings = _settingsProvider;
    if (settings != null) {
      unawaited(settings.flushTypographyPersistence().catchError((_) {}));
    }
    super.dispose();
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
      setState(() => _error = context.l10n.writeThoughtFirst);
      return;
    }
    if (_isPublic && content.length < 5) {
      setState(() => _error = context.l10n.publicThoughtMinLength);
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
                Text(
                  context.l10n.writeThought,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
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
                  decoration: InputDecoration(
                    hintText: context.l10n.thoughtPrompt,
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 14),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(context.l10n.privateOnly),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(context.l10n.shareToMingtai),
                    ),
                  ],
                  selected: {_isPublic},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) {
                    final next = value.first;
                    if (next && !widget.canPublish) {
                      setState(() => _error = context.l10n.loginToPublish);
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
                  _isPublic
                      ? context.l10n.publicThoughtExplanation
                      : context.l10n.privateThoughtExplanation,
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
                      child: Text(context.l10n.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _submit,
                      child: Text(
                        _isPublic
                            ? context.l10n.publishToMingtai
                            : context.l10n.keepPrivate,
                      ),
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

class _ReaderParagraphAnchor {
  final int paragraphIndex;
  final String paragraphText;

  const _ReaderParagraphAnchor({
    required this.paragraphIndex,
    required this.paragraphText,
  });

  Map<String, dynamic> toMetadata() => {
    'paragraph_index': paragraphIndex,
    'paragraph_text': paragraphText,
  };
}

class _ReaderParagraphThoughtsSheet extends StatelessWidget {
  final List<UserEntry> thoughts;

  const _ReaderParagraphThoughtsSheet({required this.thoughts});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final excerpt = thoughts
        .map((thought) => thought.originalText.trim())
        .firstWhere((text) => text.isNotEmpty, orElse: () => '');
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.68,
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: palette.divider.withValues(alpha: 0.55)),
      ),
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
          Text(
            context.l10n.readerThought,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (excerpt.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.primarySoft.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '“$excerpt”',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                  height: 1.55,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: thoughts.length,
              separatorBuilder: (_, _) => Divider(
                color: palette.divider.withValues(alpha: 0.65),
                height: 20,
              ),
              itemBuilder: (context, index) {
                final thought = thoughts[index];
                return Text(
                  thought.userInput.trim(),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    height: 1.7,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingChapterIntent {
  final int chapterIndex;
  final int performanceRequestId;

  const _PendingChapterIntent({
    required this.chapterIndex,
    required this.performanceRequestId,
  });
}

class _ChapterPerformanceTrace {
  final int requestId;
  final int chapterIndex;
  final String reason;
  final DateTime startedAt;
  final Map<String, int> stages = {};

  _ChapterPerformanceTrace({
    required this.requestId,
    required this.chapterIndex,
    required this.reason,
    required this.startedAt,
  });
}

String _readerError(Object error, String fallback) {
  final message = error.toString().replaceFirst('Exception: ', '').trim();
  return message.isEmpty ? fallback : message;
}
