import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/app/patient_theme.dart';

import 'support/contrast.dart';

/// Matriz determinística de contraste (WCAG 2.1 §1.4.3) — ver o irmão em
/// `apps/acs/test/contrast_tokens_test.dart` para o porquê deste teste
/// existir no lugar da medição manual no WebAIM, e
/// `contrast_tokens_light_test.dart` para o equivalente do tema claro.
void main() {
  const normalText = 4.5;
  const largeTextOrUi = 3.0;
  const risk = PatientRiskColors.dark;

  final cases = <(String, Color, Color, double)>[
    ('branco sobre scaffold', Colors.white, PatientDarkColors.background, normalText),
    ('branco sobre card', Colors.white, PatientDarkColors.surfaceRaised, normalText),
    // Achado A do relatório antigo era falso positivo: passa com folga.
    ('white54 sobre card (rodapé da triagem)', Colors.white54, PatientDarkColors.surfaceRaised, normalText),
    ('yellowOnSurface sobre card (risco amarelo)', risk.yellowOnSurface, PatientDarkColors.surfaceRaised, normalText),
    // Variantes de texto que o app usa em vez do fill puro (ver os testes de
    // documentação abaixo para a prova de que o fill sozinho falha).
    ('dangerOnSurface sobre card', risk.dangerOnSurface, PatientDarkColors.surfaceRaised, normalText),
    ('dangerOnSurface sobre scaffold', risk.dangerOnSurface, PatientDarkColors.background, normalText),
    ('accentOnSurface sobre card', risk.accentOnSurface, PatientDarkColors.surfaceRaised, normalText),
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

  // Achado A (refutado) e os achados de texto do relatório reescrito: os
  // TOKENS DE PREENCHIMENTO, usados como texto direto sobre superfície,
  // falham — por isso `dangerOnSurface`/`accentOnSurface` existem em vez de
  // reaproveitar `danger`/`accent` também para texto.
  test('danger (fill) usado como texto sobre card fica abaixo de 4.5:1', () {
    expect(contrastOn(PatientColors.danger, PatientDarkColors.surfaceRaised), lessThan(normalText));
  });

  test('danger (fill) usado como texto sobre scaffold fica abaixo de 4.5:1', () {
    expect(contrastOn(PatientColors.danger, PatientDarkColors.background), lessThan(normalText));
  });

  test('accent (fill) usado como texto sobre card fica abaixo de 4.5:1', () {
    expect(contrastOn(PatientColors.accent, PatientDarkColors.surfaceRaised), lessThan(normalText));
  });
}
