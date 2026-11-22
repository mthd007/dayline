import 'package:flutter/material.dart';

/// Colour tokens. The dark theme is the default and is true-black friendly (OLED).
class Pal {
  Pal._();

  static const eventColors = <Color>[
    Color(0xFF7C9CFF), // periwinkle
    Color(0xFF5EE0B5), // mint
    Color(0xFFFFB86B), // apricot
    Color(0xFFFF7A90), // coral
    Color(0xFFC59BFF), // lilac
    Color(0xFF5CD0F0), // sky
    Color(0xFFE8D36A), // butter
    Color(0xFFA8E06A), // lime
  ];

  static const eventColorNames = [
    'Periwinkle',
    'Mint',
    'Apricot',
    'Coral',
    'Lilac',
    'Sky',
    'Butter',
    'Lime',
  ];

  static Color event(int i) => eventColors[i.abs() % eventColors.length];

  // Dark
  static const darkBg = Color(0xFF0B0D12);
  static const darkSurface = Color(0xFF14171F);
  static const darkSurface2 = Color(0xFF1C202B);
  static const darkLine = Color(0xFF2A2F3C);
  static const darkText = Color(0xFFECEEF4);
  static const darkMuted = Color(0xFF8F96A8);

  // Light (optional)
  static const lightBg = Color(0xFFF6F7FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurface2 = Color(0xFFEDEFF5);
  static const lightLine = Color(0xFFDDE0EA);
  static const lightText = Color(0xFF14171F);
  static const lightMuted = Color(0xFF6A7184);

  static const accent = Color(0xFF8FA8FF);
  static const accentDeep = Color(0xFF4A63D9);
}

/// Handy access to the current palette from widgets.
extension DaylineColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get bg => isDark ? Pal.darkBg : Pal.lightBg;
  Color get surface => isDark ? Pal.darkSurface : Pal.lightSurface;
  Color get surface2 => isDark ? Pal.darkSurface2 : Pal.lightSurface2;
  Color get line => isDark ? Pal.darkLine : Pal.lightLine;
  Color get text => isDark ? Pal.darkText : Pal.lightText;
  Color get muted => isDark ? Pal.darkMuted : Pal.lightMuted;
  Color get accent => isDark ? Pal.accent : Pal.accentDeep;
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() => _build(Brightness.dark);
  static ThemeData light() => _build(Brightness.light);

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final bg = dark ? Pal.darkBg : Pal.lightBg;
    final surface = dark ? Pal.darkSurface : Pal.lightSurface;
    final surface2 = dark ? Pal.darkSurface2 : Pal.lightSurface2;
    final text = dark ? Pal.darkText : Pal.lightText;
    final muted = dark ? Pal.darkMuted : Pal.lightMuted;
    final line = dark ? Pal.darkLine : Pal.lightLine;
    final accent = dark ? Pal.accent : Pal.accentDeep;

    final scheme = ColorScheme.fromSeed(
      seedColor: Pal.accentDeep,
      brightness: b,
    ).copyWith(
      primary: accent,
      onPrimary: dark ? const Color(0xFF0B1030) : Colors.white,
      surface: surface,
      onSurface: text,
      surfaceContainerHighest: surface2,
      outline: line,
      outlineVariant: line,
      error: const Color(0xFFFF6B6B),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      dividerColor: line,
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: line,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        hintStyle: TextStyle(color: muted),
        labelStyle: TextStyle(color: muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: line),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.onPrimary : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent : surface2,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.transparent : line,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface2,
        selectedColor: accent.withValues(alpha: 0.22),
        side: BorderSide(color: line),
        labelStyle: TextStyle(color: text, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface2,
        contentTextStyle: TextStyle(color: text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: text,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      ),
    );
  }
}
