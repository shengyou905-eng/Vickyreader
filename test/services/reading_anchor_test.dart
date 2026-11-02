import 'package:ai_reader/services/reading_anchor.dart';
import 'package:ai_reader/services/epub_service.dart';
import 'package:ai_reader/models/highlight.dart';
import 'package:ai_reader/screens/reader/widgets/reader_document_html.dart';
import 'package:html/parser.dart' as html;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'duplicate phrases require a valid offset or unique neighboring evidence',
    () {
      const text = 'first same text. second same text.';
      final second = text.lastIndexOf('same');
      expect(ReadingAnchor.resolve(text, 'same'), isNull);
      expect(
        ReadingAnchor.resolve(
          text,
          'same',
          startOffset: second,
          endOffset: second + 4,
        )?.start,
        second,
      );
      expect(
        ReadingAnchor.resolve(text, 'same', before: 'second ')?.start,
        second,
      );
      expect(ReadingAnchor.resolve(text, 'missing'), isNull);
      expect(ReadingAnchor.resolve(text, ''), isNull);
    },
  );

  test('real selection context wins over the first duplicate paragraph', () {
    const content = '<p>FIRST same ending.</p><p>SECOND same ending.</p>';
    final ambiguous = EpubService.getReadingContext(content, 'same');
    expect(ambiguous.before, '');
    expect(ambiguous.paragraph, '');
    final located = EpubService.getReadingContext(
      content,
      'same',
      selectionAnchor: {
        'selectedText': 'same',
        'paragraphText': 'SECOND same ending.',
        'contextBefore': 'SECOND ',
        'contextAfter': ' ending.',
      },
    );
    expect(located.paragraph, 'SECOND same ending.');
    expect(located.before, 'SECOND ');
    expect(
      EpubService.getReadingContext('<p>unique text</p>', 'unique').paragraph,
      'unique text',
    );
  });

  test(
    'stored spine source index resolves after filtered navigation; legacy fallback remains',
    () {
      final chapters = [
        EpubChapter(title: 'A', content: '', index: 0, sourceIndex: 1),
        EpubChapter(title: 'B', content: '', index: 1, sourceIndex: 3),
      ];
      expect(EpubService.chapterListIndex(chapters, '3'), 1);
      expect(EpubService.chapterListIndex(chapters, '1'), 0);
      expect(EpubService.chapterListIndex(chapters, '0'), 0);
      expect(EpubService.chapterListIndex(chapters, '99'), -1);
    },
  );

  test(
    'highlight restoration marks only chosen occurrence, preserving nested HTML',
    () {
      const content = '<p>same text</p><p>same <em>text</em></p>';
      final markup = ReaderDocumentHtml.prepareChapter(
        title: 'Title',
        content: content,
        highlights: [
          Highlight(
            id: 'h',
            bookId: 'b',
            chapterIndex: '1',
            selectedText: 'same text',
            contextBefore: '',
            contextAfter: '',
            startOffset: 9,
            endOffset: 18,
            createdAt: DateTime(2026),
          ),
        ],
      );
      final doc = html.parseFragment(markup.bodyHtml);
      final paragraphs = doc.querySelectorAll('p');
      expect(paragraphs.first.querySelector('.ai-reader-highlight'), isNull);
      expect(
        paragraphs.last
            .querySelectorAll('.ai-reader-highlight')
            .map((n) => n.text)
            .join(),
        'same text',
      );
      expect(paragraphs.last.querySelector('em')?.text, 'text');
    },
  );
}
