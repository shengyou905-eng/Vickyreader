import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/book.dart';
import '../services/book_service.dart';
import '../services/import_service.dart';

class BookshelfProvider extends ChangeNotifier {
  List<Book> _books = [];
  bool _isLoading = false;
  String? _error;

  List<Book> get books => _books;
  bool get isLoading => _isLoading;
  bool get isEmpty => _books.isEmpty && !_isLoading;
  String? get error => _error;

  Future<void> loadBooks() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _books = await BookService.getBooks();
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<Book?> importFromFile(String filePath) async {
    _isLoading = true;
    notifyListeners();
    try {
      final book = await ImportService.importFile(filePath);
      await BookService.insertBook(book);
      _books.insert(0, book);
      _isLoading = false;
      notifyListeners();
      return book;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<Book?> importFromUrl(String url) async {
    _isLoading = true;
    notifyListeners();
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = url.split('/').last.split('?').first;
      if (!ImportService.isSupported(fileName)) {
        throw Exception('不支持的格式，仅支持 EPUB、TXT、PDF');
      }
      final filePath = p.join(dir.path, 'downloads');
      await Directory(filePath).create(recursive: true);
      final savePath = p.join(filePath, fileName);

      final response = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw Exception('下载失败：HTTP ${response.statusCode}');
      }
      await File(savePath).writeAsBytes(response.bodyBytes);

      final book = await ImportService.importFile(savePath);
      await BookService.insertBook(book);
      _books.insert(0, book);
      _isLoading = false;
      notifyListeners();
      return book;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<void> deleteBook(String id) async {
    await BookService.deleteBook(id);
    _books.removeWhere((b) => b.id == id);
    notifyListeners();
  }

  Future<void> updateBookProgress(String id, double progress) async {
    final idx = _books.indexWhere((b) => b.id == id);
    if (idx >= 0) {
      _books[idx].readingProgress = progress;
      _books[idx] = _books[idx].copyWith(lastOpenedAt: DateTime.now());
      await BookService.updateBook(_books[idx]);
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
