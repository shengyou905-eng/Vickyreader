import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../config/theme.dart';

class SelectionMenu extends StatelessWidget {
  final VoidCallback onExplain;
  final Function(String color) onHighlight;
  final VoidCallback onNote;
  final VoidCallback onDismiss;

  const SelectionMenu({
    super.key,
    required this.onExplain,
    required this.onHighlight,
    required this.onNote,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final primary = Theme.of(context).colorScheme.primary;
    final glassColor = Color.alphaBlend(
      primary.withAlpha(14),
      Colors.white.withAlpha(174),
    );

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: primary.withAlpha(22),
              blurRadius: 26,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: glassColor,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withAlpha(190),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _CapsuleAction(
                      icon: Icons.auto_awesome_rounded,
                      label: '小U解读',
                      color: primary,
                      emphasized: true,
                      onTap: onExplain,
                    ),
                  ),
                  _GlassDivider(color: palette.divider),
                  Expanded(
                    child: _CapsuleAction(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: '写想法',
                      color: palette.icon,
                      onTap: onNote,
                    ),
                  ),
                  _GlassDivider(color: palette.divider),
                  _CapsuleIconAction(
                    tooltip: '保存划线',
                    icon: Icons.bookmark_border_rounded,
                    color: palette.icon,
                    onTap: () => onHighlight(_colorToHex(palette.primaryLight)),
                  ),
                  _CapsuleIconAction(
                    tooltip: '取消',
                    icon: Icons.close_rounded,
                    color: palette.textSecondary,
                    onTap: onDismiss,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CapsuleAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool emphasized;
  final VoidCallback onTap;

  const _CapsuleAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: emphasized ? color : palette.textPrimary,
                  fontSize: 13,
                  fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CapsuleIconAction extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CapsuleIconAction({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          width: 40,
          height: 56,
          child: Icon(icon, size: 17, color: color.withAlpha(190)),
        ),
      ),
    );
  }
}

class _GlassDivider extends StatelessWidget {
  final Color color;

  const _GlassDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(width: 0.5, height: 22, color: color.withAlpha(118));
  }
}

String _colorToHex(Color color) {
  return '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
