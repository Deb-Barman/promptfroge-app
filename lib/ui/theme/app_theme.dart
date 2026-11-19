import 'package:flutter/material.dart';

/// Prompt Forge design tokens (premium dark developer workspace; amber + blue accents).
class PfPalette {
  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color border;
  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color amber;
  final Color blue;
  final Color green;
  final Color red;
  final Color violet;
  final Color editorBg;

  const PfPalette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.amber,
    required this.blue,
    required this.green,
    required this.red,
    required this.violet,
    required this.editorBg,
  });

  static const dark = PfPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF0B0D10),
    surface: Color(0xFF12151A),
    surface2: Color(0xFF181C22),
    border: Color(0xFF242932),
    text: Color(0xFFE6E8EB),
    textSecondary: Color(0xFFA0A7B2),
    textTertiary: Color(0xFF7A8290),
    amber: Color(0xFFE8A33D),
    blue: Color(0xFF5B8DEF),
    green: Color(0xFF4FAE7A),
    red: Color(0xFFE55A5A),
    violet: Color(0xFF9B7FE0),
    editorBg: Color(0xFF0E1115),
  );

  static const light = PfPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF5F6F8),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF0F2F5),
    border: Color(0xFFE1E4EA),
    text: Color(0xFF14171C),
    textSecondary: Color(0xFF4A515C),
    textTertiary: Color(0xFF7A8290),
    amber: Color(0xFFC98712),
    blue: Color(0xFF3B6FD6),
    green: Color(0xFF2F8F5B),
    red: Color(0xFFD14343),
    violet: Color(0xFF7A5CC9),
    editorBg: Color(0xFFFBFBFC),
  );
}

extension PfContext on BuildContext {
  PfPalette get pf => Theme.of(this).brightness == Brightness.dark ? PfPalette.dark : PfPalette.light;
}

class AppTheme {
  AppTheme._();

  static const List<String> uiFontFallback = ['Inter', 'SF Pro Text', 'Roboto', 'Segoe UI', 'sans-serif'];

  static ThemeData build(PfPalette p) {
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.amber,
      onPrimary: p.brightness == Brightness.dark ? const Color(0xFF1A1305) : Colors.white,
      secondary: p.blue,
      onSecondary: Colors.white,
      error: p.red,
      onError: Colors.white,
      surface: p.surface,
      onSurface: p.text,
    );
    final base = ThemeData(brightness: p.brightness, useMaterial3: true, colorScheme: scheme);
    final text = base.textTheme.apply(bodyColor: p.text, displayColor: p.text, fontFamily: uiFontFallback.first, fontFamilyFallback: uiFontFallback);
    return base.copyWith(
      scaffoldBackgroundColor: p.bg,
      textTheme: text,
      dividerColor: p.border,
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 20),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.amber.withOpacity(0.16),
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.textSecondary)),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.amber : p.textTertiary)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.amber.withOpacity(0.16),
        selectedIconTheme: IconThemeData(color: p.amber),
        unselectedIconTheme: IconThemeData(color: p.textTertiary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.amber, width: 1.4)),
        hintStyle: TextStyle(color: p.textTertiary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.amber,
          foregroundColor: p.brightness == Brightness.dark ? const Color(0xFF1A1305) : Colors.white,
          minimumSize: const Size(44, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          minimumSize: const Size(44, 46),
          side: BorderSide(color: p.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: p.amber)),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: p.surface2,
        side: BorderSide(color: p.border),
        labelStyle: TextStyle(color: p.textSecondary, fontSize: 12.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surface2,
        contentTextStyle: TextStyle(color: p.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.amber : p.textTertiary),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.amber.withOpacity(0.35) : p.surface2),
      ),
      dividerTheme: DividerThemeData(color: p.border, space: 1, thickness: 1),
    );
  }

  static ThemeData get dark => build(PfPalette.dark);
  static ThemeData get light => build(PfPalette.light);
}
