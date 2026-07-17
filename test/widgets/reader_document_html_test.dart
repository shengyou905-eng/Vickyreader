import 'package:ai_reader/config/reader_paging_mode.dart';
import 'package:ai_reader/config/reader_typography.dart';
import 'package:ai_reader/providers/settings_provider.dart';
import 'package:ai_reader/screens/reader/widgets/reader_document_html.dart';
import 'package:ai_reader/services/reader_font_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReaderDocumentHtml', () {
    test('applies typography variables without flattening EPUB semantics', () {
      final settings = SettingsProvider()
        ..setReaderFontFamily(ReaderFontFamily.serif)
        ..setFontSize(20)
        ..setLineHeight(1.8)
        ..setPageMargin(24);

      final html = ReaderDocumentHtml.build(
        title: '测试章节',
        content: '''
          <h2>原有标题</h2>
          <p>正文<strong>粗体</strong><em>斜体</em><sup>脚注</sup></p>
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
      expect(html, isNot(contains('.chapter-body * { font-family:')));
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
  });
}
