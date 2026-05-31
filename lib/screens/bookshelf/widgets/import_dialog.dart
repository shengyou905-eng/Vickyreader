import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../config/theme.dart';

class ImportDialog extends StatelessWidget {
  const ImportDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '导入电子书',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '支持 EPUB · TXT · PDF',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          _ImportOption(
            icon: Icons.folder_open_rounded,
            title: '从本地文件导入',
            subtitle: '选择 EPUB、TXT 或 PDF 文件',
            onTap: () => _pickLocalFile(context),
          ),
          const SizedBox(height: 12),
          _ImportOption(
            icon: Icons.link_rounded,
            title: '从链接下载',
            subtitle: '输入 EPUB 下载地址',
            onTap: () => _importFromUrl(context),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _pickLocalFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub', 'txt', 'pdf'],
    );
    if (result != null && result.files.single.path != null) {
      if (context.mounted) {
        Navigator.of(context).pop(result.files.single.path);
      }
    }
  }

  Future<void> _importFromUrl(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从链接下载'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '请输入 EPUB / TXT / PDF 文件的下载链接',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                Navigator.pop(ctx, url);
              }
            },
            child: const Text('下载'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null && result.isNotEmpty && context.mounted) {
      Navigator.pop(context, {'url': result});
    }
  }
}

class _ImportOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ImportOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: palette.divider),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: palette.primaryLight.withAlpha(74),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: palette.icon, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: palette.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
