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

  /// Variantes de `red`/`accent` para uso como TEXTO/ÍCONE sobre superfície
  /// escura (`surface`/`surfaceRaised`), não como preenchimento.
  ///
  /// `red` e `accent` só atingem ≥4.5:1 (WCAG 1.4.3) sobre o fundo do
  /// Scaffold — sobre `surfaceRaised` caem para 3.04:1 e 2.84:1. Como
  /// preenchimento de botão eles continuam corretos (branco sobre `red` dá
  /// 4.83:1), por isso não são substituídos: só a leitura como texto muda.
  /// `yellow` e `green` não precisam de variante — já passam (6.83:1 e
  /// 5.79:1) sobre `surfaceRaised`.
  static const redOnSurface = Color(0xFFF87171);
  static const accentOnSurface = Color(0xFF60A5FA);
}

/// Cor de texto/ícone equivalente a uma cor clínica de preenchimento.
///
/// Ponto único de conversão: qualquer lugar que hoje usa uma cor de
/// `switch (riskLevel) { ... AcsColors.red/accent ... }` como cor de
/// preenchimento (botão, badge, legenda) passa por aqui antes de aplicá-la a
/// um `TextStyle`/`Icon`. `yellow`/`green` retornam inalterados.
Color acsOnSurface(Color fill) => switch (fill) {
      AcsColors.red => AcsColors.redOnSurface,
      AcsColors.accent => AcsColors.accentOnSurface,
      _ => fill,
    };

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