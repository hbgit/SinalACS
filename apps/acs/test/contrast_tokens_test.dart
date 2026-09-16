import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/acs_theme.dart';

import 'support/contrast.dart';

/// Matriz determinística de contraste (WCAG 2.1 §1.4.3), no lugar da medição
/// manual no WebAIM que produziu `spec/ux_accessibility_assessment.md`.
///
/// A causa do relatório anterior estar errado era medir todo texto contra o
/// fundo do `Scaffold` (`AcsDarkColors.background`), quando texto de risco e
/// de status é renderizado dentro de `Card` (`AcsDarkColors.surfaceRaised`)
/// ou de `AppBar` (`AcsDarkColors.surface`) — por isso cada linha aqui
/// declara a SUPERFÍCIE real, não só o par de cores. Ver
/// `contrast_tokens_light_test.dart` para o equivalente do tema claro.
void main() {
  const normalText = 4.5;
  const largeTextOrUi = 3.0;
  const risk = AcsRiskColors.dark;

  /// (rótulo, texto/ícone, superfície, limiar) — um por par realmente
  /// renderizado no app. `branco` sobre qualquer superfície e `yellow`/
  /// `green` sobre card já eram os casos "fáceis"; ficam aqui como guarda
  /// contra regressão, não porque fossem os achados do relatório.
  final cases = <(String, Color, Color, double)>[
    ('branco sobre scaffold', Colors.white, AcsDarkColors.background, normalText),
    ('branco sobre card', Colors.white, AcsDarkColors.surfaceRaised, normalText),
    ('yellow sobre card (badge de risco amarelo)', AcsColors.yellow, AcsDarkColors.surfaceRaised, normalText),
    ('green sobre card (badge de risco verde)', AcsColors.green, AcsDarkColors.surfaceRaised, normalText),
    // Variantes de texto que o app usa em vez do fill puro (ver os testes de
    // documentação abaixo para a prova de que o fill sozinho falha).
    ('redOnSurface sobre card', risk.redOnSurface, AcsDarkColors.surfaceRaised, normalText),
    ('accentOnSurface sobre card', risk.accentOnSurface, AcsDarkColors.surfaceRaised, normalText),
    ('redOnSurface sobre scaffold', risk.redOnSurface, AcsDarkColors.background, normalText),
    ('accentOnSurface sobre scaffold', risk.accentOnSurface, AcsDarkColors.background, normalText),
    ('accentOnSurface sobre appbar', risk.accentOnSurface, AcsDarkColors.surface, normalText),
    // Preenchimento de botão: texto branco sobre a cor de fundo — o teste que
    // prova que não precisamos trocar `red`/`accent` como fill.
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

  // Documenta os dois achados do relatório reescrito (B e C): os TOKENS DE
  // PREENCHIMENTO, usados como texto direto sobre o card, falham — é por
  // isso que `redOnSurface`/`accentOnSurface` existem, em vez de reaproveitar
  // `red`/`accent` também para texto.
  test('red (fill) usado como texto sobre card fica abaixo de 4.5:1', () {
    expect(contrastOn(AcsColors.red, AcsDarkColors.surfaceRaised), lessThan(normalText));
  });

  test('accent (fill) usado como texto sobre card fica abaixo de 4.5:1', () {
    expect(contrastOn(AcsColors.accent, AcsDarkColors.surfaceRaised), lessThan(normalText));
  });

  test('#EF4444 (correção sugerida pelo relatório antigo) continua abaixo de 4.5:1 sobre card', () {
    // Documenta por que a Fase 2 não adotou a sugestão original do relatório:
    // clarear o token único não bastava.
    final ratio = contrastOn(const Color(0xFFEF4444), AcsDarkColors.surfaceRaised);
    expect(ratio, lessThan(normalText));
  });
}
