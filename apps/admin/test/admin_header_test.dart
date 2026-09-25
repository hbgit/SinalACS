import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/layout_harness.dart';

/// O cabeçalho carrega duas linhas de texto e o selo "Acesso auditado".
///
/// Em 72dp fixos de altura e menos de 400dp de largura os três competem pelo
/// mesmo espaço. O selo é informativo, não um controle, então em tela estreita
/// ele pode virar ícone — desde que continue anunciado a leitores de tela, que
/// é o que `Semantics(label:)` garante.
void main() {
  testWidgets('mostra o selo de acesso auditado como ícone em tela estreita', (tester) async {
    await abrirBackoffice(tester, tamanho: const Size(360, 800));

    expect(find.byKey(const Key('admin_audit_badge')), findsOneWidget);
    expect(tester.widget(find.byKey(const Key('admin_audit_badge'))), isA<Icon>());
    expect(find.byType(Chip), findsNothing);
  });

  testWidgets('o selo continua anunciado a leitores de tela quando vira ícone', (tester) async {
    await abrirBackoffice(tester, tamanho: const Size(360, 800));

    expect(
      find.bySemanticsLabel('Acesso auditado'),
      findsOneWidget,
      reason: 'trocar o rótulo por um ícone não pode remover a informação de quem usa leitor de tela',
    );
  });

  testWidgets('mostra o selo de acesso auditado como chip em tela larga', (tester) async {
    await abrirBackoffice(tester, tamanho: const Size(1024, 768));

    expect(find.byKey(const Key('admin_audit_badge')), findsOneWidget);
    expect(tester.widget(find.byKey(const Key('admin_audit_badge'))), isA<Chip>());
  });
}
