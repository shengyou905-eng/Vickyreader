import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/book.dart';
import '../../providers/reader_provider.dart';
import '../../services/book_service.dart';
import '../../services/share_service.dart';
import '../reader/reader_screen.dart';

class ThoughtDetailScreen extends StatefulWidget {
  final Map<String, dynamic> note;

  const ThoughtDetailScreen({super.key, required this.note});

  @override
  State<ThoughtDetailScreen> createState() => _ThoughtDetailScreenState();
}

class _ThoughtDetailScreenState extends State<ThoughtDetailScreen> {
  Book? _book;

  String get _content => widget.note['content']?.toString() ?? '';
  String get _originalText => widget.note['selectedText']?.toString() ?? '';
  String get _bookTitle =>
      _book?.title.trim().isNotEmpty == true ? _book!.title.trim() : '未命名书籍';
  String get _date => _formatDate(
    widget.note['updatedAt']?.toString() ??
        widget.note['createdAt']?.toString() ??
        '',
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loadBook());
  }

  Future<void> _loadBook() async {
    final book = await BookService.getBook(widget.note['bookId'] as String);
    if (mounted) setState(() => _book = book);
  }

  Future<void> _openOriginal() async {
    final book =
        _book ??
        await BookService.getBook(widget.note['bookId']?.toString() ?? '');
    if (book == null || !mounted) return;
    final reader = context.read<ReaderProvider>();
    await reader.openBook(book);
    reader.goToChapter(
      int.tryParse(widget.note['chapterIndex']?.toString() ?? '0') ?? 0,
    );
    if (_originalText.isNotEmpty) reader.setScrollTarget(_originalText);
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ReaderScreen()));
  }

  String _shareText() {
    final buffer = StringBuffer('《$_bookTitle》\n');
    if (_originalText.isNotEmpty) {
      buffer.write('\n$_originalText\n');
    }
    buffer.write('\n────────\n\n我的想法\n\n$_content\n\n知读');
    return buffer.toString();
  }

  Future<void> _shareImage() async {
    await ShareService.shareCard(
      context,
      fileName: 'zhidu_thought_${DateTime.now().millisecondsSinceEpoch}',
      text: _shareText(),
      card: ZhiDuShareCard(
        eyebrow: '阅读回应',
        title: '《$_bookTitle》',
        quote: _originalText,
        body: _content,
        date: _date,
      ),
    );
  }

  Future<void> _onMenuSelected(String action) async {
    try {
      if (action == 'share_text') {
        await ShareService.shareText(context, _shareText());
      } else if (action == 'share_image') {
        await _shareImage();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('分享失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读回应'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '导出',
            onSelected: _onMenuSelected,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'share_text', child: Text('分享文本')),
              PopupMenuItem(value: 'share_image', child: Text('分享图片')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
        children: [
          Text(
            '《$_bookTitle》',
            style: const TextStyle(
              color: AppTheme.primaryDark,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _date,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          if (_originalText.isNotEmpty) ...[
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
              decoration: BoxDecoration(
                color: const Color(0xFFF0ECF7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _originalText,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 15,
                  height: 1.7,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            '我的想法',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _content,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 17,
              height: 1.85,
            ),
          ),
          const SizedBox(height: 30),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _openOriginal,
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: const Text('回到原文'),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(String value) {
  final time = DateTime.tryParse(value)?.toLocal();
  if (time == null) return '';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${time.year}年${two(time.month)}月${two(time.day)}日';
}
