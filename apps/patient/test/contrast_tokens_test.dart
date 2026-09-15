import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/app/patient_theme.dart';

import 'support/contrast.dart';

/// Matriz determinística de contraste (WCAG 2.1 §1.4.3) — ver o irmão em
/// `apps/acs/test/contrast_tokens_test.dart` para o porquê deste teste
/// existir no lugar da medição manual no WebAIM.
void main() {
  const normalText = 4.5;
  const largeTextOrUi = 3.0;

  const cases = <(String, Color, Color, double)>[
    ('branco sobre scaffold', Colors.white, PatientColors.background, normalText),
    ('branco sobre card', Colors.white, PatientColors.surfaceRaised, normalText),
    // Achado A do relatório antigo era falso positivo: passa com folga.
    ('white54 sobre card (rodapé da triagem)', Colors.white54, PatientColors.surfaceRaised, normalText),
    ('yellow #E0A800 sobre card (risco amarelo)', Color(0xFFE0A800), PatientColors.surfaceRaised, normalText),
    // Variantes de texto que o app usa em vez do fill puro (ver os testes de
    // documentação abaixo para a prova de que o fill sozinho falha).
    ('dangerOnSurface sobre card', PatientColors.dangerOnSurface, PatientColors.surfaceRaised, normalText),
    ('dangerOnSurface sobre scaffold', PatientColors.dangerOnSurface, PatientColors.background, normalText),
    ('accentOnSurface sobre card', PatientColors.accentOnSurface, PatientColors.surfaceRaised, normalText),
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
    expect(contrastOn(PatientColors.danger, PatientColors.surfaceRaised), lessThan(normalText));
  });

  test('danger (fill) usado como texto sobre scaffold fica abaixo de 4.5:1', () {
    expect(contrastOn(PatientColors.danger, PatientColors.background), lessThan(normalText));
  });

  test('accent (fill) usado como texto sobre card fica abaixo de 4.5:1', () {
    expect(contrastOn(PatientColors.accent, PatientColors.surfaceRaised), lessThan(normalText));
  });
}
