import 'package:path/path.dart' as p;
import '../models/book.dart';
import 'epub_service.dart';
import 'txt_service.dart';
import 'pdf_service.dart';

class ImportService {
  /// Detect format from extension and route to correct parser
  static Future<Book> importFile(String filePath) async {
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');

    switch (ext) {
      case 'epub':
        return EpubService.importEpub(filePath);
      case 'txt':
        return TxtService.importTxt(filePath);
      case 'pdf':
        return PdfService.importPdf(filePath);
      default:
        throw Exception('不支持的格式：.$ext。支持 EPUB、TXT、PDF');
    }
  }

  /// Check if a file extension is supported
  static bool isSupported(String filePath) {
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
    return ['epub', 'txt', 'pdf'].contains(ext);
  }

  /// Get format from file extension
  static String formatFromPath(String filePath) {
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
    if (['epub', 'txt', 'pdf'].contains(ext)) return ext;
    return ext;
  }
}
