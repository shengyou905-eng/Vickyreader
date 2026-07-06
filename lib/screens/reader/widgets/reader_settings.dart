import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/reader_paging_mode.dart';
import '../../../config/theme.dart';
import '../../../providers/settings_provider.dart';

class ReaderSettings extends StatelessWidget {
  const ReaderSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '阅读设置',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 20), // 字号
              const Text('字号', style: TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('A', style: TextStyle(fontSize: 13)),
                  Expanded(
                    child: Slider(
                      value: settings.fontSize,
                      min: 12,
                      max: 28,
                      divisions: 16,
                      activeColor: AppTheme.primary,
                      onChanged: (v) => settings.setFontSize(v),
                    ),
                  ),
                  const Text('A', style: TextStyle(fontSize: 20)),
                ],
              ),
              const SizedBox(height: 12), // 行距
              const Text('行距', style: TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Slider(
                value: settings.lineHeight,
                min: 1.2,
                max: 2.4,
                divisions: 6,
                activeColor: AppTheme.primary,
                onChanged: (v) => settings.setLineHeight(v),
              ),
              const SizedBox(height: 16),
              const Text('翻页', style: TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              SegmentedButton<ReaderPagingMode>(
                segments: const [
                  ButtonSegment<ReaderPagingMode>(
                    value: ReaderPagingMode.vertical,
                    label: Text('上下滚动'),
                    icon: Icon(Icons.swap_vert, size: 18),
                  ),
                  ButtonSegment<ReaderPagingMode>(
                    value: ReaderPagingMode.horizontal,
                    label: Text('左右翻页'),
                    icon: Icon(Icons.swap_horiz, size: 18),
                  ),
                ],
                selected: {settings.readerPagingMode},
                onSelectionChanged: (next) {
                  if (next.isEmpty) return;
                  settings.setReaderPagingMode(next.first);
                },
              ),
              const SizedBox(height: 12), // 主题
              const Text('主题', style: TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _ThemeOption(
                    label: '白色',
                    color: Colors.white,
                    isSelected: settings.themeMode == 'light',
                    onTap: () => settings.setThemeMode('light'),
                  ),
                  const SizedBox(width: 12),
                  _ThemeOption(
                    label: '护眼',
                    color: const Color(0xFFF5ECD7),
                    isSelected: settings.themeMode == 'sepia',
                    onTap: () => settings.setThemeMode('sepia'),
                  ),
                  const SizedBox(width: 12),
                  _ThemeOption(
                    label: '绿意',
                    color: const Color(0xFFEAF4E3),
                    isSelected: settings.themeMode == 'green',
                    onTap: () => settings.setThemeMode('green'),
                  ),
                  const SizedBox(width: 12),
                  _ThemeOption(
                    label: '夜间',
                    color: const Color(0xFF1A1A1A),
                    isSelected: settings.themeMode == 'dark',
                    onTap: () => settings.setThemeMode('dark'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            ),
          ),
        );
      },
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(
                color: isSelected ? AppTheme.primary : AppTheme.dividerColor,
                width: isSelected ? 2.5 : 1,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppTheme.primary.withAlpha(40),
                        blurRadius: 8,
                      )
                    ]
                  : null,
            ),
            child: isSelected
                ? const Center(
                    child: Icon(Icons.check, color: AppTheme.primary),
                  )
                : null,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
