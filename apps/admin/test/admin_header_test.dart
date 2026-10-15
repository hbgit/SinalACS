import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sinalacs_admin/app/app.dart';

import 'support/fake_admin_auth.dart';
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

  test('adminRoleLabel traduz os papéis e cai num rótulo genérico', () {
    expect(adminRoleLabel('admin'), 'Administrador');
    expect(adminRoleLabel('coordinator'), 'Coordenador');
    expect(adminRoleLabel('qualquer-coisa'), 'Equipe');
  });

  testWidgets('o cabeçalho mostra o papel da sessão e não "admin.dev"', (tester) async {
    await abrirBackoffice(tester, tamanho: const Size(1024, 768));

    expect(find.text('BACKOFFICE • ADMINISTRADOR'), findsOneWidget);
    expect(find.textContaining('admin.dev', findRichText: true), findsNothing);
    expect(find.textContaining('ADM-001'), findsNothing, reason: 'o userId não vai para o cabeçalho');
  });

  testWidgets('sessão de coordenador mostra "Coordenador"', (tester) async {
    await abrirBackoffice(tester, tamanho: const Size(1024, 768), auth: FakeAdminAuth()..role = 'coordinator');

    expect(find.text('BACKOFFICE • COORDENADOR'), findsOneWidget);
  });

  for (final (rotulo, tamanho) in const [
    ('320dp', Size(320, 640)),
    ('360dp', Size(360, 800)),
    ('paisagem 800x360', Size(800, 360)),
    ('largo 1024dp', Size(1024, 768)),
  ]) {
    testWidgets('o cabeçalho com o papel cabe a 200% de fonte em $rotulo', (tester) async {
      await abrirBackoffice(tester, tamanho: tamanho, escalaDeFonte: 2.0, auth: FakeAdminAuth()..role = 'coordinator');

      esperarSemEstouroDeLayout(tester, 'cabeçalho com papel em $rotulo');
      esperarCaberNaLargura(tester, find.byType(AppBar), 'AppBar em $rotulo');
      expect(find.textContaining('COORDENADOR'), findsOneWidget);
    });
  }
}
