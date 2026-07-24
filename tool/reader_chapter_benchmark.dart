import 'package:ai_reader/config/reader_paging_mode.dart';
import 'package:ai_reader/config/reader_typography.dart';
import 'package:ai_reader/providers/settings_provider.dart';
import 'package:ai_reader/screens/reader/widgets/reader_document_html.dart';
import 'package:ai_reader/services/reader_font_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reader chapter payload benchmark', () {
    final settings = SettingsProvider()
      ..setReaderFontFamily(ReaderFontFamily.serif);
    final content = '<!DOCTYPE html><html><body>${List.generate(
      300,
      (index) => '<p>第$index段：阅读让遥远的思想在此刻重新发生，并保留<strong>强调</strong>与<em>语义</em>。</p>',
    ).join()}</body></html>';
    const font = ReaderFontAsset(
      cssFamily: 'ZhiDu Source Han Serif',
      uri: 'file:///books/.reader_fonts/SourceHanSerifCN-Regular.otf',
      format: 'opentype',
    );

    for (var i = 0; i < 5; i++) {
      ReaderDocumentHtml.build(
        title: '章节$i',
        content: content,
        settings: settings,
        highlights: const [],
        pagingMode: ReaderPagingMode.horizontal,
        readerFontAsset: font,
      );
    }

    const rounds = 50;
    final fullWatch = Stopwatch()..start();
    late String fullHtml;
    for (var i = 0; i < rounds; i++) {
      fullHtml = ReaderDocumentHtml.build(
        title: '章节$i',
        content: content,
        settings: settings,
        highlights: const [],
        pagingMode: ReaderPagingMode.horizontal,
        readerFontAsset: font,
      );
    }
    fullWatch.stop();

    final coldWatch = Stopwatch()..start();
    late String coldScript;
    for (var i = 0; i < rounds; i++) {
      final markup = ReaderDocumentHtml.prepareChapter(
        title: '章节$i',
        content: content,
        highlights: const [],
      );
      coldScript = ReaderDocumentHtml.buildUpdateScript(
        chapter: markup,
        requestId: i,
        pagingMode: ReaderPagingMode.horizontal,
      );
    }
    coldWatch.stop();

    final cachedMarkup = ReaderDocumentHtml.prepareChapter(
      title: '缓存章节',
      content: content,
      highlights: const [],
    );
    final cachedWatch = Stopwatch()..start();
    late String cachedScript;
    for (var i = 0; i < rounds; i++) {
      cachedScript = ReaderDocumentHtml.buildUpdateScript(
        chapter: cachedMarkup,
        requestId: i,
        pagingMode: ReaderPagingMode.horizontal,
      );
    }
    cachedWatch.stop();

    // ignore: avoid_print
    print(
      'BENCH full_avg_us=${fullWatch.elapsedMicroseconds ~/ rounds} '
      'incremental_cold_avg_us=${coldWatch.elapsedMicroseconds ~/ rounds} '
      'incremental_cached_avg_us=${cachedWatch.elapsedMicroseconds ~/ rounds} '
      'full_bytes=${fullHtml.length} cold_bytes=${coldScript.length} '
      'cached_bytes=${cachedScript.length}',
    );
  });
}
