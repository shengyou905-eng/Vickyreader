import 'package:flutter/material.dart';

enum AppThemeId {
  lavender('lavender', 'Lavender', '薰衣草'),
  babyBlue('baby_blue', 'Baby Blue', '春水'),
  paper('paper', 'Paper', '纸页'),
  sage('sage', 'Sage', '灰绿');

  final String storageValue;
  final String label;
  final String chineseLabel;

  const AppThemeId(this.storageValue, this.label, this.chineseLabel);

  static AppThemeId fromStorage(String? value) {
    return AppThemeId.values.firstWhere(
      (theme) => theme.storageValue == value,
      orElse: () => AppThemeId.lavender,
    );
  }
}

@immutable
class AppVisualFoundation extends ThemeExtension<AppVisualFoundation> {
  final Color background;
  final Color surface;
  final Color surfaceSoft;
  final Color ink;
  final Color inkMuted;
  final Color divider;
  final Color shadow;
  final double pagePadding;
  final double sectionSpacing;
  final double cardPadding;
  final double cardRadius;
  final double controlRadius;
  final double paperTextureOpacity;
  final Duration motionDuration;

  const AppVisualFoundation({
    required this.background,
    required this.surface,
    required this.surfaceSoft,
    required this.ink,
    required this.inkMuted,
    required this.divider,
    required this.shadow,
    required this.pagePadding,
    required this.sectionSpacing,
    required this.cardPadding,
    required this.cardRadius,
    required this.controlRadius,
    required this.paperTextureOpacity,
    required this.motionDuration,
  });

  static const standard = AppVisualFoundation(
    background: Color(0xFFF5F3EE),
    surface: Color(0xFFFBFAF6),
    surfaceSoft: Color(0xFFEFEEE8),
    ink: Color(0xFF20211F),
    inkMuted: Color(0xFF72746F),
    divider: Color(0xFFDEDDD6),
    shadow: Color(0xFF65645F),
    pagePadding: 20,
    sectionSpacing: 24,
    cardPadding: 16,
    cardRadius: 16,
    controlRadius: 12,
    paperTextureOpacity: 0.025,
    motionDuration: Duration(milliseconds: 220),
  );

  List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: shadow.withValues(alpha: 0.07),
      blurRadius: 18,
      offset: const Offset(0, 7),
    ),
  ];

  @override
  AppVisualFoundation copyWith({
    Color? background,
    Color? surface,
    Color? surfaceSoft,
    Color? ink,
    Color? inkMuted,
    Color? divider,
    Color? shadow,
    double? pagePadding,
    double? sectionSpacing,
    double? cardPadding,
    double? cardRadius,
    double? controlRadius,
    double? paperTextureOpacity,
    Duration? motionDuration,
  }) {
    return AppVisualFoundation(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceSoft: surfaceSoft ?? this.surfaceSoft,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      divider: divider ?? this.divider,
      shadow: shadow ?? this.shadow,
      pagePadding: pagePadding ?? this.pagePadding,
      sectionSpacing: sectionSpacing ?? this.sectionSpacing,
      cardPadding: cardPadding ?? this.cardPadding,
      cardRadius: cardRadius ?? this.cardRadius,
      controlRadius: controlRadius ?? this.controlRadius,
      paperTextureOpacity: paperTextureOpacity ?? this.paperTextureOpacity,
      motionDuration: motionDuration ?? this.motionDuration,
    );
  }

  @override
  AppVisualFoundation lerp(AppVisualFoundation? other, double t) {
    if (other == null) return this;
    return AppVisualFoundation(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSoft: Color.lerp(surfaceSoft, other.surfaceSoft, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      pagePadding: _lerpDouble(pagePadding, other.pagePadding, t),
      sectionSpacing: _lerpDouble(sectionSpacing, other.sectionSpacing, t),
      cardPadding: _lerpDouble(cardPadding, other.cardPadding, t),
      cardRadius: _lerpDouble(cardRadius, other.cardRadius, t),
      controlRadius: _lerpDouble(controlRadius, other.controlRadius, t),
      paperTextureOpacity: _lerpDouble(
        paperTextureOpacity,
        other.paperTextureOpacity,
        t,
      ),
      motionDuration: t < 0.5 ? motionDuration : other.motionDuration,
    );
  }
}

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color primary;
  final Color primaryDeep;
  final Color primarySoft;
  final Color selectedBackground;
  final Color glow;
  final Color onPrimary;

  const AppPalette({
    required this.primary,
    required this.primaryDeep,
    required this.primarySoft,
    required this.selectedBackground,
    required this.glow,
    required this.onPrimary,
  });

  // Compatibility aliases while existing screens migrate to semantic tokens.
  Color get background => AppVisualFoundation.standard.background;
  Color get surface => AppVisualFoundation.standard.surface;
  Color get card => AppVisualFoundation.standard.surface;
  Color get primaryLight => primarySoft;
  Color get primaryDark => primaryDeep;
  Color get icon => primary;
  Color get illustration => glow;
  Color get textPrimary => AppVisualFoundation.standard.ink;
  Color get textSecondary => AppVisualFoundation.standard.inkMuted;
  Color get divider => AppVisualFoundation.standard.divider;
  Color get buttonForeground => onPrimary;

  @override
  AppPalette copyWith({
    Color? primary,
    Color? primaryDeep,
    Color? primarySoft,
    Color? selectedBackground,
    Color? glow,
    Color? onPrimary,
  }) {
    return AppPalette(
      primary: primary ?? this.primary,
      primaryDeep: primaryDeep ?? this.primaryDeep,
      primarySoft: primarySoft ?? this.primarySoft,
      selectedBackground: selectedBackground ?? this.selectedBackground,
      glow: glow ?? this.glow,
      onPrimary: onPrimary ?? this.onPrimary,
    );
  }

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDeep: Color.lerp(primaryDeep, other.primaryDeep, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      selectedBackground: Color.lerp(
        selectedBackground,
        other.selectedBackground,
        t,
      )!,
      glow: Color.lerp(glow, other.glow, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
    );
  }
}

