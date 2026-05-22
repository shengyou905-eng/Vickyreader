import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdfx/pdfx.dart';
import '../../../config/theme.dart';
import '../../../providers/reader_provider.dart';

/// PDF：根据 [scrollDirection] 纵向连续滚或横向逐页滑。
class PdfReaderWidget extends StatefulWidget {
  final Axis scrollDirection;

  const PdfReaderWidget({
    super.key,
    this.scrollDirection = Axis.vertical,
  });

  @override
  State<PdfReaderWidget> createState() => _PdfReaderWidgetState();
}

class _PdfReaderWidgetState extends State<PdfReaderWidget> {
  PdfController? _pdfController;
  int _currentPage = 1;
  int _totalPages = 1;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPdf();
  }

  Future<void> _initPdf() async {
    final reader = context.read<ReaderProvider>();
    final book = reader.book;
    if (book == null) return;

    final pdfPath = book.filePath;
    if (!File(pdfPath).existsSync()) {
      setState(() {
        _isLoading = false;
        _error = 'PDF 文件不存在';
      });
      return;
    }

    try {
      final documentFuture = PdfDocument.openFile(pdfPath);
      final doc = await documentFuture;
      final pagesCount = doc.pagesCount;
      final restoredPage = reader.scrollOffset > 0
          ? reader.scrollOffset.round().clamp(1, pagesCount).toInt()
          : 1;

      _pdfController = PdfController(
        document: documentFuture,
        initialPage: restoredPage,
      );

      setState(() {
        _totalPages = pagesCount;
        _currentPage = restoredPage;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'PDF 加载失败：$e';
      });
    }
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    if (_pdfController == null) {
      return const Center(
        child: Text('无法加载 PDF', style: TextStyle(color: AppTheme.textSecondary)),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
          child: Text(
            '$_currentPage / $_totalPages',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ),
        Expanded(
          child: PdfView(
            controller: _pdfController!,
            scrollDirection: widget.scrollDirection,
            onPageChanged: (page) {
              setState(() => _currentPage = page);
              context.read<ReaderProvider>().setScrollOffset(page.toDouble());
            },
          ),
        ),
      ],
    );
  }
}
