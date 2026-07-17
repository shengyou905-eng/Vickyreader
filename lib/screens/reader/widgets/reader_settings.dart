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
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
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
              20 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.divider,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '阅读排版',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await settings.resetReaderSettings();
                        onReaderStyleChanged?.call();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: palette.textSecondary,
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          fontFamilyFallback: ['SourceHanSerifCN'],
                        ),
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('恢复默认'),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const _SectionTitle('阅读效果'),
                const SizedBox(height: 10),
                _ReadingPreview(settings: settings),
                const SizedBox(height: 24),
                const _SectionTitle('字体'),
                const SizedBox(height: 10),
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
                const SizedBox(height: 24),
                const _SectionTitle('排版'),
                const SizedBox(height: 10),
                _SliderSetting(
                  label: '字号',
                  valueLabel: '${settings.fontSize.round()}',
                  value: settings.fontSize,
                  min: 12,
                  max: 28,
                  divisions: 16,
                  onChanged: (value) =>
                      _update(() => settings.setFontSize(value)),
                ),
                const SizedBox(height: 16),
                _SliderSetting(
                  label: '行距',
                  valueLabel: settings.lineHeight.toStringAsFixed(1),
                  value: settings.lineHeight,
                  min: 1.2,
                  max: 2.4,
                  divisions: 12,
                  onChanged: (value) =>
                      _update(() => settings.setLineHeight(value)),
                ),
                const SizedBox(height: 16),
                _SliderSetting(
                  label: '页边距',
                  valueLabel: '${settings.pageMargin.round()}',
                  value: settings.pageMargin,
                  min: 12,
                  max: 36,
                  divisions: 12,
                  onChanged: (value) =>
                      _update(() => settings.setPageMargin(value)),
                ),
                const SizedBox(height: 24),
                const _SectionTitle('翻页方式'),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ReaderPagingMode>(
                    segments: const [
                      ButtonSegment<ReaderPagingMode>(
                        value: ReaderPagingMode.vertical,
                        label: Text('上下滚动'),
                        icon: Icon(Icons.swap_vert_rounded, size: 16),
                      ),
                      ButtonSegment<ReaderPagingMode>(
                        value: ReaderPagingMode.horizontal,
                        label: Text('左右翻页'),
                        icon: Icon(Icons.swap_horiz_rounded, size: 16),
                      ),
                    ],
                    selected: {settings.readerPagingMode},
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 10),
                      ),
                      textStyle: const WidgetStatePropertyAll(
                        TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          fontFamilyFallback: ['SourceHanSerifCN'],
                        ),
                      ),
                      side: WidgetStateProperty.resolveWith(
                        (states) => BorderSide(
                          color: states.contains(WidgetState.selected)
                              ? palette.primary
                              : palette.divider,
                        ),
                      ),
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? palette.primary.withValues(alpha: 0.08)
                            : palette.surface,
                      ),
                      foregroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? palette.primary
                            : palette.textSecondary,
                      ),
                    ),
                    onSelectionChanged: (next) {
                      if (next.isNotEmpty) {
                        settings.setReaderPagingMode(next.first);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 24),
                const _SectionTitle('纸张背景'),
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

class _SectionTitle extends StatelessWidget {
  final String label;

  const _SectionTitle(this.label);

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Text(
      label,
      style: TextStyle(
        color: palette.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ReadingPreview extends StatelessWidget {
  static const _sample = '山川入卷，灯火落在书页之间。阅读让遥远的思想，在此刻重新发生。';

  final SettingsProvider settings;

  const _ReadingPreview({required this.settings});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final horizontalPadding =
        (20 +
                (settings.pageMargin - ReaderTypographyDefaults.pageMargin) *
                    0.45)
            .clamp(14.0, 28.0)
            .toDouble();
    final borderColor = settings.themeMode == 'dark'
        ? Colors.white.withValues(alpha: 0.14)
        : palette.divider.withValues(alpha: 0.85);
    return AnimatedContainer(
      key: const ValueKey('reader-settings-preview-card'),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 20,
      ),
      decoration: BoxDecoration(
        color: settings.backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        _sample,
        key: const ValueKey('reader-settings-preview-text'),
        style: TextStyle(
          color: settings.textColor,
          fontSize: settings.fontSize,
          height: settings.lineHeight,
          fontFamily: settings.readerFontFamily.previewFontFamily,
          fontFamilyFallback: settings.readerFontFamily.previewFontFallback,
        ),
      ),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('reader-font-${font.storageValue}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 82,
          padding: const EdgeInsets.fromLTRB(11, 10, 9, 10),
          decoration: BoxDecoration(
            color: selected
                ? palette.primary.withValues(alpha: 0.07)
                : palette.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? palette.primary : palette.divider,
              width: selected ? 1.25 : 1,
            ),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    font.label,
                    style: TextStyle(
                      color: selected ? palette.primary : palette.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '山川入卷',
                      maxLines: 1,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 17,
                        height: 1.1,
                        fontFamily: font.previewFontFamily,
                        fontFamilyFallback: font.previewFontFallback,
                      ),
                    ),
                  ),
                ],
              ),
              if (selected)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 15,
                    color: palette.primary,
                  ),
                ),
            ],
          ),
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
  final ValueChanged<double> onChanged;

  const _SliderSetting({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
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
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 38),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: palette.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: palette.divider.withValues(alpha: 0.7),
                ),
              ),
              child: Text(
                valueLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            activeTrackColor: palette.primary,
            inactiveTrackColor: palette.divider,
            thumbColor: palette.primary,
            overlayColor: palette.primary.withValues(alpha: 0.08),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
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
    final checkColor = color.computeLuminance() < 0.35
        ? Colors.white
        : palette.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? palette.primary : palette.divider,
                  width: selected ? 2 : 1,
                ),
              ),
              child: selected
                  ? Icon(Icons.check_rounded, color: checkColor, size: 18)
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? palette.primary : palette.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
