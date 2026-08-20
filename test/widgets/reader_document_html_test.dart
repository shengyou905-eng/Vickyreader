import 'package:ai_reader/config/reader_paging_mode.dart';
import 'package:ai_reader/config/reader_typography.dart';
import 'package:ai_reader/providers/settings_provider.dart';
import 'package:ai_reader/screens/reader/widgets/reader_document_html.dart';
import 'package:ai_reader/services/reader_font_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReaderDocumentHtml', () {
    test('applies typography to EPUB descendants without flattening semantics', () {
      final settings = SettingsProvider()
        ..setReaderFontFamily(ReaderFontFamily.serif)
        ..setFontSize(20)
        ..setLineHeight(1.8)
        ..setPageMargin(24);

      final html = ReaderDocumentHtml.build(
        title: '测试章节',
        content: '''
          <h2>原有标题</h2>
          <style>p, strong { font-family: "Publisher Font"; }</style>
          <p style="font-family: Publisher Inline">正文<strong>粗体</strong><em>斜体</em><sup>脚注</sup></p>
          <blockquote>原有引用</blockquote>
        ''',
        settings: settings,
        highlights: const [],
        pagingMode: ReaderPagingMode.vertical,
        readerFontAsset: const ReaderFontAsset(
          cssFamily: 'ZhiDu Source Han Serif',
          uri: 'file:///reader_fonts/SourceHanSerifCN-Regular.otf',
          format: 'opentype',
        ),
      );

      expect(html, contains('--font-size: 20.0px'));
      expect(html, contains('--line-height: 1.8'));
      expect(html, contains('--page-pad-x: 24.0px'));
      expect(html, contains('"ZhiDu Source Han Serif"'));
      expect(html, contains('SourceHanSerifCN-Regular.otf'));
      expect(html, contains('<h2>原有标题</h2>'));
      expect(html, contains('<strong>粗体</strong>'));
      expect(html, contains('<em>斜体</em>'));
      expect(html, contains('<sup>脚注</sup>'));
      expect(html, contains('<blockquote>原有引用</blockquote>'));
      expect(
        html,
        contains(
          '.chapter-body * {\n    font-family: var(--reader-font-family) !important;',
        ),
      );
      expect(
        html,
        contains(
          '.chapter-title {\n    font-family: var(--reader-font-family) !important;',
        ),
      );
      expect(html, contains('font-weight: bold'));
      expect(html, contains('font-style: italic'));
      expect(html, contains('.chapter-body p, .chapter-body li {'));
      expect(html, contains('text-align: justify !important;'));
      expect(html, contains('text-justify: inter-ideograph;'));
      expect(html, contains('.chapter-title {\n    font-family'));
      expect(html, contains('text-align: center;'));
    });

    test('adds the embedded WenKai face and keeps fallback fonts', () {
      final settings = SettingsProvider()
        ..setReaderFontFamily(ReaderFontFamily.wenkai);

      final html = ReaderDocumentHtml.build(
        title: '第一章',
        content: '<p>山川入卷</p>',
        settings: settings,
        highlights: const [],
        pagingMode: ReaderPagingMode.horizontal,
        readerFontAsset: const ReaderFontAsset(
          cssFamily: 'LXGW WenKai Lite',
          uri: 'file:///reader_fonts/LXGWWenKaiLite-Regular.ttf',
          format: 'truetype',
        ),
      );

      expect(html, contains('@font-face'));
      expect(html, contains('font-family: "LXGW WenKai Lite"'));
      expect(html, contains('"Kaiti SC"'));
      expect(html, contains('data-paging="horizontal"'));
    });

    test('adds the embedded Source Han Serif face for Song typography', () {
      final settings = SettingsProvider()
        ..setReaderFontFamily(ReaderFontFamily.serif);

      final html = ReaderDocumentHtml.build(
        title: '第一章',
        content: '<p>山川入卷</p>',
        settings: settings,
        highlights: const [],
        pagingMode: ReaderPagingMode.vertical,
        readerFontAsset: const ReaderFontAsset(
          cssFamily: 'ZhiDu Source Han Serif',
          uri: 'file:///reader_fonts/SourceHanSerifCN-Regular.otf',
          format: 'opentype',
        ),
      );

      expect(html, contains('font-family: "ZhiDu Source Han Serif"'));
      expect(html, contains('SourceHanSerifCN-Regular.otf'));
      expect(html, contains('format("opentype")'));
    });

    test('TXT chapter HTML uses the same body typography pipeline', () {
      final settings = SettingsProvider()
        ..setReaderFontFamily(ReaderFontFamily.wenkai)
        ..setPageMargin(30);
      final html = ReaderDocumentHtml.build(
        title: '第一部分',
        content: '''<!DOCTYPE html><html><body>
          <h1 class="chapter-title">第一部分</h1>
          <p>这是 TXT 正文。</p>
        </body></html>''',
        settings: settings,
        highlights: const [],
        pagingMode: ReaderPagingMode.vertical,
        readerFontAsset: const ReaderFontAsset(
          cssFamily: 'LXGW WenKai Lite',
          uri: 'file:///reader_fonts/LXGWWenKaiLite-Regular.ttf',
          format: 'truetype',
        ),
      );

      expect(html, contains('<div class="chapter-body">'));
      expect(html, contains('<p>这是 TXT 正文。</p>'));
      expect('<h1 class="chapter-title">第一部分</h1>'.allMatches(html).length, 1);
      expect(html, contains('--page-pad-x: 30.0px'));
      expect(html, contains('font-family: "LXGW WenKai Lite"'));
      expect(html, contains('LXGWWenKaiLite-Regular.ttf'));
    });

    test('keeps the font face in the reusable document shell only once', () {
      final settings = SettingsProvider()
        ..setReaderFontFamily(ReaderFontFamily.serif);
      final html = ReaderDocumentHtml.build(
        title: '第一章',
        content: '<p>正文</p>',
        settings: settings,
        highlights: const [],
        pagingMode: ReaderPagingMode.horizontal,
        readerFontAsset: const ReaderFontAsset(
          cssFamily: 'ZhiDu Source Han Serif',
          uri: 'file:///books/.reader_fonts/SourceHanSerifCN-Regular.otf',
          format: 'opentype',
        ),
      );

      expect('id="reader-font-face"'.allMatches(html).length, 1);
      expect(html, contains('window.readerReplaceChapter'));
      expect(html, contains('window.readerReportInitialReady'));
      expect(html, contains('(faces && faces.length)'));
      expect(html, contains("'FONT_FALLBACK'"));
      expect(html, contains('window.readerVisibleText'));
      expect(html, contains("return parts.join(' ').slice(0, 7000);"));
      expect(html, isNot(contains("parts.join('\n')")));
    });

    test('builds an atomic chapter update without reinjecting font CSS', () {
      final chapter = ReaderDocumentHtml.prepareChapter(
        title: '第二章',
        content: '<p>新的正文<strong>仍保留粗体</strong></p>',
        highlights: const [],
      );
      final script = ReaderDocumentHtml.buildUpdateScript(
        chapter: chapter,
        requestId: 7,
        pagingMode: ReaderPagingMode.vertical,
        scrollToEnd: true,
      );

      expect(script, contains('readerReplaceChapter'));
      expect(script, contains('新的正文'));
      expect(script, contains('仍保留粗体'));
      expect(script, contains('"requestId":7'));
      expect(script, contains('"scrollToEnd":true'));
      expect(script, isNot(contains('@font-face')));
      expect(script, isNot(contains('<!DOCTYPE html>')));
    });

    test('exposes private paragraph thought anchors and marker updates', () {
      final html = ReaderDocumentHtml.build(
        title: '第一章',
        content: '<p>一段可以留下想法的文字。</p><p>另一段正文。</p>',
        settings: SettingsProvider(),
        highlights: const [],
        pagingMode: ReaderPagingMode.vertical,
      );

      expect(html, contains('window.readerSelectionAnchor'));
      expect(html, contains('window.readerSetThoughtMarkers'));
      expect(html, contains('data-reader-paragraph-index'));
      expect(html, contains('reader-thought-marker'));
      expect(
        html,
        contains("FlutterBridge.postMessage('THOUGHT_MARKER|' + index)"),
      );
    });
  });
}
