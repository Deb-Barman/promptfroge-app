import 'package:flutter/material.dart';

/// Prompt Forge design tokens — taken 1:1 from the CSS variables of the original PromptForge.html.
class PfPalette {
  final Brightness brightness;
  final Color bg; // --bg-0
  final Color surface; // --bg-1 (cards, bars)
  final Color surface2; // --bg-2
  final Color surface3; // --bg-3 (secondary buttons, tags)
  final Color raised; // --bg-raised
  final Color borderSubtle; // --border-subtle (cards, bars)
  final Color border; // --border (controls)
  final Color borderStrong; // --border-strong
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
    required this.surface3,
    required this.raised,
    required this.borderSubtle,
    required this.border,
    required this.borderStrong,
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
    surface2: Color(0xFF171B22),
    surface3: Color(0xFF1E232B),
    raised: Color(0xFF21262F),
    borderSubtle: Color(0xFF232830),
    border: Color(0xFF2C323C),
    borderStrong: Color(0xFF3A4150),
    text: Color(0xFFE7EAEE),
    textSecondary: Color(0xFFA8B0BC),
    textTertiary: Color(0xFF6B7280),
    amber: Color(0xFFE8A33D),
    blue: Color(0xFF5B8DEF),
    green: Color(0xFF4FAE7A),
    red: Color(0xFFE55A5A),
    violet: Color(0xFF9B7FE0),
    editorBg: Color(0xFF0D1013),
  );

  static const light = PfPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF5F6F8),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFFBFBFC),
    surface3: Color(0xFFF0F1F4),
    raised: Color(0xFFFFFFFF),
    borderSubtle: Color(0xFFE7E9ED),
    border: Color(0xFFDBDEE4),
    borderStrong: Color(0xFFC3C7D0),
    text: Color(0xFF1A1D23),
    textSecondary: Color(0xFF545B68),
    textTertiary: Color(0xFF868D99),
    amber: Color(0xFFE8A33D),
    blue: Color(0xFF5B8DEF),
    green: Color(0xFF4FAE7A),
    red: Color(0xFFE55A5A),
    violet: Color(0xFF9B7FE0),
    editorBg: Color(0xFFFFFFFF),
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
        fillColor: p.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.blue, width: 1.2)),
        hintStyle: TextStyle(color: p.textTertiary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.amber,
          foregroundColor: const Color(0xFF1A1206),
          minimumSize: const Size(44, 42),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          backgroundColor: p.surface3,
          minimumSize: const Size(44, 42),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          side: BorderSide(color: p.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: p.amber)),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: p.surface3,
        side: BorderSide(color: p.border),
        labelStyle: TextStyle(color: p.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), side: BorderSide(color: p.border)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.border)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.amber,
        unselectedLabelColor: p.textTertiary,
        indicatorColor: p.amber,
        dividerColor: p.borderSubtle,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
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
