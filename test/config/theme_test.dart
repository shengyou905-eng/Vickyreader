import 'package:ai_reader/config/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lavender keeps the requested brand accent values', () {
    expect(AppTheme.lavender.primary, const Color(0xFF75658F));
    expect(AppTheme.lavender.primaryDeep, const Color(0xFF514460));
    expect(AppTheme.lavender.primarySoft, const Color(0xFFE8E1EF));
    expect(AppTheme.lavender.selectedBackground, const Color(0xFFDCD2E7));
    expect(AppTheme.lavender.glow, const Color(0xFFA999BE));
  });

  test('sage keeps the requested gray-green accent values', () {
    expect(AppTheme.sage.primary, const Color(0xFF708871));
    expect(AppTheme.sage.primaryDeep, const Color(0xFF4F6552));
    expect(AppTheme.sage.primarySoft, const Color(0xFFDCE5D8));
    expect(AppTheme.sage.selectedBackground, const Color(0xFFCEDBC9));
    expect(AppTheme.sage.glow, const Color(0xFF98AA92));
  });

  test('all themes share the warm paper foundation', () {
    const visuals = AppVisualFoundation.standard;

    expect(visuals.background, const Color(0xFFF5F3EE));
    expect(visuals.surface, const Color(0xFFFBFAF6));
    expect(visuals.surfaceSoft, const Color(0xFFEFEEE8));
    expect(visuals.ink, const Color(0xFF20211F));
    expect(visuals.inkMuted, const Color(0xFF72746F));

    for (final id in AppThemeId.values) {
      final extension = AppTheme.forTheme(id).extension<AppVisualFoundation>();
      expect(extension, same(visuals));
    }
  });

  test('unknown stored value falls back to lavender', () {
    expect(AppThemeId.fromStorage(null), AppThemeId.lavender);
    expect(AppThemeId.fromStorage('unknown'), AppThemeId.lavender);
  });
}
