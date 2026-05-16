import 'dart:io';
import 'dart:convert';
import 'package:charset/charset.dart' show gbk;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import '../config/constants.dart';
import '../models/book.dart';

class TxtChapter {
  final String title;
  final String content; // HTML
  final int index;

  TxtChapter({required this.title, required this.content, required this.index});
}

class TxtService {
  static Future<Book> importTxt(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final text = _decodeWithDetection(bytes);

    // Derive title from filename
    final fileName = p.basenameWithoutExtension(filePath);
    final title = fileName.isNotEmpty ? fileName : '未命名文档';

    // Split into chapters
    final chapters = _splitChapters(text);

    // Save chapters
    final appDir = await getApplicationDocumentsDirectory();
    final bookDir = p.join(appDir.path, AppConstants.booksDir);
    await Directory(bookDir).create(recursive: true);
    final bookId = const Uuid().v4();
    final chapterDir = p.join(bookDir, bookId);
    await Directory(chapterDir).create();

    for (final ch in chapters) {
      final html = _buildChapterHtml(ch.title, ch.content);
      await File(p.join(chapterDir, 'ch_${ch.index}.html'))
          .writeAsString(html);
    }

    final titlesJson = chapters.map((c) => c.title).toList();
    await File(p.join(chapterDir, 'titles.json'))
        .writeAsString(jsonEncode(titlesJson));

    return Book(
      id: bookId,
      title: title,
      author: '未知作者',
      filePath: filePath,
      format: 'txt',
      addedAt: DateTime.now(),
      lastOpenedAt: DateTime.now(),
      chapterTitles: chapters.map((c) => c.title).toList(),
    );
  }

  /// Detect encoding and decode: UTF-8 → GBK → Latin-1
  static String _decodeWithDetection(List<int> bytes) {
    // Try UTF-8
    try {
      return utf8.decode(bytes);
    } catch (_) {}

    // Try UTF-8 with replacement (lossy)
    try {
      final result = utf8.decode(bytes, allowMalformed: true);
      final replacementCount = '�'.allMatches(result).length;
      if (replacementCount < result.length * 0.05) {
        return result;
      }
    } catch (_) {}

    // Try GBK
    try {
      return gbk.decode(bytes);
    } catch (_) {}

    // Fallback to Latin-1 (preserves all bytes)
    return latin1.decode(bytes);
  }

  /// Split text into chapters using regex patterns
  static List<TxtChapter> _splitChapters(String text) {
    // Chapter heading patterns
    final patterns = [
      // Chinese numbered chapters
      RegExp(r'(第[零一二三四五六七八九十百千\d]+[章节回卷])'),
      // Chinese numbered sections
      RegExp(r'(第[零一二三四五六七八九十百千\d]+[部节])'),
      // Arabic numbered chapters
      RegExp(r'(第\d+[章节回卷部])'),
      // English chapters
      RegExp(r'(Chapter \d+)', caseSensitive: false),
      RegExp(r'(Part \d+)', caseSensitive: false),
      // Numeric headings
      RegExp(r'(^\d+[\.\、]\s*)', multiLine: true),
      // Text markers
      RegExp(r'(序[言章]|前言|楔子|尾声|后记|附录|番外)'),
    ];

    // Find all chapter markers
    final markers = <int, String>{};
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(text)) {
        final idx = match.start;
        // Only add if not too close to an existing marker
        final tooClose = markers.keys.any((m) => (m - idx).abs() < 10);
        if (!tooClose) {
          markers[idx] = match.group(1)!;
        }
      }
    }

    if (markers.isEmpty) {
      // No chapters found — split by 5000 chars
      return _splitByLength(text, 5000);
    }

    // Sort by position
    final sorted = markers.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final chapters = <TxtChapter>[];
    int chIndex = 0;

    // Text before first marker (if substantial)
    if (sorted.first.key > 200) {
      final before = text.substring(0, sorted.first.key).trim();
      if (before.isNotEmpty) {
        chapters.add(TxtChapter(
            title: '前言', content: before, index: chIndex++));
      }
    }

    // Chapters
    for (int i = 0; i < sorted.length; i++) {
      final start = sorted[i].key;
      final title = sorted[i].value;
      final end = i + 1 < sorted.length ? sorted[i + 1].key : text.length;
      final content = text.substring(start, end).trim();
      if (content.isNotEmpty) {
        chapters.add(TxtChapter(title: title, content: content, index: chIndex++));
      }
    }

    return chapters;
  }

  /// Split text into chunks of maxLength chars
  static List<TxtChapter> _splitByLength(String text, int maxLength) {
    final chapters = <TxtChapter>[];
    int start = 0;
    int idx = 0;
    while (start < text.length) {
      int end = (start + maxLength).clamp(0, text.length);
      // Try to break at paragraph boundary
      if (end < text.length) {
        final paraBreak = text.lastIndexOf('\n\n', end);
        if (paraBreak > start + maxLength * 0.5) {
          end = paraBreak;
        }
      }
      chapters.add(TxtChapter(
        title: '第${idx + 1}部分',
        content: text.substring(start, end).trim(),
        index: idx,
      ));
      start = end;
      idx++;
    }
    return chapters;
  }

  static String _buildChapterHtml(String title, String content) {
    final escaped = _escapeHtml(content);
    final paragraphs = escaped
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => '<p>$line</p>')
        .join('\n');

    return '''<!DOCTYPE html>
<html><head><meta charset="utf-8"></head><body>
<h1 class="chapter-title">${_escapeHtml(title)}</h1>
$paragraphs
</body></html>''';
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}
