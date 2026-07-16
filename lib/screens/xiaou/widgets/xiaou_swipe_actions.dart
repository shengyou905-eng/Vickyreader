import 'package:flutter/material.dart';

import '../../../config/theme.dart';

class XiaouSwipeActions extends StatefulWidget {
  final Widget child;
  final bool isImportant;
  final VoidCallback? onToggleImportant;
  final VoidCallback? onDelete;

  const XiaouSwipeActions({
    super.key,
    required this.child,
    required this.isImportant,
    this.onToggleImportant,
    this.onDelete,
  });

  @override
  State<XiaouSwipeActions> createState() => _XiaouSwipeActionsState();
}

class _XiaouSwipeActionsState extends State<XiaouSwipeActions> {
  static const double _actionWidth = 72;
  static const double _openWidth = _actionWidth * 2;
  double _offset = 0;
  bool _dragging = false;

  void _close() {
    if (!mounted) return;
    setState(() {
      _dragging = false;
      _offset = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: _openWidth,
                  child: Row(
                    children: [
                      _ActionButton(
                        icon: widget.isImportant
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        label: widget.isImportant ? '取消重要' : '标记重要',
                        color: palette.primaryDark,
                        onTap: widget.onToggleImportant == null
                            ? null
                            : () {
                                _close();
                                widget.onToggleImportant!();
                              },
                      ),
                      _ActionButton(
                        icon: Icons.delete_outline_rounded,
                        label: '删除',
                        color: const Color(0xFFA75D65),
                        onTap: widget.onDelete == null
                            ? null
                            : () {
                                _close();
                                widget.onDelete!();
                              },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) {
                setState(() => _dragging = true);
              },
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _offset = (_offset + details.delta.dx).clamp(0, _openWidth);
                });
              },
              onHorizontalDragEnd: (_) {
                setState(() {
                  _dragging = false;
                  _offset = _offset >= _openWidth * 0.38 ? _openWidth : 0;
                });
              },
              child: AnimatedContainer(
                duration: _dragging
                    ? Duration.zero
                    : const Duration(milliseconds: 190),
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(_offset, 0, 0),
                child: widget.child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return SizedBox(
      width: _XiaouSwipeActionsState._actionWidth,
      child: Material(
        color: palette.surface.withAlpha(220),
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
