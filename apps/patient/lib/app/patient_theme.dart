import 'package:flutter/material.dart';

/// Cores clínicas e de marca, compartilhadas pelos dois temas.
///
/// `accent`/`danger` só podem significar `RiskLevel` (ver CLAUDE.md); o
/// mesmo tom vale em claro e escuro — é a superfície ao redor que muda. Para
/// usar qualquer uma destas como TEXTO/ÍCONE em vez de preenchimento, use
/// [PatientRiskColors] (via `context.patientRisk`), nunca o valor daqui
/// direto.
abstract final class PatientColors {
  static const accent = Color(0xFF0D9488);
  static const accentDark = Color(0xFF0F766E);
  static const danger = Color(0xFFDC2626);
}

abstract final class PatientDarkColors {
  static const background = Color(0xFF030712);
  static const surface = Color(0xFF0F172A);
  static const surfaceRaised = Color(0xFF1E293B);
  static const border = Color(0xFF334155);
}

abstract final class PatientLightColors {
  static const background = Color(0xFFF9FAFB);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceRaised = Color(0xFFFFFFFF);
  static const border = Color(0xFFD1D5DB);
}

/// Variantes de `PatientColors`/`RiskLevel.yellow` para uso como
/// TEXTO/ÍCONE sobre superfície (`surfaceRaised`/`background`), nunca como
/// preenchimento.
///
/// Ao contrário de [PatientColors], a cor certa depende do tema ativo — um
/// [ThemeExtension] em vez de `static const`. No escuro, `accent` como
/// texto direto cai para 3.91:1 (abaixo de 4.5:1, WCAG 1.4.3); no claro,
/// `accent` cai para 3.74:1 e `danger` cai abaixo de 4.5:1 sobre o fundo da
/// tela. `yellowOnSurface` é o tom usado para `RiskLevel.yellow` em
/// `_TriageResult`, que nunca teve token de preenchimento equivalente. Ver
/// `test/contrast_tokens_test.dart` e `test/contrast_tokens_light_test.dart`.
@immutable
class PatientRiskColors extends ThemeExtension<PatientRiskColors> {
  const PatientRiskColors({
    required this.dangerOnSurface,
    required this.accentOnSurface,
    required this.yellowOnSurface,
  });

  final Color dangerOnSurface;
  final Color accentOnSurface;
  final Color yellowOnSurface;

  static const dark = PatientRiskColors(
    dangerOnSurface: Color(0xFFF87171),
    accentOnSurface: Color(0xFF2DD4BF),
    yellowOnSurface: Color(0xFFE0A800),
  );

  static const light = PatientRiskColors(
    dangerOnSurface: Color(0xFFB91C1C),
    accentOnSurface: PatientColors.accentDark,
    yellowOnSurface: Color(0xFFB45309),
  );

  @override
  PatientRiskColors copyWith({
    Color? dangerOnSurface,
    Color? accentOnSurface,
    Color? yellowOnSurface,
  }) =>
      PatientRiskColors(
        dangerOnSurface: dangerOnSurface ?? this.dangerOnSurface,
        accentOnSurface: accentOnSurface ?? this.accentOnSurface,
        yellowOnSurface: yellowOnSurface ?? this.yellowOnSurface,
      );

  @override
  PatientRiskColors lerp(ThemeExtension<PatientRiskColors>? other, double t) {
    if (other is! PatientRiskColors) return this;
    return PatientRiskColors(
      dangerOnSurface: Color.lerp(dangerOnSurface, other.dangerOnSurface, t)!,
      accentOnSurface: Color.lerp(accentOnSurface, other.accentOnSurface, t)!,
      yellowOnSurface: Color.lerp(yellowOnSurface, other.yellowOnSurface, t)!,
    );
  }
}

/// Atalho para ler [PatientRiskColors] do tema ativo.
///
/// Cai para [PatientRiskColors.dark] quando a extensão não está registrada
/// (um `MaterialApp` de teste com `ThemeData()` padrão, por exemplo) —
/// nunca derruba a árvore de widgets por causa de uma variante de cor de
/// texto.
extension PatientThemeContext on BuildContext {
  PatientRiskColors get patientRisk => Theme.of(this).extension<PatientRiskColors>() ?? PatientRiskColors.dark;
}

ThemeData buildPatientDarkTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: PatientColors.accent,
    brightness: Brightness.dark,
    surface: PatientDarkColors.surface,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: PatientDarkColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: PatientDarkColors.surface,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: PatientDarkColors.surfaceRaised,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: PatientDarkColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PatientDarkColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: PatientDarkColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: PatientDarkColors.border),
      ),
    ),
    extensions: const [PatientRiskColors.dark],
  );
}

ThemeData buildPatientLightTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: PatientColors.accent,
    brightness: Brightness.light,
    surface: PatientLightColors.surface,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: PatientLightColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: PatientLightColors.surface,
      foregroundColor: Color(0xFF111827),
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: PatientLightColors.surfaceRaised,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: PatientLightColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PatientLightColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: PatientLightColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: PatientLightColors.border),
      ),
    ),
    extensions: const [PatientRiskColors.light],
  );
}
