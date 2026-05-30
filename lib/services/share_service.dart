import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config/theme.dart';

class ShareService {
  static Future<void> shareText(BuildContext context, String text) {
    return Share.share(text, sharePositionOrigin: _shareOrigin(context));
  }

  static Future<void> shareCard(
    BuildContext context, {
    required Widget card,
    required String fileName,
    String? text,
  }) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    final boundaryKey = GlobalKey();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -1200,
        top: 0,
        child: Material(
          type: MaterialType.transparency,
          child: RepaintBoundary(
            key: boundaryKey,
            child: SizedBox(width: 360, child: card),
          ),
        ),
      ),
    );
    overlay.insert(entry);

    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('分享卡片生成失败，请稍后重试');
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw Exception('分享卡片生成失败，请稍后重试');
      }
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, '$fileName.png'));
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: text,
        sharePositionOrigin: _shareOrigin(context),
      );
    } finally {
      entry.remove();
    }
  }

  static Rect _shareOrigin(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return const Rect.fromLTWH(0, 0, 1, 1);
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }
}

class ZhiDuShareCard extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String body;
  final String date;
  final String? quote;

  const ZhiDuShareCard({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.date,
    this.quote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
      decoration: const BoxDecoration(
        color: Color(0xFFFAF8FD),
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            eyebrow,
            style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 21,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (quote?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0EBF8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                quote!.trim(),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  height: 1.7,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          const Divider(height: 1, color: Color(0xFFE6DFEE)),
          const SizedBox(height: 18),
          Text(
            body,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              height: 1.8,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: Text(
                  date,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              const Text(
                '知读',
                style: TextStyle(
                  color: AppTheme.primaryDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
