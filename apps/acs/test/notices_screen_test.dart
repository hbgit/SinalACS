import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';

import 'support/fakes.dart';
import 'support/semantics_scan.dart';

/// Mesmo caminho de `entrar` em `login_flow_test.dart` (não importável entre
/// arquivos de teste). Credenciais sintéticas.
Future<void> entrar(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
  await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
  await tester.tap(find.byKey(const Key('login_button')));
  await tester.pumpAndSettle();
}

Future<void> abrirAvisos(WidgetTester tester, FakeAcsBackend backend) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SinalAcsApp(backend: backend, feedBuilder: (queue) => FakeAlertFeed(queue)),
  );
  await entrar(tester);
  await tester.tap(find.text('Mais'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Avisos à comunidade'));
  await tester.pumpAndSettle();
}

Future<void> preencher(WidgetTester tester, {String titulo = 'Vacinação', String mensagem = 'Amanhã, das 8h às 12h.'}) async {
  await tester.enterText(find.byKey(const Key('notice_title_field')), titulo);
  await tester.enterText(find.byKey(const Key('notice_message_field')), mensagem);
  await tester.pump();
}

void main() {
  testWidgets('enviar chama o backend com título, mensagem e público e mostra o resultado', (tester) async {
    final backend = FakeAcsBackend();
    await abrirAvisos(tester, backend);
    await preencher(tester);
    await tester.tap(find.byKey(const Key('notice_chronic_switch')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('notice_send_button')));
    await tester.pumpAndSettle();

    expect(backend.notices, [('Vacinação', 'Amanhã, das 8h às 12h.', true)]);
    expect(find.textContaining('2 de 3'), findsOneWidget);
  });

  testWidgets('botão desabilitado com título ou mensagem vazios', (tester) async {
    await abrirAvisos(tester, FakeAcsBackend());
    FilledButton botao() =>
        tester.widget<FilledButton>(find.byKey(const Key('notice_send_button')));
    expect(botao().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('notice_title_field')), 'Só título');
    await tester.pump();
    expect(botao().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('notice_message_field')), '   ');
    await tester.pump();
    expect(botao().onPressed, isNull);
  });

  testWidgets('falha do envio mostra o erro do servidor e mantém o texto digitado', (tester) async {
    final backend = FakeAcsBackend()
      ..noticeFailure = const BackendFailure('Não foi possível entregar o aviso agora.');
    await abrirAvisos(tester, backend);
    await preencher(tester, titulo: 'T', mensagem: 'M');
    await tester.tap(find.byKey(const Key('notice_send_button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Não foi possível entregar'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('notice_message_field'))).controller!.text,
      'M',
    );
    expect(find.textContaining('2 de 3'), findsNothing);
  });

  testWidgets('o aviso pede para não escrever dado de saúde e mostra os limites', (tester) async {
    await abrirAvisos(tester, FakeAcsBackend());
    expect(find.textContaining('Não escreva nome nem condição de saúde'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('notice_title_field'))).maxLength, 60);
    expect(tester.widget<TextField>(find.byKey(const Key('notice_message_field'))).maxLength, 240);
  });

  testWidgets('toque duplo no envio manda um aviso só', (tester) async {
    final gate = Completer<void>();
    final backend = FakeAcsBackend()..noticeGate = gate;
    await abrirAvisos(tester, backend);
    await preencher(tester);
    await tester.tap(find.byKey(const Key('notice_send_button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('notice_send_button')), warnIfMissed: false);
    await tester.pump();
    expect(backend.notices, hasLength(1));

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('2 de 3'), findsOneWidget);
  });

  testWidgets('a tela de avisos não cria nó de botão inerte', (tester) async {
    final handle = tester.ensureSemantics();
    await abrirAvisos(tester, FakeAcsBackend());
    expectNenhumBotaoInerte(tester);
    handle.dispose();
  });
}
