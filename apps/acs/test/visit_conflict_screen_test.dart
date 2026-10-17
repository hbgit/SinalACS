import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/acs_theme.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/app/visit_conflict_screen.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';

import 'support/fakes.dart';

/// Telas de comparação e decisão do conflito de visita (#79). Fila real sobre
/// armazenamento em memória e resolvedor falso. Ids e pacientes sintéticos.
void main() {
  const localId = 'conflito-1';
  final registradaEm = DateTime(2026, 10, 10, 9, 30);

  OfflineVisitRecord emConflito({
    String id = localId,
    int n = 1,
    VisitConflictSnapshot? servidor,
    bool semCopia = false,
  }) =>
      OfflineVisitRecord(
        localId: id,
        patientId: syntheticPatientId(n),
        risk: 'yellow',
        status: 'PENDENTE',
        outcome: 'Realizada com sucesso',
        notes: 'obs igual',
        createdAt: registradaEm,
        conflictServerVersion: 3,
        conflictServer: semCopia
            ? null
            : servidor ??
                VisitConflictSnapshot(
                  version: 3,
                  status: 'Paciente ausente',
                  notes: 'obs igual',
                  completedAt: registradaEm.toUtc(),
                ),
      );

  Future<({OfflineVisitQueue fila, InMemoryVisitStore store, FakeVisitConflictResolver resolvedor})> montarFila(
    List<OfflineVisitRecord> visitas,
  ) async {
    final store = InMemoryVisitStore();
    await store.save(visitas);
    final resolvedor = FakeVisitConflictResolver();
    final fila = OfflineVisitQueue(store: store, conflictResolver: resolvedor);
    await fila.restore();
    return (fila: fila, store: store, resolvedor: resolvedor);
  }

  Future<void> abrir(WidgetTester tester, Widget tela, {Size tamanho = const Size(360, 800)}) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = tamanho;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildAcsDarkTheme(), home: tela));
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, Finder alvo) async {
    await tester.ensureVisible(alvo);
    await tester.pumpAndSettle();
    await tester.tap(alvo);
    await tester.pumpAndSettle();
  }

  /// Lista com uma visita em conflito, já aberta na comparação.
  Future<void> abrirComparacaoPelaLista(WidgetTester tester, OfflineVisitQueue fila) async {
    await abrir(tester, VisitConflictListScreen(queue: fila));
    await tocar(tester, find.byKey(const Key('conflict_item_$localId')));
    expect(find.byType(VisitConflictCompareScreen), findsOneWidget);
  }

  testWidgets('botão Resolver conflito(s) só aparece com conflito e abre a lista', (tester) async {
    final store = InMemoryVisitStore();
    final fila = OfflineVisitQueue(
      store: store,
      synchronizer: FakeVisitSynchronizer(statusFor: (_) => 'conflict'),
      conflictResolver: FakeVisitConflictResolver(),
    );
    await fila.add(OfflineVisitRecord(
      localId: localId,
      patientId: syntheticPatientId(1),
      risk: 'yellow',
      status: 'PENDENTE',
      outcome: 'Realizada com sucesso',
    ));
    await abrir(
      tester,
      // No app a tela vive dentro do Scaffold do painel.
      Scaffold(body: VisitRegistrationScreen(queue: fila, alert: testAlert(alertId: 'alerta-1', riskLevel: 'yellow'))),
    );
    expect(find.byKey(const Key('resolve_conflicts')), findsNothing);

    await tocar(tester, find.byKey(const Key('sync_visits')));

    expect(
      find.text('1 visita(s) em conflito com o servidor. Toque em "Resolver conflito(s)" para comparar e escolher.'),
      findsOneWidget,
    );
    // O SnackBar cobre o pé da tela; espera ele sair antes de tocar.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final botao = find.byKey(const Key('resolve_conflicts'));
    expect(botao, findsOneWidget);
    expect(find.descendant(of: botao, matching: find.text('Resolver conflito(s)')), findsOneWidget);
    await tocar(tester, botao);

    expect(find.byType(VisitConflictListScreen), findsOneWidget);
    expect(find.text('Visitas em conflito'), findsOneWidget);
    final item = find.byKey(const Key('conflict_item_$localId'));
    expect(item, findsOneWidget);
    expect(find.descendant(of: item, matching: find.text('Paciente ${syntheticPatientId(1).substring(0, 8)}')),
        findsOneWidget);
  });

  testWidgets('lista vazia avisa e volta ao registro com o contador atualizado', (tester) async {
    final (:fila, store: _, resolvedor: _) = await montarFila([emConflito()]);
    await abrir(
      tester,
      // No app a tela vive dentro do Scaffold do painel.
      Scaffold(body: VisitRegistrationScreen(queue: fila, alert: testAlert(alertId: 'alerta-1', riskLevel: 'yellow'))),
    );
    await tocar(tester, find.byKey(const Key('resolve_conflicts')));
    await tocar(tester, find.byKey(const Key('conflict_item_$localId')));
    await tocar(tester, find.byKey(const Key('conflict_keep_server')));
    await tocar(tester, find.byKey(const Key('confirm_keep_server')));

    expect(find.text('Nenhuma visita em conflito.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(VisitRegistrationScreen), findsOneWidget);
    expect(find.byKey(const Key('conflict_visits_count')), findsNothing);
    expect(find.byKey(const Key('resolve_conflicts')), findsNothing);
  });

  testWidgets('comparação mostra os dois lados e marca o que difere', (tester) async {
    final semantica = tester.ensureSemantics();
    try {
      final (:fila, store: _, resolvedor: _) = await montarFila([emConflito()]);
      await abrir(tester, VisitConflictCompareScreen(queue: fila, localId: localId));

      final local = find.byKey(const Key('conflict_local'));
      final servidor = find.byKey(const Key('conflict_server'));
      expect(find.descendant(of: local, matching: find.text('Neste aparelho')), findsOneWidget);
      expect(find.descendant(of: servidor, matching: find.text('No servidor (versão 3)')), findsOneWidget);
      expect(find.descendant(of: local, matching: find.text('Realizada com sucesso')), findsOneWidget);
      expect(find.descendant(of: servidor, matching: find.text('Paciente ausente')), findsOneWidget);
      expect(find.descendant(of: local, matching: find.text('10/10/2026 09:30')), findsOneWidget);
      expect(find.descendant(of: servidor, matching: find.text('10/10/2026 09:30')), findsOneWidget,
          reason: 'hora local, não UTC');

      final status = find.byKey(const Key('conflict_diff_status'));
      expect(status, findsOneWidget);
      expect(find.descendant(of: status, matching: find.text('Diferente')), findsOneWidget);
      expect(find.descendant(of: status, matching: find.byIcon(Icons.compare_arrows)), findsOneWidget);
      expect(find.bySemanticsLabel('Status do atendimento diferente entre aparelho e servidor'), findsOneWidget);
      final texto = tester.widget<Text>(find.descendant(of: status, matching: find.text('Diferente')));
      expect(texto.style?.color, AcsRiskColors.dark.accentOnSurface);

      expect(find.byKey(const Key('conflict_diff_notes')), findsNothing, reason: 'observações iguais');
      expect(find.byKey(const Key('conflict_diff_completed')), findsNothing, reason: 'mesma data');
      expect(find.text('Diferente'), findsOneWidget);
    } finally {
      semantica.dispose();
    }
  });

  testWidgets('observações vazias aparecem como "Sem observações"', (tester) async {
    final (:fila, store: _, resolvedor: _) = await montarFila([
      emConflito(servidor: const VisitConflictSnapshot(version: 3, status: 'Realizada com sucesso', notes: '')),
    ]);
    await abrir(tester, VisitConflictCompareScreen(queue: fila, localId: localId));

    expect(
      find.descendant(of: find.byKey(const Key('conflict_server')), matching: find.text('Sem observações')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('conflict_diff_notes')), findsOneWidget);
    expect(find.byKey(const Key('conflict_diff_status')), findsNothing);
  });

  testWidgets('Manter a do servidor pede confirmação; cancelar não apaga', (tester) async {
    final (:fila, :store, resolvedor: _) = await montarFila([emConflito()]);
    await abrir(tester, VisitConflictCompareScreen(queue: fila, localId: localId));

    await tocar(tester, find.byKey(const Key('conflict_keep_server')));
    expect(find.text('Descartar a versão deste aparelho?'), findsOneWidget);
    expect(
      find.text('A visita registrada neste aparelho será apagada e a do servidor continua valendo. '
          'Isso não pode ser desfeito.'),
      findsOneWidget,
    );
    final confirmar = tester.widget<Text>(
      find.descendant(of: find.byKey(const Key('confirm_keep_server')), matching: find.text('Descartar a minha')),
    );
    expect(confirmar.style?.color, AcsRiskColors.dark.redOnSurface);

    await tocar(tester, find.byKey(const Key('cancel_keep_server')));

    expect(fila.conflictCount, 1);
    expect(await store.load(), hasLength(1));
    expect(find.byType(VisitConflictCompareScreen), findsOneWidget);
  });

  testWidgets('Manter a do servidor: confirmar remove a visita', (tester) async {
    final (:fila, :store, :resolvedor) = await montarFila([emConflito()]);
    await abrirComparacaoPelaLista(tester, fila);

    await tocar(tester, find.byKey(const Key('conflict_keep_server')));
    await tocar(tester, find.byKey(const Key('confirm_keep_server')));

    expect(fila.conflictCount, 0);
    expect(await store.load(), isEmpty);
    expect(resolvedor.chamadas, isEmpty, reason: 'só local (D4): o servidor não é chamado');
    expect(find.byType(VisitConflictCompareScreen), findsNothing);
    expect(find.text('Nenhuma visita em conflito.'), findsOneWidget);
  });

  testWidgets('Manter a minha envia com a versão vista e volta à lista', (tester) async {
    final (:fila, :store, :resolvedor) = await montarFila([emConflito()]);
    await abrirComparacaoPelaLista(tester, fila);

    await tocar(tester, find.byKey(const Key('conflict_keep_local')));

    final chamada = resolvedor.chamadas.single;
    expect(chamada.expectedServerVersion, 3, reason: 'a versão do servidor que o ACS viu');
    expect(chamada.visit.outcome, 'Realizada com sucesso');
    expect(chamada.visit.notes, 'obs igual');
    expect(find.byType(VisitConflictCompareScreen), findsNothing);
    expect(find.byType(VisitConflictListScreen), findsOneWidget);
    expect(find.text('Versão do aparelho enviada ao servidor.'), findsOneWidget);
    expect(find.text('Nenhuma visita em conflito.'), findsOneWidget);
    expect(await store.load(), isEmpty);
  });

  testWidgets('Editar e enviar manda o status e as observações editados', (tester) async {
    final (:fila, store: _, :resolvedor) = await montarFila([emConflito()]);
    await abrirComparacaoPelaLista(tester, fila);

    await tocar(tester, find.byKey(const Key('conflict_edit')));
    final notas = find.byKey(const Key('conflict_edit_notes'));
    expect(tester.widget<TextField>(notas).controller!.text, 'obs igual', reason: 'pré-preenchido com o do aparelho');
    expect(find.descendant(of: find.byKey(const Key('conflict_edit_outcome')), matching: find.text('Realizada com sucesso')),
        findsOneWidget);

    await tocar(tester, find.byKey(const Key('conflict_edit_outcome')));
    await tester.tap(find.text('Recusou atendimento').last);
    await tester.pumpAndSettle();
    await tester.enterText(notas, '  editada  ');
    await tocar(tester, find.byKey(const Key('conflict_send_edited')));

    final chamada = resolvedor.chamadas.single;
    expect(chamada.visit.outcome, 'Recusou atendimento');
    expect(chamada.visit.notes, 'editada');
    expect(chamada.expectedServerVersion, 3);
    expect(find.text('Versão do aparelho enviada ao servidor.'), findsOneWidget);
  });

  testWidgets('conflito novo atualiza o painel do servidor e avisa', (tester) async {
    final (:fila, store: _, :resolvedor) = await montarFila([emConflito()]);
    resolvedor.resposta = (visit, _) async => VisitSyncOutcome(
          localId: visit.localId,
          status: 'conflict',
          serverVersion: 5,
          serverSnapshot: const VisitConflictSnapshot(version: 5, status: 'Recusou atendimento', notes: 'outra'),
        );
    await abrirComparacaoPelaLista(tester, fila);

    await tocar(tester, find.byKey(const Key('conflict_keep_local')));

    expect(find.byType(VisitConflictCompareScreen), findsOneWidget);
    final servidor = find.byKey(const Key('conflict_server'));
    expect(find.descendant(of: servidor, matching: find.text('No servidor (versão 5)')), findsOneWidget);
    expect(find.descendant(of: servidor, matching: find.text('Recusou atendimento')), findsOneWidget);
    expect(find.byKey(const Key('conflict_diff_notes')), findsOneWidget);
    final aviso = find.byKey(const Key('conflict_status'));
    expect(find.descendant(of: aviso, matching: find.text('A visita mudou de novo no servidor. Compare outra vez antes de decidir.')),
        findsOneWidget);
    expect(fila.conflictVisits.single.conflictServerVersion, 5);
  });

  testWidgets('falha de rede mantém a visita e mostra o motivo', (tester) async {
    final (:fila, :store, :resolvedor) = await montarFila([emConflito()]);
    resolvedor.resposta = (_, __) async => throw const BackendFailure('Sem conexão com o servidor.');
    await abrirComparacaoPelaLista(tester, fila);

    await tocar(tester, find.byKey(const Key('conflict_keep_local')));

    expect(find.byType(VisitConflictCompareScreen), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('conflict_status')), matching: find.text('Sem conexão com o servidor.')),
        findsOneWidget);
    expect(fila.conflictCount, 1);
    expect((await store.load()).single.inConflict, isTrue);
    final status = tester.widget<Semantics>(find.ancestor(
      of: find.text('Sem conexão com o servidor.'),
      matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true),
    ).first);
    expect(status.properties.liveRegion, isTrue);
  });

  testWidgets('recusa do servidor volta à lista com o motivo', (tester) async {
    final (:fila, store: _, :resolvedor) = await montarFila([emConflito()]);
    resolvedor.resposta = (visit, _) async => VisitSyncOutcome(
          localId: visit.localId,
          status: 'rejected',
          message: 'paciente fora da sua microárea',
        );
    await abrirComparacaoPelaLista(tester, fila);

    await tocar(tester, find.byKey(const Key('conflict_keep_local')));

    expect(find.byType(VisitConflictCompareScreen), findsNothing);
    expect(find.text('O servidor recusou esta visita: paciente fora da sua microárea'), findsOneWidget);
    expect(fila.rejectedCount, 1);
  });

  testWidgets('botões ficam desabilitados com a chamada em voo', (tester) async {
    final (:fila, store: _, :resolvedor) = await montarFila([emConflito()]);
    final portao = Completer<void>();
    resolvedor.portao = portao;
    await abrir(tester, VisitConflictCompareScreen(queue: fila, localId: localId));

    await tester.ensureVisible(find.byKey(const Key('conflict_keep_local')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conflict_keep_local')));
    await tester.pump();

    for (final chave in ['conflict_keep_local', 'conflict_edit', 'conflict_keep_server']) {
      final botao = tester.widget<ButtonStyleButton>(find.byKey(Key(chave)));
      expect(botao.onPressed, isNull, reason: '$chave com a chamada em voo');
    }
    await tester.tap(find.byKey(const Key('conflict_keep_local')), warnIfMissed: false);
    await tester.pump();
    expect(resolvedor.chamadas, hasLength(1), reason: 'sem duplo envio');

    portao.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('sem cópia do servidor mostra o aviso e mantém as ações', (tester) async {
    final (:fila, store: _, :resolvedor) = await montarFila([emConflito(semCopia: true)]);
    await abrir(tester, VisitConflictCompareScreen(queue: fila, localId: localId));

    final servidor = find.byKey(const Key('conflict_server'));
    expect(find.descendant(of: servidor, matching: find.text('No servidor (versão 3)')), findsOneWidget);
    expect(find.descendant(of: servidor, matching: find.text('Conteúdo do servidor indisponível neste aparelho.')),
        findsOneWidget);
    expect(find.text('Diferente'), findsNothing);
    for (final chave in ['conflict_keep_local', 'conflict_edit', 'conflict_keep_server']) {
      final botao = tester.widget<ButtonStyleButton>(find.byKey(Key(chave)));
      expect(botao.onPressed, isNotNull, reason: chave);
      expect(tester.getSize(find.byKey(Key(chave))).height, greaterThanOrEqualTo(48));
    }

    await tocar(tester, find.byKey(const Key('conflict_keep_local')));
    expect(resolvedor.chamadas.single.expectedServerVersion, 3);
  });

  testWidgets('largura de celular empilha os painéis', (tester) async {
    final (:fila, store: _, resolvedor: _) = await montarFila([emConflito()]);
    await abrir(tester, VisitConflictCompareScreen(queue: fila, localId: localId), tamanho: const Size(360, 800));

    final local = tester.getRect(find.byKey(const Key('conflict_local')));
    final servidor = tester.getRect(find.byKey(const Key('conflict_server')));
    expect(servidor.top, greaterThanOrEqualTo(local.bottom), reason: 'servidor abaixo do aparelho');
  });

  testWidgets('largura de tablet põe os painéis lado a lado', (tester) async {
    final (:fila, store: _, resolvedor: _) = await montarFila([emConflito()]);
    await abrir(tester, VisitConflictCompareScreen(queue: fila, localId: localId), tamanho: const Size(800, 1000));

    final local = tester.getRect(find.byKey(const Key('conflict_local')));
    final servidor = tester.getRect(find.byKey(const Key('conflict_server')));
    expect(servidor.top, local.top);
    expect(servidor.left, greaterThanOrEqualTo(local.right));
  });
}
