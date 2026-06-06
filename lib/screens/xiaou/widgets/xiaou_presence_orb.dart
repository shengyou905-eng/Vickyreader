import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

class XiaouPresenceOrb extends StatefulWidget {
  final bool isThinking;
  final int pulseKey;
  final VoidCallback onTap;

  const XiaouPresenceOrb({
    super.key,
    required this.isThinking,
    required this.pulseKey,
    required this.onTap,
  });

  @override
  State<XiaouPresenceOrb> createState() => _XiaouPresenceOrbState();
}

class _XiaouPresenceOrbState extends State<XiaouPresenceOrb>
    with TickerProviderStateMixin {
  late final AnimationController _breathController;
  late final AnimationController _pulseController;
  late final AnimationController _dwellController;
  Timer? _dwellTimer;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    _dwellController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _dwellTimer = Timer(const Duration(seconds: 7), () {
      if (mounted) _dwellController.forward();
    });
  }

  @override
  void didUpdateWidget(covariant XiaouPresenceOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isThinking != oldWidget.isThinking) {
      _breathController.duration = widget.isThinking
          ? const Duration(milliseconds: 5500)
          : const Duration(milliseconds: 4000);
      _breathController.repeat();
    }
    if (widget.pulseKey != oldWidget.pulseKey) {
      _pulseController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '意识入口',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _breathController,
            _pulseController,
            _dwellController,
          ]),
          builder: (context, child) {
            final breath = _breathValue(_breathController.value);
            final dwell = Curves.easeOut.transform(_dwellController.value);
            final pulse =
                math.sin(_pulseController.value * math.pi) *
                (1 - _pulseController.value) *
                0.07;
            final thinking = widget.isThinking ? 1.0 : 0.0;
            final scale = 1 + breath * (0.04 + thinking * 0.012) + pulse;
            final opacity =
                0.58 + breath * 0.16 + dwell * 0.08 + thinking * 0.14;
            final blue = const Color(0xFFAEDFFF);
            final babyBlue = const Color(0xFF62BFEA);
            final lavender = const Color(0xFFD9C2FF);
            final pink = const Color(0xFFF8C3E0);

            return Opacity(
              opacity: opacity.clamp(0.0, 0.9).toDouble(),
              child: Transform.scale(
                scale: scale,
                child: SizedBox(
                  width: 132,
                  height: 132,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _DiffuseGlow(
                        size: 132 + breath * 18 + pulse * 28,
                        color: blue,
                        alpha: (112 + breath * 30 + dwell * 18 + thinking * 34)
                            .round(),
                        blur: 34,
                        offset: const Offset(-8, -9),
                      ),
                      _DiffuseGlow(
                        size: 112 + breath * 16 + pulse * 24,
                        color: lavender,
                        alpha: (78 + breath * 22 + dwell * 14 + thinking * 26)
                            .round(),
                        blur: 31,
                        offset: const Offset(9, 5),
                      ),
                      _DiffuseGlow(
                        size: 88 + breath * 12 + pulse * 18,
                        color: pink,
                        alpha: (58 + breath * 18 + dwell * 12 + thinking * 20)
                            .round(),
                        blur: 30,
                        offset: const Offset(14, 13),
                      ),
                      _DiffuseGlow(
                        size: 52 + breath * 7 + pulse * 12,
                        color: Colors.white,
                        alpha: (96 + breath * 24 + thinking * 30).round(),
                        blur: 16,
                        offset: const Offset(-7, -10),
                      ),
                      _DiffuseGlow(
                        size: 70 + breath * 10 + pulse * 18,
                        color: babyBlue,
                        alpha: (86 + breath * 24 + dwell * 14 + thinking * 28)
                            .round(),
                        blur: 24,
                        offset: const Offset(-2, 2),
                      ),
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: ClipOval(
                          child: Container(
                            width: 50 + breath * 2 + thinking * 3,
                            height: 50 + breath * 2 + thinking * 3,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                center: const Alignment(-0.35, -0.45),
                                radius: 0.96,
                                colors: [
                                  Colors.white.withAlpha(
                                    (150 + breath * 18 + thinking * 24).round(),
                                  ),
                                  blue.withAlpha(
                                    (136 +
                                            breath * 24 +
                                            thinking * 34 +
                                            dwell * 12)
                                        .round(),
                                  ),
                                  lavender.withAlpha(
                                    (94 +
                                            breath * 18 +
                                            thinking * 24 +
                                            dwell * 8)
                                        .round(),
                                  ),
                                  pink.withAlpha(
                                    (74 +
                                            breath * 14 +
                                            thinking * 18 +
                                            dwell * 6)
                                        .round(),
                                  ),
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.32, 0.6, 0.82, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _dwellTimer?.cancel();
    _breathController.dispose();
    _pulseController.dispose();
    _dwellController.dispose();
    super.dispose();
  }

  double _breathValue(double value) {
    if (value < 0.38) {
      return Curves.easeOutCubic.transform(value / 0.38);
    }
    if (value < 0.52) return 1.0;
    if (value < 0.9) {
      return 1 - Curves.easeInOutCubic.transform((value - 0.52) / 0.38);
    }
    return 0.0;
  }
}

class _DiffuseGlow extends StatelessWidget {
  final double size;
  final Color color;
  final int alpha;
  final double blur;
  final Offset offset;

  const _DiffuseGlow({
    required this.size,
    required this.color,
    required this.alpha,
    required this.blur,
    required this.offset,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: offset,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withAlpha(alpha.clamp(0, 255).toInt()),
                color.withAlpha(
                  (alpha * 0.38).round().clamp(0, 255).toInt(),
                ),
                Colors.transparent,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
