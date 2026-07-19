import 'package:flutter/material.dart';

ThemeData buildLaMaisonTheme() {
  const background = Color(0xFFFAFAF8);
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF5C4D7D),
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: background,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}
