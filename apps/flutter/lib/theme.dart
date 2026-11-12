import 'package:flutter/material.dart';

class OTheme {
  static const purple = Color(0xFFB48CFF);
  static const aqua = Color(0xFF5FE0C0);
  static const deep = Color(0xFF11111A);
  static const panel = Color(0xFF1D1C28);
  static const panelElevated = Color(0xFF29263A);

  static ThemeData dark() {
    final colors = ColorScheme.fromSeed(
      seedColor: purple,
      brightness: Brightness.dark,
      surface: deep,
    ).copyWith(
      primary: purple,
      onPrimary: deep,
      secondary: aqua,
      surface: deep,
      onSurface: const Color(0xFFF2EFFB),
      outline: const Color(0xFF464156),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: deep,
      appBarTheme: const AppBarTheme(backgroundColor: deep, foregroundColor: Colors.white, elevation: 0),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19), side: const BorderSide(color: Color(0xFF343043))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF514A62))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: purple, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: panel,
        indicatorColor: panelElevated,
        height: 75,
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: deep,
          backgroundColor: purple,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      dividerTheme: const DividerThemeData(color: Color(0xFF343043)),
    );
  }
}
