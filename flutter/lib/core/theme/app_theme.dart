import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: const Color(0xFFFFB6C1), // Baby Pink
      scaffoldBackgroundColor: Colors.transparent, // Let global background show through
      colorScheme: const ColorScheme.light(
        primary: Color(0xFFFFB6C1),
        secondary: Color(0xFFFF6B9D), // Hot Pink
        surface: Color(0x66FFFFFF), // Frosted glass light
        onPrimary: Color(0xFF2D151E),
        onSurface: Color(0xFFC2185B), // Deep Rose for text
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF2D151E), // Dark rich plum background
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: const Color(0xFF8B2B4E), // Deep plum/magenta
      scaffoldBackgroundColor: Colors.transparent, // Let global background show through
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF8B2B4E), // Deep plum/magenta
        secondary: Color(0xFFFFB6C1), // Baby Pink for accents
        surface: Color(0x22FFFFFF), // Frosted glass dark
        onPrimary: Colors.white,
        onSurface: Color(0xFFFFB6C1), // Baby pink for text in dark mode
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFFFFF0F5), // Light lavender blush background
        contentTextStyle: const TextStyle(color: Color(0xFF2D151E), fontWeight: FontWeight.w600),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
