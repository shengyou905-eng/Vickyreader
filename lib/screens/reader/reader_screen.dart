import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../config/reader_paging_mode.dart';
import '../../config/theme.dart';
import '../../models/highlight.dart';
import '../../providers/reader_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/epub_service.dart';
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

  @override
  void initState() {
    super.initState();
    _initWebView();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reader = context.read<ReaderProvider>();
      if (reader.book?.format != 'pdf' && reader.currentChapter != null) {
        _loadChapter();
      }
    });
  }

  void _initWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _onPageReady(),
          onNavigationRequest: (request) {
            if (request.url.startsWith('about:blank')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: _onJsMessage,
      );
  }

  void _onPageReady() {
    if (!mounted) return;
    _ignoreChapterMessages = false;
    final reader = context.read<ReaderProvider>();
    final settings = context.read<SettingsProvider>();
    _applyReaderStyles(settings);
    if (reader.scrollOffset > 0) {
      final v = reader.scrollOffset;
      final horizontal =
          settings.readerPagingMode == ReaderPagingMode.horizontal;
      _webViewController.runJavaScript(
        horizontal
            ? "(function(){var s=document.getElementById('readSurface');if(s)s.scrollLeft=$v;})();"
            : "(function(){var s=document.getElementById('readSurface');if(s)s.scrollTop=$v;})();",
      );
    }
    final target = reader.scrollToTextTarget;
    if (target != null) {
      _webViewController.runJavaScript(
        "scrollToText('${_jsEscape(target)}')",
      );
      reader.setScrollTarget(null);
    }
  }

  void _applyReaderStyles(SettingsProvider settings) {
    final css = '''
      document.documentElement.style.setProperty('--font-size', '${settings.fontSize}px');
      document.documentElement.style.setProperty('--line-height', '${settings.lineHeight}');
      document.documentElement.style.setProperty('--bg-color', '${_colorToHex(settings.backgroundColor)}');
      document.documentElement.style.setProperty('--text-color', '${_colorToHex(settings.textColor)}');
    ''';
    _webViewController.runJavaScript(css);
  }

  String _colorToHex(Color color) {
    final r = (color.r * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final g = (color.g * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final b = (color.b * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
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
      context.read<ReaderProvider>().selectText(selectedText);
    } else if (text.startsWith('CHAPTER|')) {
      if (_ignoreChapterMessages) return;
      final offset = int.tryParse(text.substring(8)) ?? 0;
      if (offset > 0) {
        final reader = context.read<ReaderProvider>();
        final newIdx = reader.currentChapterIndex + offset;
        if (newIdx < reader.chapters.length && newIdx != reader.currentChapterIndex) {
          reader.goToChapter(newIdx);
        }
      }
    } else if (text.startsWith('SCROLL|')) {
      final offset = double.tryParse(text.substring(7)) ?? 0;
      context.read<ReaderProvider>().updateScrollOffset(offset);
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

    final spine = await EpubService.getSpine(book.id);
    final targetHref = href.split('#').first;
    for (int i = 0; i < spine.length; i++) {
      if (spine[i].endsWith(targetHref) || targetHref.endsWith(spine[i].split('/').last)) {
        if (i < reader.chapters.length) {
          reader.goToChapter(i);
          _loadChapter();
        }
        return;
      }
    }
  }

  Future<void> _loadChapter() async {
    final reader = context.read<ReaderProvider>();
    final chapter = reader.currentChapter;
    if (chapter == null) return;
    if (reader.book == null) return;

    final settings = context.read<SettingsProvider>();
    final chapterIdx = reader.currentChapterIndex.toString();
    final chapterHighlights = reader.highlights
        .where((h) => h.chapterIndex == chapterIdx)
        .toList();

    final List<Map<String, String>> nextChapters = [];
    for (int i = 1; i <= 2; i++) {
      final idx = reader.currentChapterIndex + i;
      if (idx < reader.chapters.length) {
        nextChapters.add({
          'title': reader.chapters[idx].title,
          'content': reader.chapters[idx].content,
        });
      }
    }
    final html = _buildChapterHtml(
      chapter.title,
      chapter.content,
      settings,
      highlights: chapterHighlights,
      nextChapters: nextChapters,
    );
    final filePath = await EpubService.getChapterFilePath(
        reader.book!.id, reader.currentChapterIndex);
    await File(filePath).writeAsString(html);
    final baseDir = Uri.directory(p.dirname(filePath)).toString();
    _webViewController.loadHtmlString(html, baseUrl: baseDir);
  }

  String _buildChapterHtml(
      String title, String content, SettingsProvider settings,
      {List<Highlight> highlights = const [],
       List<Map<String, String>> nextChapters = const []}) {
    return ReaderDocumentHtml.build(
      title: title,
      content: content,
      settings: settings,
      highlights: highlights,
      pagingMode: settings.readerPagingMode,
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

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  void _showSettings() {
    final pagingBefore = context.read<SettingsProvider>().readerPagingMode;
    showModalBottomSheet(
      context: context,
      builder: (_) => const ReaderSettings(),
    ).then((_) {
      if (!mounted) return;
      final settings = context.read<SettingsProvider>();
      _applyReaderStyles(settings);
      if (settings.readerPagingMode != pagingBefore) {
        final reader = context.read<ReaderProvider>();
        final book = reader.book;
        if (book != null && book.format != 'pdf') {
          _ignoreChapterMessages = true;
          reader.setScrollOffset(0);
          _loadChapter();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer2<ReaderProvider, SettingsProvider>(
        builder: (context, reader, settings, _) {
          if (reader.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final isPdf = reader.book?.format == 'pdf';

          return Stack(
            children: [
              if (isPdf)
                Stack(
                  children: [
                    PdfReaderWidget(
                      key: ValueKey(settings.readerPagingMode),
                      scrollDirection:
                          settings.readerPagingMode == ReaderPagingMode.horizontal
                              ? Axis.horizontal
                              : Axis.vertical,
                    ),
                    Positioned(
                      top: 0, left: 0, right: 0,
                      height: 48,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _toggleControls,
                      ),
                    ),
                  ],
                )
              else
                WebViewWidget(controller: _webViewController),

              if (reader.selectedText != null)
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: SelectionMenu(
                    selectedText: reader.selectedText!,
                    onExplain: () => reader.showAiExplanation(),
                    onHighlight: (color) async {
                      final chapter = reader.currentChapter;
                      if (chapter != null) {
                        final plainText = EpubService.getPlainText(chapter.content);
                        final startIdx = plainText.indexOf(reader.selectedText!);
                        if (startIdx >= 0) {
                          final textContext = EpubService.getContext(
                            chapter.content,
                            reader.selectedText!,
                            200,
                          );
                          await reader.addHighlight(
                            selectedText: reader.selectedText!,
                            contextBefore: textContext.before,
                            contextAfter: textContext.after,
                            startOffset: startIdx,
                            endOffset: startIdx + reader.selectedText!.length,
                            color: color,
                          );
                          _webViewController.runJavaScript(
                            "wrapSelection('$color', '${_jsEscape(reader.selectedText!)}')",
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已由小U整理'), duration: Duration(seconds: 1)),
                            );
                          }
                        }
                      }
                      reader.clearSelection();
                    },
                    onNote: () => _showNoteDialog(reader),
                    onDismiss: () => reader.clearSelection(),
                  ),
                ),

              if (reader.showAiPanel)
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  height: MediaQuery.of(context).size.height * 0.4,
                  child: const AiExplanationCard(),
                ),

              if (_showControls) _buildTopBar(reader),
              if (_showControls) _buildBottomBar(reader),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopBar(ReaderProvider reader) {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        color: context.read<SettingsProvider>().backgroundColor.withAlpha(230),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                reader.saveProgress();
                Navigator.of(context).pop();
              },
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(reader.book?.title ?? '',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (reader.currentChapter != null)
                    Text(reader.currentChapter!.title,
                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
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
      bottom: 0, left: 0, right: 0,
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
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
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

  void _showTableOfContents(ReaderProvider reader) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('目录', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: reader.chapters.length,
                itemBuilder: (_, i) => ListTile(
                  dense: true,
                  title: Text(reader.chapters[i].title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: i == reader.currentChapterIndex ? FontWeight.w600 : FontWeight.normal,
                      color: i == reader.currentChapterIndex ? AppTheme.primary : AppTheme.textPrimary,
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

  void _showNoteDialog(ReaderProvider reader) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('写想法'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(hintText: '记录你的想法...'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              reader.clearSelection();
              Navigator.pop(ctx);
            },
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final noteContent = controller.text.trim();
              if (noteContent.isNotEmpty) {
                await reader.addThought(content: noteContent);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已由小U整理'), duration: Duration(seconds: 1)),
                  );
                }
              }
              reader.clearSelection();
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
