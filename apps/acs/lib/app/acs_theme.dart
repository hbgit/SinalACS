import 'package:flutter/material.dart';

/// Cores clínicas e de marca, compartilhadas pelos dois temas.
///
/// `red`/`yellow`/`green` só podem significar `RiskLevel` (ver CLAUDE.md); o
/// mesmo tom vale em claro e escuro — é a superfície ao redor que muda. Para
/// usar qualquer uma destas como TEXTO/ÍCONE em vez de preenchimento, use
/// [AcsRiskColors] (via `context.acsRisk`), nunca o valor daqui direto.
abstract final class AcsColors {
  static const accent = Color(0xFF2563EB);
  static const red = Color(0xFFDC2626);
  static const yellow = Color(0xFFF59E0B);
  static const green = Color(0xFF10B981);
}

abstract final class AcsDarkColors {
  static const background = Color(0xFF030712);
  static const surface = Color(0xFF111827);
  static const surfaceRaised = Color(0xFF1F2937);
  static const border = Color(0xFF374151);
}

abstract final class AcsLightColors {
  static const background = Color(0xFFF9FAFB);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceRaised = Color(0xFFFFFFFF);
  static const border = Color(0xFFD1D5DB);
}

/// Variantes de `AcsColors` para uso como TEXTO/ÍCONE sobre superfície
/// (`surfaceRaised`/`background`), nunca como preenchimento.
///
/// Ao contrário de [AcsColors], a cor certa depende do tema ativo — um
/// [ThemeExtension] em vez de `static const`. No escuro, `red`/`accent`
/// como texto direto caem para 3.04:1 e 2.84:1 (abaixo de 4.5:1, WCAG
/// 1.4.3); `yellow`/`green` já passam e por isso reaparecem inalterados. No
/// claro é o oposto: `yellow`/`green` (desenhados para fundo escuro) caem
/// para ~2:1, e `red` cai abaixo de 4.5:1 sobre o fundo da tela — só
/// `accent` sobrevive sem alteração. Ver `test/contrast_tokens_test.dart` e
/// `test/contrast_tokens_light_test.dart`.
@immutable
class AcsRiskColors extends ThemeExtension<AcsRiskColors> {
  const AcsRiskColors({
    required this.redOnSurface,
    required this.accentOnSurface,
    required this.yellowOnSurface,
    required this.greenOnSurface,
  });

  final Color redOnSurface;
  final Color accentOnSurface;
  final Color yellowOnSurface;
  final Color greenOnSurface;

  static const dark = AcsRiskColors(
    redOnSurface: Color(0xFFF87171),
    accentOnSurface: Color(0xFF60A5FA),
    yellowOnSurface: AcsColors.yellow,
    greenOnSurface: AcsColors.green,
  );

  static const light = AcsRiskColors(
    redOnSurface: Color(0xFFB91C1C),
    accentOnSurface: AcsColors.accent,
    yellowOnSurface: Color(0xFFB45309),
    greenOnSurface: Color(0xFF047857),
  );

  @override
  AcsRiskColors copyWith({
    Color? redOnSurface,
    Color? accentOnSurface,
    Color? yellowOnSurface,
    Color? greenOnSurface,
  }) =>
      AcsRiskColors(
        redOnSurface: redOnSurface ?? this.redOnSurface,
        accentOnSurface: accentOnSurface ?? this.accentOnSurface,
        yellowOnSurface: yellowOnSurface ?? this.yellowOnSurface,
        greenOnSurface: greenOnSurface ?? this.greenOnSurface,
      );

  @override
  AcsRiskColors lerp(ThemeExtension<AcsRiskColors>? other, double t) {
    if (other is! AcsRiskColors) return this;
    return AcsRiskColors(
      redOnSurface: Color.lerp(redOnSurface, other.redOnSurface, t)!,
      accentOnSurface: Color.lerp(accentOnSurface, other.accentOnSurface, t)!,
      yellowOnSurface: Color.lerp(yellowOnSurface, other.yellowOnSurface, t)!,
      greenOnSurface: Color.lerp(greenOnSurface, other.greenOnSurface, t)!,
    );
  }
}

/// Atalho para ler [AcsRiskColors] do tema ativo.
///
/// Cai para [AcsRiskColors.dark] quando a extensão não está registrada (um
/// `MaterialApp` de teste com `ThemeData()` padrão, por exemplo) — nunca
/// derruba a árvore de widgets por causa de uma variante de cor de texto.
extension AcsThemeContext on BuildContext {
  AcsRiskColors get acsRisk => Theme.of(this).extension<AcsRiskColors>() ?? AcsRiskColors.dark;
}

/// Cor de texto/ícone equivalente a uma cor clínica de preenchimento, no
/// tema ativo em [context].
///
/// Ponto único de conversão: qualquer lugar que hoje usa uma cor de
/// `switch (riskLevel) { ... AcsColors.red/accent/yellow/green ... }` como
/// cor de preenchimento (botão, badge, legenda) passa por aqui antes de
/// aplicá-la a um `TextStyle`/`Icon`.
Color acsOnSurface(BuildContext context, Color fill) {
  final risk = context.acsRisk;
  return switch (fill) {
    AcsColors.red => risk.redOnSurface,
    AcsColors.accent => risk.accentOnSurface,
    AcsColors.yellow => risk.yellowOnSurface,
    AcsColors.green => risk.greenOnSurface,
    _ => fill,
  };
}

ThemeData buildAcsDarkTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AcsDarkColors.background,
  colorScheme: ColorScheme.fromSeed(seedColor: AcsColors.accent, brightness: Brightness.dark, surface: AcsDarkColors.surface),
  appBarTheme: const AppBarTheme(backgroundColor: AcsDarkColors.surface, foregroundColor: Colors.white, elevation: 0),
  cardTheme: CardThemeData(
    color: AcsDarkColors.surfaceRaised,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AcsDarkColors.border)),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AcsDarkColors.surface,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AcsDarkColors.border)),
  ),
  extensions: const [AcsRiskColors.dark],
);

ThemeData buildAcsLightTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  scaffoldBackgroundColor: AcsLightColors.background,
  colorScheme: ColorScheme.fromSeed(seedColor: AcsColors.accent, brightness: Brightness.light, surface: AcsLightColors.surface),
  appBarTheme: const AppBarTheme(backgroundColor: AcsLightColors.surface, foregroundColor: Color(0xFF111827), elevation: 0),
  cardTheme: CardThemeData(
    color: AcsLightColors.surfaceRaised,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AcsLightColors.border)),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AcsLightColors.background,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AcsLightColors.border)),
  ),
  extensions: const [AcsRiskColors.light],
);
