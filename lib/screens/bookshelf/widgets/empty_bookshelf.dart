import 'package:flutter/material.dart';
import '../../../config/theme.dart';

class EmptyBookshelf extends StatelessWidget {
  final VoidCallback onImport;

  const EmptyBookshelf({super.key, required this.onImport});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Simple vector illustration using Flutter shapes
            _buildIllustration(palette),
            const SizedBox(height: 32),
            const Text(
              '书架空空如也',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '导入你的第一本电子书吧～',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('导入电子书'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIllustration(AppPalette palette) {
    return Container(
      width: 140,
      height: 180,
      decoration: BoxDecoration(
        color: palette.illustration.withAlpha(30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: palette.illustration.withAlpha(100),
          width: 2,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Book shape
          Container(
            width: 80,
            height: 110,
            decoration: BoxDecoration(
              color: palette.illustration.withAlpha(82),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: palette.primary, width: 1.5),
            ),
          ),
          // Book spine
          Positioned(
            left: 38,
            top: 35,
            child: Container(
              width: 3,
              height: 110,
              color: palette.primary.withAlpha(120),
            ),
          ),
          // Bookmark
          Positioned(
            right: 32,
            top: 28,
            child: CustomPaint(
              size: const Size(16, 28),
              painter: _BookmarkPainter(color: palette.primaryDark),
            ),
          ),
          // Magnifying glass
          Positioned(
            right: 20,
            bottom: 30,
            child: Icon(
              Icons.auto_awesome,
              size: 22,
              color: palette.icon.withAlpha(190),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookmarkPainter extends CustomPainter {
  final Color color;

  const _BookmarkPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height - 6)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BookmarkPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
