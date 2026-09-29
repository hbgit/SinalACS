import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';

import 'support/contrast.dart';

/// Matriz determinística de contraste (WCAG 2.1 §1.4.3), no mesmo formato de
/// `apps/acs/test/contrast_tokens_test.dart` e
/// `apps/patient/test/contrast_tokens_test.dart`.
///
/// O admin repetia o defeito que os outros dois apps já haviam corrigido:
/// `AdminColors.red`/`accent` usados como cor de PREENCHIMENTO (botão, faixa
/// lateral de risco) também eram usados como cor de TEXTO/ÍCONE sobre
/// `Card`/`AppBar` — papéis com exigências opostas. Cada linha abaixo declara
/// a SUPERFÍCIE real onde o texto/ícone é renderizado, não só o par de cores.
void main() {
  const normalText = 4.5;
  const largeTextOrUi = 3.0;

  /// (rótulo, texto/ícone, superfície, limiar) — um por par realmente
  /// renderizado no app.
  const cases = <(String, Color, Color, double)>[
    ('branco sobre scaffold', Colors.white, AdminColors.background, normalText),
    ('branco sobre card', Colors.white, AdminColors.surfaceRaised, normalText),
    ('branco sobre appbar', Colors.white, AdminColors.surface, normalText),
    ('yellow sobre card (badge de risco amarelo)', AdminColors.yellow, AdminColors.surfaceRaised, normalText),
    ('green sobre card (badge de risco verde)', AdminColors.green, AdminColors.surfaceRaised, normalText),
    // Variantes de texto que o app passa a usar em vez do fill puro (ver os
    // testes de documentação abaixo para a prova de que o fill sozinho falha).
    ('redOnSurface sobre card', AdminColors.redOnSurface, AdminColors.surfaceRaised, normalText),
    ('accentOnSurface sobre card', AdminColors.accentOnSurface, AdminColors.surfaceRaised, normalText),
    ('redOnSurface sobre scaffold', AdminColors.redOnSurface, AdminColors.background, normalText),
    ('accentOnSurface sobre scaffold', AdminColors.accentOnSurface, AdminColors.background, normalText),
    // O eyebrow do cabeçalho renderiza sobre a AppBar (AdminColors.surface),
    // não sobre um Card — é por isso que accentOnSurface precisa passar nas
    // duas superfícies, e não só sobre card.
    ('accentOnSurface sobre appbar (eyebrow do cabeçalho)', AdminColors.accentOnSurface, AdminColors.surface, normalText),
    // Preenchimento: texto branco sobre a cor de fundo — a prova de que não
    // precisamos trocar `red`/`accent` como fill.
    ('branco sobre red (faixa/chip de risco)', Colors.white, AdminColors.red, largeTextOrUi),
    ('branco sobre accent (botão do colorScheme)', Colors.white, AdminColors.accent, largeTextOrUi),
  ];

  for (final (label, fg, bg, threshold) in cases) {
    test(label, () {
      final ratio = contrastOn(fg, bg);
      expect(
        ratio,
        greaterThanOrEqualTo(threshold),
        reason: '$label: $ratio:1 abaixo do limiar $threshold:1 exigido pela WCAG',
      );
    });
  }

  // Documenta os achados originais: os TOKENS DE PREENCHIMENTO, usados como
  // texto/ícone direto, falham — é por isso que redOnSurface/accentOnSurface
  // existem, em vez de reaproveitar red/accent também para texto.
  test('red (fill) usado como texto sobre card fica abaixo de 4,5:1', () {
    expect(contrastOn(AdminColors.red, AdminColors.surfaceRaised), lessThan(normalText));
  });

  test('accent (fill) usado como texto sobre card fica abaixo de 4,5:1', () {
    expect(contrastOn(AdminColors.accent, AdminColors.surfaceRaised), lessThan(normalText));
  });

  test('accent (fill) usado como ícone sobre card fica abaixo de 3:1', () {
    // O ícone do banner "Ambiente de desenvolvimento" é WCAG 1.4.11 (limiar
    // 3:1 para componente não-textual), não 1.4.3 — mas falha nos dois.
    expect(contrastOn(AdminColors.accent, AdminColors.surfaceRaised), lessThan(largeTextOrUi));
  });

  test('o accentOnSurface do ACS (#60A5FA) passaria no contraste mas troca o matiz', () {
    // Documenta por que o valor não foi copiado literalmente de acs_theme.dart:
    // o par (fill, texto) do admin é indigo/indigo, não indigo/azul. #60A5FA
    // atinge 4,5:1 aqui também — o problema não é matemático, é de identidade
    // visual, e não aparece num teste de contraste isolado.
    const acsAccentOnSurface = Color(0xFF60A5FA);
    expect(contrastOn(acsAccentOnSurface, AdminColors.surfaceRaised), greaterThanOrEqualTo(normalText));
  });
}
