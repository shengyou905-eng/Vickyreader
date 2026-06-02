import 'package:flutter/material.dart';

enum AppThemeId {
  lavender('lavender', 'Lavender', '薰衣草'),
  babyBlue('baby_blue', 'Baby Blue', '春水'),
  paper('paper', 'Paper', '纸页');

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
class AppPalette extends ThemeExtension<AppPalette> {
  final Color background;
  final Color surface;
  final Color card;
  final Color primaryLight;
  final Color primary;
  final Color primaryDark;
  final Color icon;
  final Color illustration;
  final Color textPrimary;
  final Color textSecondary;
  final Color divider;
  final Color buttonForeground;

  const AppPalette({
    required this.background,
    required this.surface,
    required this.card,
    required this.primaryLight,
    required this.primary,
    required this.primaryDark,
    required this.icon,
    required this.illustration,
    required this.textPrimary,
    required this.textSecondary,
    required this.divider,
    required this.buttonForeground,
  });

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? card,
    Color? primaryLight,
    Color? primary,
    Color? primaryDark,
    Color? icon,
    Color? illustration,
    Color? textPrimary,
    Color? textSecondary,
    Color? divider,
    Color? buttonForeground,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      primaryLight: primaryLight ?? this.primaryLight,
      primary: primary ?? this.primary,
      primaryDark: primaryDark ?? this.primaryDark,
      icon: icon ?? this.icon,
      illustration: illustration ?? this.illustration,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      divider: divider ?? this.divider,
      buttonForeground: buttonForeground ?? this.buttonForeground,
    );
  }

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      icon: Color.lerp(icon, other.icon, t)!,
      illustration: Color.lerp(illustration, other.illustration, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      buttonForeground: Color.lerp(
        buttonForeground,
        other.buttonForeground,
        t,
      )!,
    );
  }
}

class AppTheme {
  // Legacy tokens remain available while screens migrate to context.appPalette.
  static const Color primaryLight = Color(0xFFB39DDB);
  static const Color primary = Color(0xFF9575CD);
  static const Color primaryDark = Color(0xFF7E57C2);
  static const Color background = Color(0xFFF8F6FC);
  static const Color surface = Color(0xFFFEFCFF);
  static const Color textPrimary = Color(0xFF302C38);
  static const Color textSecondary = Color(0xFF767080);
  static const Color dividerColor = Color(0xFFE9E4EF);

  static const AppPalette lavender = AppPalette(
    background: Color(0xFFF8F6FC),
    surface: Color(0xFFFEFCFF),
    card: Color(0xFFFEFCFF),
    primaryLight: Color(0xFFDCCFF0),
    primary: Color(0xFF9275C7),
    primaryDark: Color(0xFF75589E),
    icon: Color(0xFF8065A5),
    illustration: Color(0xFFC9B7E8),
    textPrimary: Color(0xFF302C38),
    textSecondary: Color(0xFF767080),
    divider: Color(0xFFE9E4EF),
    buttonForeground: Color(0xFFFBF9FD),
  );

  static const AppPalette babyBlue = AppPalette(
    background: Color(0xFFF3FAFE),
    surface: Color(0xFFFCFEFF),
    card: Color(0xFFFAFDFF),
    primaryLight: Color(0xFFD6F0FC),
    primary: Color(0xFF89CFF0),
    primaryDark: Color(0xFF5FA9D0),
    icon: Color(0xFF6DB6DC),
    illustration: Color(0xFFBDE8FA),
    textPrimary: Color(0xFF303944),
    textSecondary: Color(0xFF73818E),
    divider: Color(0xFFDCEFF8),
    buttonForeground: Color(0xFFFCFEFF),
  );

  static const AppPalette paper = AppPalette(
    background: Color(0xFFF7F3EA),
    surface: Color(0xFFFCF9F1),
    card: Color(0xFFFBF7EE),
    primaryLight: Color(0xFFE2D7C4),
    primary: Color(0xFF9A8768),
    primaryDark: Color(0xFF79694F),
    icon: Color(0xFF89775A),
    illustration: Color(0xFFD8C7AA),
    textPrimary: Color(0xFF38342E),
    textSecondary: Color(0xFF7D7569),
    divider: Color(0xFFE7DFD1),
    buttonForeground: Color(0xFFFCF9F1),
  );

  static AppPalette paletteFor(AppThemeId themeId) {
    switch (themeId) {
      case AppThemeId.babyBlue:
        return babyBlue;
      case AppThemeId.paper:
        return paper;
      case AppThemeId.lavender:
        return lavender;
    }
  }

  static ThemeData forTheme(AppThemeId themeId) {
    final palette = paletteFor(themeId);
    return ThemeData(
      useMaterial3: true,
      extensions: [palette],
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.primary,
        primary: palette.primary,
        secondary: palette.primaryLight,
        surface: palette.surface,
        onPrimary: palette.buttonForeground,
        onSurface: palette.textPrimary,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: palette.background,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surface,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: palette.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.card,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.buttonForeground,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.buttonForeground,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.primary,
        foregroundColor: palette.buttonForeground,
        elevation: 2,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surface,
        indicatorColor: palette.primaryLight.withAlpha(145),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? palette.primaryDark
                : palette.icon,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? palette.textPrimary
                : palette.textSecondary,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      iconTheme: IconThemeData(color: palette.icon),
      dividerColor: palette.divider,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
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
          color: palette.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: palette.textPrimary,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: palette.textPrimary),
        bodyMedium: TextStyle(fontSize: 14, color: palette.textSecondary),
      ),
    );
  }

  static ThemeData get lightTheme => forTheme(AppThemeId.lavender);
}

extension AppThemeContext on BuildContext {
  AppPalette get appPalette {
    return Theme.of(this).extension<AppPalette>() ?? AppTheme.lavender;
  }
}