class AppTheme {
  // Legacy tokens remain available while screens migrate to context.appPalette.
  static const Color primaryLight = Color(0xFFE8E1EF);
  static const Color primary = Color(0xFF75658F);
  static const Color primaryDark = Color(0xFF514460);
  static const Color background = Color(0xFFF5F3EE);
  static const Color surface = Color(0xFFFBFAF6);
  static const Color textPrimary = Color(0xFF20211F);
  static const Color textSecondary = Color(0xFF72746F);
  static const Color dividerColor = Color(0xFFDEDDD6);

  static const AppPalette lavender = AppPalette(
    primary: Color(0xFF75658F),
    primaryDeep: Color(0xFF514460),
    primarySoft: Color(0xFFE8E1EF),
    selectedBackground: Color(0xFFDCD2E7),
    glow: Color(0xFFA999BE),
    onPrimary: Color(0xFFFBFAF6),
  );

  static const AppPalette babyBlue = AppPalette(
    primary: Color(0xFF89CFF0),
    primaryDeep: Color(0xFF4D829A),
    primarySoft: Color(0xFFDDEFF6),
    selectedBackground: Color(0xFFCCE6F0),
    glow: Color(0xFFA9D7E9),
    onPrimary: Color(0xFF20211F),
  );

  static const AppPalette paper = AppPalette(
    primary: Color(0xFF9A8768),
    primaryDeep: Color(0xFF6E5E45),
    primarySoft: Color(0xFFE7DED0),
    selectedBackground: Color(0xFFDBCFBC),
    glow: Color(0xFFB9A889),
    onPrimary: Color(0xFFFBFAF6),
  );

  static const AppPalette sage = AppPalette(
    primary: Color(0xFF708871),
    primaryDeep: Color(0xFF4F6552),
    primarySoft: Color(0xFFDCE5D8),
    selectedBackground: Color(0xFFCEDBC9),
    glow: Color(0xFF98AA92),
    onPrimary: Color(0xFFFBFAF6),
  );

  static AppPalette paletteFor(AppThemeId themeId) {
    switch (themeId) {
      case AppThemeId.babyBlue:
        return babyBlue;
      case AppThemeId.paper:
        return paper;
      case AppThemeId.sage:
        return sage;
      case AppThemeId.lavender:
        return lavender;
    }
  }

  static ThemeData forTheme(AppThemeId themeId) {
    final palette = paletteFor(themeId);
    const visuals = AppVisualFoundation.standard;
    return ThemeData(
      useMaterial3: true,
      extensions: [visuals, palette],
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.primary,
        primary: palette.primary,
        secondary: palette.primarySoft,
        surface: visuals.surface,
        onPrimary: palette.onPrimary,
        onSurface: visuals.ink,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: visuals.background,
      canvasColor: visuals.background,
      shadowColor: visuals.shadow.withValues(alpha: 0.08),
      appBarTheme: AppBarTheme(
        backgroundColor: visuals.surface,
        foregroundColor: visuals.ink,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: visuals.ink,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: visuals.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: visuals.shadow.withValues(alpha: 0.08),
        elevation: 0.7,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(visuals.cardRadius),
          side: BorderSide(color: visuals.divider.withValues(alpha: 0.7)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(visuals.controlRadius),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.onPrimary,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.primary,
        foregroundColor: palette.onPrimary,
        elevation: 2,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: visuals.surface,
        indicatorColor: palette.selectedBackground.withValues(alpha: 0.72),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? palette.primaryDark
                : visuals.inkMuted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? visuals.ink
                : visuals.inkMuted,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: visuals.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      iconTheme: IconThemeData(color: palette.primary),
      dividerColor: visuals.divider,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: visuals.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(visuals.controlRadius),
          borderSide: BorderSide(color: visuals.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(visuals.controlRadius),
          borderSide: BorderSide(color: visuals.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(visuals.controlRadius),
          borderSide: BorderSide(color: palette.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: visuals.ink,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: visuals.ink,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: visuals.ink,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: visuals.ink,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: visuals.ink, height: 1.55),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: visuals.inkMuted,
          height: 1.5,
        ),
      ),
    );
  }

  static ThemeData get lightTheme => forTheme(AppThemeId.lavender);
}

extension AppThemeContext on BuildContext {
  AppPalette get appPalette {
    return Theme.of(this).extension<AppPalette>() ?? AppTheme.lavender;
  }

  AppVisualFoundation get appVisuals {
    return Theme.of(this).extension<AppVisualFoundation>() ??
        AppVisualFoundation.standard;
  }
}

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
