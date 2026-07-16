import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/reader_paging_mode.dart';
import '../../../config/reader_typography.dart';
import '../../../config/theme.dart';
import '../../../providers/settings_provider.dart';

class ReaderSettings extends StatelessWidget {
  final VoidCallback? onReaderStyleChanged;

  const ReaderSettings({super.key, this.onReaderStyleChanged});

  void _update(VoidCallback change) {
    change();
    onReaderStyleChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.84;
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              10,
              20,
              18 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.divider,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '阅读排版',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        settings.resetTypography();
                        onReaderStyleChanged?.call();
                      },
                      icon: const Icon(Icons.restart_alt_rounded, size: 17),
                      label: const Text('恢复默认'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: ReaderFontFamily.values
                      .map(
                        (font) => Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: font == ReaderFontFamily.wenkai ? 0 : 8,
                            ),
                            child: _FontCard(
                              font: font,
                              selected: settings.readerFontFamily == font,
                              onTap: () => _update(
                                () => settings.setReaderFontFamily(font),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 22),
                _SliderSetting(
                  label: '字号',
                  valueLabel: '${settings.fontSize.round()}',
                  value: settings.fontSize,
                  min: 12,
                  max: 28,
                  divisions: 16,
                  leading: const Text('A', style: TextStyle(fontSize: 13)),
                  trailing: const Text('A', style: TextStyle(fontSize: 21)),
                  onChanged: (value) =>
                      _update(() => settings.setFontSize(value)),
                ),
                const SizedBox(height: 14),
                _SliderSetting(
                  label: '行距',
                  valueLabel: settings.lineHeight.toStringAsFixed(1),
                  value: settings.lineHeight,
                  min: 1.2,
                  max: 2.4,
                  divisions: 12,
                  leading: const Icon(Icons.density_small_rounded, size: 17),
                  trailing: const Icon(Icons.density_large_rounded, size: 18),
                  onChanged: (value) =>
                      _update(() => settings.setLineHeight(value)),
                ),
                const SizedBox(height: 14),
                _SliderSetting(
                  label: '页边距',
                  valueLabel: '${settings.pageMargin.round()}',
                  value: settings.pageMargin,
                  min: 12,
                  max: 36,
                  divisions: 12,
                  leading: const Icon(Icons.unfold_less_rounded, size: 18),
                  trailing: const Icon(Icons.unfold_more_rounded, size: 18),
                  onChanged: (value) =>
                      _update(() => settings.setPageMargin(value)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Divider(height: 1, color: palette.divider),
                ),
                Text(
                  '翻页',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ReaderPagingMode>(
                    segments: const [
                      ButtonSegment<ReaderPagingMode>(
                        value: ReaderPagingMode.vertical,
                        label: Text('上下滚动'),
                        icon: Icon(Icons.swap_vert_rounded, size: 18),
                      ),
                      ButtonSegment<ReaderPagingMode>(
                        value: ReaderPagingMode.horizontal,
                        label: Text('左右翻页'),
                        icon: Icon(Icons.swap_horiz_rounded, size: 18),
                      ),
                    ],
                    selected: {settings.readerPagingMode},
                    onSelectionChanged: (next) {
                      if (next.isNotEmpty) {
                        settings.setReaderPagingMode(next.first);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '纸张',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _ThemeOption(
                      label: '白色',
                      color: const Color(0xFFFDFDFC),
                      selected: settings.themeMode == 'light',
                      onTap: () =>
                          _update(() => settings.setThemeMode('light')),
                    ),
                    _ThemeOption(
                      label: '米纸',
                      color: const Color(0xFFF5ECD7),
                      selected: settings.themeMode == 'sepia',
                      onTap: () =>
                          _update(() => settings.setThemeMode('sepia')),
                    ),
                    _ThemeOption(
                      label: '护眼',
                      color: const Color(0xFFEAF4E3),
                      selected: settings.themeMode == 'green',
                      onTap: () =>
                          _update(() => settings.setThemeMode('green')),
                    ),
                    _ThemeOption(
                      label: '夜间',
                      color: const Color(0xFF262626),
                      selected: settings.themeMode == 'dark',
                      onTap: () => _update(() => settings.setThemeMode('dark')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FontCard extends StatelessWidget {
  final ReaderFontFamily font;
  final bool selected;
  final VoidCallback onTap;

  const _FontCard({
    required this.font,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 112,
        padding: const EdgeInsets.fromLTRB(9, 13, 9, 10),
        decoration: BoxDecoration(
          color: selected ? palette.primaryLight : palette.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? palette.primary : palette.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Text(
                  '山川\n入卷',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 19,
                    height: 1.25,
                    fontFamily: font.previewFontFamily,
                    fontFamilyFallback: font.previewFontFallback,
                  ),
                ),
              ),
            ),
            Text(
              font.label,
              style: TextStyle(
                color: selected ? palette.primary : palette.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              font.description,
              maxLines: 1,
              style: TextStyle(color: palette.textSecondary, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Widget leading;
  final Widget trailing;
  final ValueChanged<double> onChanged;

  const _SliderSetting({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.leading,
    required this.trailing,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              valueLabel,
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            SizedBox(width: 24, child: Center(child: leading)),
            Expanded(
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                activeColor: palette.primary,
                inactiveColor: palette.divider,
                onChanged: onChanged,
              ),
            ),
            SizedBox(width: 24, child: Center(child: trailing)),
          ],
        ),
      ],
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 42,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? palette.primary : palette.divider,
                  width: selected ? 2 : 1,
                ),
              ),
              child: selected
                  ? Icon(Icons.check_rounded, color: palette.primary, size: 19)
                  : null,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: selected ? palette.primary : palette.textSecondary,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
