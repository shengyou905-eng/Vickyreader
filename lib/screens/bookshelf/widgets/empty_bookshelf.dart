import 'package:flutter/material.dart';
import '../../../config/theme.dart';

class EmptyBookshelf extends StatelessWidget {
  final VoidCallback onImport;

  const EmptyBookshelf({super.key, required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Simple vector illustration using Flutter shapes
            _buildIllustration(),
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
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
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

  Widget _buildIllustration() {
    return Container(
      width: 140,
      height: 180,
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withAlpha(30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryLight.withAlpha(80),
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
              color: AppTheme.primaryLight.withAlpha(60),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppTheme.primary, width: 1.5),
            ),
          ),
          // Book spine
          Positioned(
            left: 38,
            top: 35,
            child: Container(
              width: 3,
              height: 110,
              color: AppTheme.primary.withAlpha(120),
            ),
          ),
          // Bookmark
          Positioned(
            right: 32,
            top: 28,
            child: CustomPaint(
              size: const Size(16, 28),
              painter: _BookmarkPainter(),
            ),
          ),
          // Magnifying glass
          Positioned(
            right: 20,
            bottom: 30,
            child: Icon(
              Icons.auto_awesome,
              size: 22,
              color: AppTheme.primaryDark.withAlpha(180),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookmarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.primaryDark
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
