import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Shared low-contrast paper surface for reflective reading screens.
class AppPaperSurface extends StatelessWidget {
  final Widget child;

  const AppPaperSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final visuals = context.appVisuals;
    return ColoredBox(
      color: visuals.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _PaperTexturePainter(
                  color: visuals.inkMuted.withValues(
                    alpha: visuals.paperTextureOpacity,
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _PaperTexturePainter extends CustomPainter {
  final Color color;

  const _PaperTexturePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.55
      ..strokeCap = StrokeCap.round;

    for (double y = 10; y < size.height; y += 18) {
      final row = (y / 18).floor();
      final offset = row.isEven ? 7.0 : 17.0;
      for (double x = offset; x < size.width; x += 31) {
        final length = ((row + x.floor()) % 3) + 1.5;
        canvas.drawLine(Offset(x, y), Offset(x + length, y + 0.35), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PaperTexturePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
