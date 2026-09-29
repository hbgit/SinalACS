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

  /// Variantes de `red`/`accent` para uso como TEXTO/ÍCONE sobre superfície
  /// escura (`surface`/`surfaceRaised`), não como preenchimento.
  ///
  /// `red` cai para 3,04:1 sobre `surfaceRaised` e `accent` para 2,33:1, contra
  /// os 4,5:1 da WCAG 1.4.3. Como preenchimento os dois continuam corretos
  /// (branco sobre `red` dá 4,83:1; sobre `accent`, 6,29:1), por isso não são
  /// substituídos — só a leitura como texto muda. `yellow` e `green` não
  /// precisam de variante: já passam (6,83:1 e 5,79:1) sobre `surfaceRaised`.
  ///
  /// `accentOnSurface` é indigo-400, e não o `#60A5FA` do ACS: o accent do
  /// backoffice é indigo `#4F46E5`, não o azul `#2563EB` do ACS. A regra
  /// compartilhada é o passo -400 da mesma cor, não o valor literal.
  static const redOnSurface = Color(0xFFF87171);
  static const accentOnSurface = Color(0xFF818CF8);
}

/// Cor de texto/ícone equivalente a uma cor clínica de preenchimento.
///
/// Ponto único de conversão: `riskColor()` em `app.dart` alimenta tanto um
/// `backgroundColor`/borda (fill) quanto, em alguns pontos, um `TextStyle`
/// direto — sem este helper cada call site teria que lembrar sozinho de
/// trocar `red`/`accent` pela variante. `yellow`/`green` retornam inalterados.
Color adminOnSurface(Color fill) => switch (fill) {
      AdminColors.red => AdminColors.redOnSurface,
      AdminColors.accent => AdminColors.accentOnSurface,
      _ => fill,
    };

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
