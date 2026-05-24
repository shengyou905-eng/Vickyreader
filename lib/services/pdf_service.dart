import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import '../config/constants.dart';
import '../models/book.dart';

class PdfService {
  /// Import a PDF file: copy to app storage, save metadata.
  /// Rendering is handled by pdfx in PdfReaderWidget.
  static Future<Book> importPdf(
    String filePath, {
    String? bookId,
    String? title,
    String? author,
  }) async {
    final fileName = p.basenameWithoutExtension(filePath);
    final bookTitle = (title ?? '').trim().isNotEmpty
        ? title!.trim()
        : (fileName.isNotEmpty ? fileName : '未命名文档');
    final bookAuthor = (author ?? '').trim().isNotEmpty ? author!.trim() : '佚名';

    final appDir = await getApplicationDocumentsDirectory();
    final bookDir = p.join(appDir.path, AppConstants.booksDir);
    await Directory(bookDir).create(recursive: true);
    final resolvedBookId = bookId ?? const Uuid().v4();
    final chapterDir = p.join(bookDir, resolvedBookId);
    await Directory(chapterDir).create(recursive: true);

    // Copy original PDF to book directory for rendering
    final pdfCopyPath = p.join(chapterDir, 'original.pdf');
    await File(filePath).copy(pdfCopyPath);

    // Save minimal metadata
    await File(p.join(chapterDir, 'pdf_meta.json')).writeAsString(jsonEncode({
      'totalPages': 1, // Will be determined at render time by pdfx
    }));

    return Book(
      id: resolvedBookId,
      title: bookTitle,
      author: bookAuthor,
      filePath: pdfCopyPath,
      format: 'pdf',
      addedAt: DateTime.now(),
      lastOpenedAt: DateTime.now(),
      chapterTitles: const ['PDF 文档'],
    );
  }

  /// Get the PDF file path for a book
  static Future<String> getPdfPath(String bookId) async {
    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, AppConstants.booksDir, bookId, 'original.pdf');
  }

  /// Get PDF metadata
  static Future<Map<String, dynamic>> getPdfMeta(String bookId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final metaFile = File(p.join(
        appDir.path, AppConstants.booksDir, bookId, 'pdf_meta.json'));
    if (await metaFile.exists()) {
      return jsonDecode(await metaFile.readAsString());
    }
    return {};
  }
}
