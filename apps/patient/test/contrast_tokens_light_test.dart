import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/app/patient_theme.dart';

import 'support/contrast.dart';

/// Equivalente de `contrast_tokens_test.dart` para o tema claro (issue #9).
///
/// `accent` (teal-600) é desenhado para funcionar como texto sobre fundo
/// ESCURO (ver `PatientRiskColors.dark`); sobre fundo claro cai para
/// 3.74:1 — por isso `PatientRiskColors.light` usa um tom mais escuro
/// (`PatientColors.accentDark`, teal-700) só para leitura como texto, sem
/// alterar o preenchimento (`PatientColors.accent`), que continua o mesmo
/// em ambos os temas.
void main() {
  const normalText = 4.5;
  const largeTextOrUi = 3.0;
  const risk = PatientRiskColors.light;

  final cases = <(String, Color, Color, double)>[
    ('texto principal sobre scaffold', const Color(0xFF111827), PatientLightColors.background, normalText),
    ('texto principal sobre card', const Color(0xFF111827), PatientLightColors.surfaceRaised, normalText),
    ('dangerOnSurface sobre card', risk.dangerOnSurface, PatientLightColors.surfaceRaised, normalText),
    ('dangerOnSurface sobre scaffold', risk.dangerOnSurface, PatientLightColors.background, normalText),
    ('accentOnSurface sobre card', risk.accentOnSurface, PatientLightColors.surfaceRaised, normalText),
    ('accentOnSurface sobre scaffold', risk.accentOnSurface, PatientLightColors.background, normalText),
    ('yellowOnSurface sobre card', risk.yellowOnSurface, PatientLightColors.surfaceRaised, normalText),
    ('yellowOnSurface sobre scaffold', risk.yellowOnSurface, PatientLightColors.background, normalText),
    // Preenchimento de botão: continua correto sem token novo.
    ('branco sobre botão de pânico (danger fill)', Colors.white, PatientColors.danger, largeTextOrUi),
  ];

  for (final (label, fg, bg, threshold) in cases) {
    test(label, () {
      final ratio = contrastOn(fg, bg);
      expect(
        ratio,
        greaterThanOrEqualTo(threshold),
        reason: '$label: $ratio:1 abaixo do limiar $threshold:1 exigido pela WCAG 1.4.3',
      );
    });
  }

  // Documenta por que o tema claro precisa de um tom próprio de accent: o
  // fill (teal-600) falha como texto sobre card claro. `danger` (vermelho),
  // ao contrário de `accent`, passa por pouco mesmo sem token dedicado
  // (4.83:1 sobre card) — `dangerOnSurface` é usado mesmo assim, pela mesma
  // margem de segurança já adotada no tema escuro.
  test('accent (fill, teal-600) usado como texto sobre card claro fica abaixo de 4.5:1', () {
    expect(contrastOn(PatientColors.accent, PatientLightColors.surfaceRaised), lessThan(normalText));
  });
}
