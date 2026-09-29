import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/acs_theme.dart';

import 'support/contrast.dart';

/// Equivalente de `contrast_tokens_test.dart` para o tema claro (issue #9).
///
/// `yellow`/`green` são desenhados para funcionar como texto sobre fundo
/// ESCURO (ver `AcsRiskColors.dark`); sobre fundo claro eles caem para
/// ~2:1 — por isso `AcsRiskColors.light` usa tons mais escuros
/// (`amber-700`/`emerald-700`) só para leitura como texto, sem alterar o
/// preenchimento (`AcsColors.yellow`/`green`), que continua o mesmo em
/// ambos os temas — a cor clínica não muda de significado.
void main() {
  const normalText = 4.5;
  const largeTextOrUi = 3.0;
  const risk = AcsRiskColors.light;

  final cases = <(String, Color, Color, double)>[
    ('texto principal sobre scaffold', const Color(0xFF111827), AcsLightColors.background, normalText),
    ('texto principal sobre card', const Color(0xFF111827), AcsLightColors.surfaceRaised, normalText),
    ('redOnSurface sobre card', risk.redOnSurface, AcsLightColors.surfaceRaised, normalText),
    ('redOnSurface sobre scaffold', risk.redOnSurface, AcsLightColors.background, normalText),
    ('accentOnSurface sobre card', risk.accentOnSurface, AcsLightColors.surfaceRaised, normalText),
    ('accentOnSurface sobre scaffold', risk.accentOnSurface, AcsLightColors.background, normalText),
    ('accentOnSurface sobre appbar', risk.accentOnSurface, AcsLightColors.surface, normalText),
    ('yellowOnSurface sobre card', risk.yellowOnSurface, AcsLightColors.surfaceRaised, normalText),
    ('yellowOnSurface sobre scaffold', risk.yellowOnSurface, AcsLightColors.background, normalText),
    ('greenOnSurface sobre card', risk.greenOnSurface, AcsLightColors.surfaceRaised, normalText),
    ('greenOnSurface sobre scaffold', risk.greenOnSurface, AcsLightColors.background, normalText),
    // Preenchimento de botão: continua correto sem token novo.
    ('branco sobre botão vermelho (SAMU/pânico)', Colors.white, AcsColors.red, largeTextOrUi),
    ('branco sobre botão accent (login)', Colors.white, AcsColors.accent, largeTextOrUi),
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

  // Documenta por que o tema claro precisa de tokens próprios: os fills
  // desenhados para o escuro falham como texto sobre fundo claro.
  test('yellow (fill, desenhado para o escuro) usado como texto sobre card claro fica abaixo de 4.5:1', () {
    expect(contrastOn(AcsColors.yellow, AcsLightColors.surfaceRaised), lessThan(normalText));
  });

  test('green (fill, desenhado para o escuro) usado como texto sobre card claro fica abaixo de 4.5:1', () {
    expect(contrastOn(AcsColors.green, AcsLightColors.surfaceRaised), lessThan(normalText));
  });
}
