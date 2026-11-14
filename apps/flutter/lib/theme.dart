import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class OTheme {
  static const purple = Color(0xFF97D5CE);
  static const aqua = Color(0xFF64C5B0);
  static const deep = Color(0xFF101F29);
  static const panel = Color(0xFF20313C);
  static const panelElevated = Color(0xFF2D4651);

  // O-AGENT Studio: quiet paper surfaces, editorial typography and measured
  // accent colors rather than neon gradients and generic dashboard tiles.
  static const paper = Color(0xFFF7F9FB);
  static const ink = Color(0xFF20323D);
  static const violet = Color(0xFF1B5966);
  static const lavender = Color(0xFFE2F1F0);
  static const warm = Color(0xFFF3E5D5);
  static const sage = Color(0xFFE2EEE7);
  static const hairline = Color(0xFFDCE6E9);

  static ThemeData studio() {
    final colors = ColorScheme.fromSeed(
      seedColor: violet,
      brightness: Brightness.light,
      surface: paper,
    ).copyWith(
      primary: violet,
      onPrimary: Colors.white,
      secondary: const Color(0xFF467862),
      onSurface: ink,
      outline: hairline,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: paper,
      // Native-feeling iOS navigation motion in the shared Flutter shell.
      // Keep animation and text scaling owned by the platform for accessibility.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      }),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        showDragHandle: true,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: paper, foregroundColor: ink,
        elevation: 0, scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: hairline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink, foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(0, 46),
          side: const BorderSide(color: hairline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: hairline),
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: paper,
        indicatorColor: lavender,
        height: 74,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: const DividerThemeData(color: hairline),
    );
  }

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
