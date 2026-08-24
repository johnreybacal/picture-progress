import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF667085),
      brightness: Brightness.light,
    );

    final baseTheme = ThemeData(useMaterial3: true, colorScheme: colorScheme);

    return baseTheme.copyWith(
      scaffoldBackgroundColor: const Color(0xFFF4F2EE),
      canvasColor: const Color(0xFFF4F2EE),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF4F2EE),
        foregroundColor: Color(0xFF111827),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: baseTheme.textTheme.apply(
        bodyColor: const Color(0xFF1F2937),
        displayColor: const Color(0xFF111827),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFFBFAF8),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFFFBFAF8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFFFFFF),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF344054),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF344054),
          side: const BorderSide(color: Color(0xFFD0D5DD)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF475467),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
      chipTheme: baseTheme.chipTheme.copyWith(
        backgroundColor: const Color(0xFFF2F4F7),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: baseTheme.textTheme.labelMedium?.copyWith(
          color: const Color(0xFF344054),
        ),
      ),
      dividerColor: const Color(0xFFE5E7EB),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF111827),
        contentTextStyle: baseTheme.textTheme.bodyMedium?.copyWith(
          color: Colors.white,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF344054),
        foregroundColor: Colors.white,
      ),
    );
  }
}
