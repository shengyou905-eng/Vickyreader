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
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Selected text preview
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  selectedText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ActionChip(
                    icon: Icons.auto_awesome,
                    label: 'AI 解释',
                    color: AppTheme.primaryDark,
                    onTap: onExplain,
                  ),
                  _ActionChip(
                    icon: Icons.format_quote,
                    label: '划线',
                    color: AppTheme.primaryLight,
                    onTap: () => onHighlight('#B39DDB'),
                  ),
                  _ActionChip(
                    icon: Icons.edit_note,
                    label: '想法',
                    color: Colors.orange.shade300,
                    onTap: onNote,
                  ),
                  _ActionChip(
                    icon: Icons.close,
                    label: '取消',
                    color: AppTheme.textSecondary,
                    onTap: onDismiss,
                  ),
                ],
              ),
            ),
          ],
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
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
