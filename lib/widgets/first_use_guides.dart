import 'dart:async';

import 'package:flutter/material.dart';

import '../config/theme.dart';

class ReaderLongPressGuide extends StatefulWidget {
  final VoidCallback onTry;
  final VoidCallback onDismiss;

  const ReaderLongPressGuide({
    super.key,
    required this.onTry,
    required this.onDismiss,
  });

  @override
  State<ReaderLongPressGuide> createState() => _ReaderLongPressGuideState();
}

class _ReaderLongPressGuideState extends State<ReaderLongPressGuide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.06)),
        ),
        IgnorePointer(
          child: Align(
            alignment: const Alignment(0, -0.18),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final progress = Curves.easeInOut.transform(_controller.value);
                return SizedBox(
                  width: 260,
                  height: 58,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 248,
                        height: 30,
                        decoration: BoxDecoration(
                          color: palette.primaryLight.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      Positioned(
                        right: 30,
                        top: 20 + progress * 5,
                        child: Icon(
                          Icons.touch_app_outlined,
                          size: 30,
                          color: palette.primaryDark.withValues(alpha: 0.78),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            minimum: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            child: Material(
              color: palette.surface.withValues(alpha: 0.97),
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '长按任意文字',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '可以提问、解读、划线，或记下想法。',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: widget.onDismiss,
                          child: const Text('我知道了'),
                        ),
                        const SizedBox(width: 4),
                        FilledButton.tonal(
                          onPressed: widget.onTry,
                          child: const Text('试一下'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ReaderSelectionGuideTip extends StatelessWidget {
  const ReaderSelectionGuideTip({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return IgnorePointer(
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(28, 0, 28, 82),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: palette.surface.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: palette.primaryLight.withValues(alpha: 0.45),
              ),
            ),
            child: Text(
              '在这里向小U提问，或查看解读。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class XiaouPresenceGuide extends StatelessWidget {
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  const XiaouPresenceGuide({
    super.key,
    required this.onOpen,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDismiss,
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.12)),
        ),
        Positioned(
          right: 24,
          bottom: 208 + MediaQuery.viewPaddingOf(context).bottom,
          child: Material(
            color: palette.surface.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 286),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '这是小U。',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '有疑问、想继续追问，或回望阅读痕迹时，点亮它。',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: onOpen,
                        child: const Text('点一下看看'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class MingtaiIntroductionGuide extends StatelessWidget {
  final VoidCallback onBrowse;
  final VoidCallback onLearnSharing;
  final VoidCallback onDismiss;

  const MingtaiIntroductionGuide({
    super.key,
    required this.onBrowse,
    required this.onLearnSharing,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 8, 18, 10),
      padding: const EdgeInsets.fromLTRB(18, 15, 10, 10),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.divider.withValues(alpha: 0.72)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '欢迎来到明台',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭引导',
                onPressed: onDismiss,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '在这里，你可以阅读大家公开分享的阅读片段、想法和书评，也可以分享自己的阅读痕迹，与其他读者讨论。',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(height: 9),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '你的内容默认保持私人，只有主动确认后才会公开。',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onBrowse, child: const Text('逛逛明台')),
              TextButton(
                onPressed: onLearnSharing,
                child: const Text('看看如何分享'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> showMingtaiSharingGuide(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final palette = sheetContext.appPalette;
      return SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '分享由你决定',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                '在阅读页选中文字，写下想法后选择“分享到明台”；也可以从明台右下角留下一段阅读。每次发布前都会让你确认，私人记录不会自动公开。',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                  height: 1.65,
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('知道了'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
