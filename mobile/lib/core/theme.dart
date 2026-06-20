import 'package:flutter/material.dart';

class VegaTheme {
  static const dark = Color(0xFF0D0D0D);
  static const surface = Color(0xFF1A1A1A);
  static const card = Color(0xFF222222);
  static const accent = Color(0xFF7C4DFF);
  static const accentBlue = Color(0xFF2196F3);
  static const textPrimary = Color(0xFFE0E0E0);
  static const textSecondary = Color(0xFF9E9E9E);
  static const border = Color(0xFF333333);
  static const userBubble = Color(0xFF2A2A3A);
  static const assistantBubble = Color(0xFF1A1A1A);

  static final theme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: dark,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: accentBlue,
      surface: surface,
      onSurface: textPrimary,
    ),
    cardTheme: const CardTheme(
      color: card,
      elevation: 0,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: dark,
      elevation: 0,
      iconTheme: IconThemeData(color: textPrimary),
    ),
    dividerColor: border,
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: textPrimary),
      bodyMedium: TextStyle(color: textPrimary),
      bodySmall: TextStyle(color: textSecondary),
    ),
  );
}
