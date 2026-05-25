import 'dart:ui';

import 'package:flutter/material.dart';
import '../../../config/theme.dart';

class SelectionMenu extends StatelessWidget {
  final String selectedText;
  final VoidCallback onExplain;
  final Function(String color) onHighlight;
  final VoidCallback onNote;
  final VoidCallback onDismiss;

  const SelectionMenu({
    super.key,
    required this.selectedText,
    required this.onExplain,
    required this.onHighlight,
    required this.onNote,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(112),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withAlpha(145)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(16),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 7, 8, 0),
                  child: Row(
                    children: [
                      const Expanded(child: SizedBox.shrink()),
                      Container(
                        width: 34,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(125),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: InkWell(
                            onTap: onDismiss,
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: AppTheme.textSecondary.withAlpha(170),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(52),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.primaryLight.withAlpha(50)),
                    ),
                    child: Text(
                      selectedText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textPrimary,
                        fontStyle: FontStyle.italic,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 9),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ActionChip(
                        icon: Icons.auto_awesome,
                        label: '小U解释',
                        color: AppTheme.primaryDark,
                        onTap: onExplain,
                      ),
                      _ActionChip(
                        icon: Icons.format_quote,
                        label: '划线',
                        color: AppTheme.primary,
                        onTap: () => onHighlight('#B39DDB'),
                      ),
                      _ActionChip(
                        icon: Icons.edit_note,
                        label: '想法',
                        color: AppTheme.primaryLight,
                        onTap: onNote,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withAlpha(44),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withAlpha(105)),
                boxShadow: [
                  BoxShadow(
                    color: color.withAlpha(12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
