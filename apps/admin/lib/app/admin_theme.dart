import 'package:flutter/material.dart';

abstract final class AdminColors {
  static const background = Color(0xFF030712);
  static const surface = Color(0xFF111827);
  static const surfaceRaised = Color(0xFF1F2937);
  static const border = Color(0xFF374151);
  static const accent = Color(0xFF4F46E5);
  static const red = Color(0xFFDC2626);
  static const yellow = Color(0xFFF59E0B);
  static const green = Color(0xFF10B981);
}

ThemeData buildAdminTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AdminColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AdminColors.accent,
        brightness: Brightness.dark,
        surface: AdminColors.surface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AdminColors.surface,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AdminColors.surface,
      ),
      cardTheme: CardThemeData(
        color: AdminColors.surfaceRaised,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AdminColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AdminColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AdminColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AdminColors.border),
        ),
      ),
    );
