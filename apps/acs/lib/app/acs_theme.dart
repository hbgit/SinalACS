import 'package:flutter/material.dart';

abstract final class AcsColors {
  static const background = Color(0xFF030712);
  static const surface = Color(0xFF111827);
  static const surfaceRaised = Color(0xFF1F2937);
  static const border = Color(0xFF374151);
  static const accent = Color(0xFF2563EB);
  static const red = Color(0xFFDC2626);
  static const yellow = Color(0xFFF59E0B);
  static const green = Color(0xFF10B981);
}

ThemeData buildAcsTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AcsColors.background,
  colorScheme: ColorScheme.fromSeed(seedColor: AcsColors.accent, brightness: Brightness.dark, surface: AcsColors.surface),
  appBarTheme: const AppBarTheme(backgroundColor: AcsColors.surface, foregroundColor: Colors.white, elevation: 0),
  cardTheme: CardThemeData(
    color: AcsColors.surfaceRaised,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AcsColors.border)),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AcsColors.surface,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AcsColors.border)),
  ),
);