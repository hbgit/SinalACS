import 'package:flutter/material.dart';

abstract final class PatientColors {
  static const background = Color(0xFF030712);
  static const surface = Color(0xFF0F172A);
  static const surfaceRaised = Color(0xFF1E293B);
  static const border = Color(0xFF334155);
  static const accent = Color(0xFF0D9488);
  static const accentDark = Color(0xFF0F766E);
  static const danger = Color(0xFFDC2626);
}

ThemeData buildPatientTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: PatientColors.accent,
    brightness: Brightness.dark,
    surface: PatientColors.surface,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: PatientColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: PatientColors.surface,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardTheme(
      color: PatientColors.surfaceRaised,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: PatientColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PatientColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: PatientColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: PatientColors.border),
      ),
    ),
  );
}