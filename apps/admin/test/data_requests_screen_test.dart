import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/app/data_requests_screen.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

import 'support/failing_admin_data_source.dart';
import 'support/fake_admin_auth.dart';
import 'support/layout_harness.dart';

/// Tela "Pedidos do titular" (#42). Dados sintéticos: nenhum paciente real.
final _agora = DateTime(2026, 10, 8, 12);

DataRequestDetail _pedido(
  String id, {
  required DataRequestType type,
  DataRequestStatus status = DataRequestStatus.open,
  required DateTime dueAt,
  bool overdue = false,
  String label = 'Paciente #A18F',
  String? details,
  String? resolution,
  DateTime? decidedAt,
}) => DataRequestDetail(
  id: id,
  type: type,
  status: status,
  createdAt: dueAt.subtract(const Duration(days: 15)),
  dueAt: dueAt,
  overdue: overdue,
  patientLabel: label,
  details: details,
  resolution: resolution,
  decidedAt: decidedAt,
);

/// Fonte falsa que grava cada chamada de pedido do titular. O resto do contrato
/// vem do mock (não é exercitado aqui).
class _FakePedidos extends MockAdminDataSource {
  _FakePedidos(this.pedidos);

  final List<DataRequestDetail> pedidos;
  final List<String> detalhesLidos = [];
  final List<String> analisesIniciadas = [];
  final List<(String, String?)> atendidos = [];
  final List<(String, String)> recusados = [];
  int listagens = 0;

  /// Quando não é `null`, as decisões esperam por ele: prova o duplo toque.
  Completer<void>? portao;

  /// Lançada (uma vez) pela próxima decisão.
  Object? erroNaDecisao;

  Future<void> _decisao() async {
    final erro = erroNaDecisao;
    if (erro != null) {
      erroNaDecisao = null;
      throw erro;
    }
    if (portao != null) await portao!.future;
  }

  @override
  Future<List<DataRequestSummary>> fetchDataRequests({DataRequestStatus? status, int limit = 50, int offset = 0}) async {
    listagens++;
    return [
      for (final p in pedidos)
        if (status == null || p.status == status) p,
    ];
  }

  @override
  Future<DataRequestDetail> fetchDataRequest(String id) async {
    detalhesLidos.add(id);
    return pedidos.firstWhere((p) => p.id == id);
  }

  @override
  Future<void> startDataRequestReview(String id) async {
    await _decisao();
    analisesIniciadas.add(id);
  }

  @override
  Future<void> completeDataRequest(String id, {String? note}) async {
    await _decisao();
    atendidos.add((id, note));
  }

  @override
  Future<void> rejectDataRequest(String id, {required String reason}) async {
    await _decisao();
    recusados.add((id, reason));
  }
}

Future<void> _abrir(WidgetTester tester, AdminDataSource fonte, {Size tamanho = const Size(1024, 900)}) async {
  redimensionar(tester, tamanho);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAdminTheme(),
      home: Scaffold(body: DataRequestsScreen(dataSource: fonte, now: () => _agora)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _abrirDetalhe(WidgetTester tester, String id) async {
  final linha = find.byKey(Key('data_request_$id'));
  await tester.ensureVisible(linha);
  await tester.pumpAndSettle();
  await tester.tap(linha);
  await tester.pumpAndSettle();
}

Future<void> _tocar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pumpAndSettle();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

ButtonStyleButton _botao(WidgetTester tester, String chave) =>
    tester.widget<ButtonStyleButton>(find.byKey(Key(chave)));

void main() {
  final vencido = _pedido(
    'req-1',
    type: DataRequestType.correction,
    dueAt: _agora.subtract(const Duration(days: 5, hours: 2)),
    overdue: true,
    details: 'Texto fictício: corrigir o nome social cadastrado.',
  );
  final emAnalise = _pedido(
    'req-2',
    type: DataRequestType.deletion,
    status: DataRequestStatus.inReview,
    dueAt: _agora.add(const Duration(days: 3)),
    label: 'Paciente #7C2E',
  );
  final atendido = _pedido(
    'req-3',
    type: DataRequestType.correction,
    status: DataRequestStatus.completed,
    dueAt: _agora.add(const Duration(days: 9)),
    label: 'Paciente #4D91',
    details: 'Texto fictício: endereço desatualizado.',
    resolution: 'Endereço corrigido pela equipe.',
    decidedAt: _agora.subtract(const Duration(days: 1)),
  );

  testWidgets('fila ordenada por prazo e pedido vencido aparece destacado com texto "Vencido há N dias"', (tester) async {
    await _abrir(tester, _FakePedidos([vencido, emAnalise, atendido]));

    final y1 = tester.getTopLeft(find.byKey(const Key('data_request_req-1'))).dy;
    final y2 = tester.getTopLeft(find.byKey(const Key('data_request_req-2'))).dy;
    final y3 = tester.getTopLeft(find.byKey(const Key('data_request_req-3'))).dy;
    expect(y1, lessThan(y2), reason: 'a ordem do servidor (prazo crescente) é mantida');
    expect(y2, lessThan(y3));

    final linhaVencida = find.byKey(const Key('data_request_req-1'));
    expect(find.descendant(of: linhaVencida, matching: find.text('Vencido há 5 dias')), findsOneWidget);
    expect(find.descendant(of: linhaVencida, matching: find.text('Correção de dados')), findsOneWidget);
    expect(find.descendant(of: linhaVencida, matching: find.text('Paciente #A18F')), findsOneWidget);
    expect(find.descendant(of: linhaVencida, matching: find.text('Aberto')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('data_request_req-2')), matching: find.text('Em análise')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('data_request_req-2')), matching: find.text('Exclusão dos dados')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('data_request_req-3')), matching: find.text('Atendido')), findsOneWidget);
    expect(find.textContaining('Vencido há'), findsOneWidget, reason: 'só o pedido que o servidor marcou como vencido');

    final texto = tester.widget<Text>(find.text('Vencido há 5 dias'));
    expect(texto.style?.color, AdminColors.overdueOnSurface);
  });

  testWidgets('o destaque não depende só de cor: ícone + texto (WCAG 1.4.1)', (tester) async {
    await _abrir(tester, _FakePedidos([vencido, emAnalise]));

    final linhaVencida = find.byKey(const Key('data_request_req-1'));
    final linhaNoPrazo = find.byKey(const Key('data_request_req-2'));
    expect(find.descendant(of: linhaVencida, matching: find.byKey(const Key('overdue_icon'))), findsOneWidget);
    expect(find.descendant(of: linhaVencida, matching: find.textContaining('Vencido há')), findsOneWidget);
    expect(find.descendant(of: linhaNoPrazo, matching: find.byKey(const Key('overdue_icon'))), findsNothing);
    expect(find.descendant(of: linhaNoPrazo, matching: find.textContaining('Vencido')), findsNothing);

    // Leitor de tela: a linha inteira é lida como uma frase que inclui o atraso.
    final semantica = tester.getSemantics(find.descendant(of: linhaVencida, matching: find.byType(MergeSemantics)).first);
    expect(semantica.label, contains('Vencido há 5 dias'));
  });

  testWidgets('detalhe mostra o texto da correção; a lista não mostra', (tester) async {
    final fonte = _FakePedidos([vencido, emAnalise]);
    await _abrir(tester, fonte);

    expect(find.text(vencido.details!), findsNothing);
    expect(fonte.detalhesLidos, isEmpty, reason: 'a lista não lê o detalhe (o texto só é decifrado no detalhe)');

    await _abrirDetalhe(tester, 'req-1');

    expect(fonte.detalhesLidos, ['req-1']);
    expect(find.text(vencido.details!), findsOneWidget);
    expect(find.text('Vencido há 5 dias'), findsOneWidget);

    await _tocar(tester, find.byKey(const Key('data_request_back')));
    expect(find.text(vencido.details!), findsNothing);
    expect(find.byKey(const Key('data_request_req-2')), findsOneWidget);
  });

  testWidgets('"Atender" de correção sem nota fica desabilitado; com nota chama completeDataRequest', (tester) async {
    final fonte = _FakePedidos([vencido]);
    await _abrir(tester, fonte);
    await _abrirDetalhe(tester, 'req-1');

    expect(_botao(tester, 'complete_button').onPressed, isNull);

    await tester.enterText(find.byKey(const Key('resolution_field')), 'ok');
    await tester.pump();
    expect(_botao(tester, 'complete_button').onPressed, isNull, reason: 'menos de 3 caracteres');

    await tester.enterText(find.byKey(const Key('resolution_field')), '   ');
    await tester.pump();
    expect(_botao(tester, 'complete_button').onPressed, isNull, reason: 'só espaços não conta');

    await tester.enterText(find.byKey(const Key('resolution_field')), 'Nome social corrigido no cadastro.');
    await tester.pump();
    expect(_botao(tester, 'complete_button').onPressed, isNotNull);

    // Duplo toque com a chamada pendente: uma só decisão vai ao servidor.
    fonte.portao = Completer<void>();
    final listagensAntes = fonte.listagens;
    await tester.ensureVisible(find.byKey(const Key('complete_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('complete_button')));
    await tester.pump();
    expect(_botao(tester, 'complete_button').onPressed, isNull, reason: 'desabilitado enquanto envia');
    await tester.tap(find.byKey(const Key('complete_button')), warnIfMissed: false);
    await tester.pump();
    fonte.portao!.complete();
    await tester.pumpAndSettle();

    expect(fonte.atendidos, [('req-1', 'Nome social corrigido no cadastro.')]);
    expect(fonte.listagens, greaterThan(listagensAntes), reason: 'a lista é atualizada depois da decisão');
  });

  testWidgets('"Recusar" exige motivo e pede confirmação', (tester) async {
    final fonte = _FakePedidos([emAnalise]);
    await _abrir(tester, fonte);
    await _abrirDetalhe(tester, 'req-2');

    expect(_botao(tester, 'reject_button').onPressed, isNull, reason: 'sem motivo não recusa');

    await tester.enterText(find.byKey(const Key('resolution_field')), 'Dados necessários por obrigação legal.');
    await tester.pump();
    expect(_botao(tester, 'reject_button').onPressed, isNotNull);

    await _tocar(tester, find.byKey(const Key('reject_button')));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(fonte.recusados, isEmpty, reason: 'nada vai ao servidor antes da confirmação');

    // Cancelar não envia.
    await _tocar(tester, find.text('Cancelar'));
    expect(fonte.recusados, isEmpty);

    await _tocar(tester, find.byKey(const Key('reject_button')));
    await _tocar(tester, find.byKey(const Key('confirm_action')));
    expect(fonte.recusados, [('req-2', 'Dados necessários por obrigação legal.')]);
  });

  testWidgets('exclusão pede confirmação explícita citando que é irreversível', (tester) async {
    final fonte = _FakePedidos([emAnalise]);
    await _abrir(tester, fonte);
    await _abrirDetalhe(tester, 'req-2');

    // Exclusão: a nota é opcional, então "Atender" já vem habilitado.
    expect(_botao(tester, 'complete_button').onPressed, isNotNull);
    expect(find.byKey(const Key('start_review_button')), findsNothing, reason: 'já está em análise');

    await _tocar(tester, find.byKey(const Key('complete_button')));
    final dialogo = find.byType(AlertDialog);
    expect(dialogo, findsOneWidget);
    expect(find.descendant(of: dialogo, matching: find.textContaining('irreversível')), findsOneWidget);
    expect(find.descendant(of: dialogo, matching: find.textContaining('anonimiza')), findsOneWidget);
    expect(fonte.atendidos, isEmpty);

    await _tocar(tester, find.byKey(const Key('confirm_action')));
    expect(fonte.atendidos, [('req-2', null)]);
  });

  testWidgets('"Iniciar análise" só aparece no pedido aberto e atualiza o status', (tester) async {
    final fonte = _FakePedidos([vencido]);
    await _abrir(tester, fonte);
    await _abrirDetalhe(tester, 'req-1');

    await _tocar(tester, find.byKey(const Key('start_review_button')));
    expect(fonte.analisesIniciadas, ['req-1']);
    expect(fonte.detalhesLidos, ['req-1', 'req-1'], reason: 'o detalhe é relido para mostrar o novo status');
  });

  testWidgets('pedido decidido não oferece ações e mostra resposta e data da decisão', (tester) async {
    await _abrir(tester, _FakePedidos([atendido]));
    await _abrirDetalhe(tester, 'req-3');

    expect(find.text('Endereço corrigido pela equipe.'), findsOneWidget);
    expect(find.textContaining('Decidido em 07/10/2026'), findsOneWidget);
    expect(find.byKey(const Key('complete_button')), findsNothing);
    expect(find.byKey(const Key('reject_button')), findsNothing);
    expect(find.byKey(const Key('start_review_button')), findsNothing);
  });

  testWidgets('decisão recusada pelo servidor mostra o texto da falha, não envia de novo e atualiza a lista', (tester) async {
    final fonte = _FakePedidos([emAnalise])
      ..erroNaDecisao = const AdminDataFailure('Pedido não encontrado ou já decidido. Atualize a lista.');
    await _abrir(tester, fonte);
    await _abrirDetalhe(tester, 'req-2');
    final listagensAntes = fonte.listagens;

    await _tocar(tester, find.byKey(const Key('complete_button')));
    await _tocar(tester, find.byKey(const Key('confirm_action')));

    expect(find.text('Pedido não encontrado ou já decidido. Atualize a lista.'), findsOneWidget);
    expect(fonte.atendidos, isEmpty);
    expect(fonte.listagens, greaterThan(listagensAntes));
  });

  testWidgets('AdminSessionExpired leva ao login; AdminDataFailure mostra texto e "Tentar novamente"', (tester) async {
    // Falha de leitura: texto próprio e retry que recupera.
    final fonte = FailingAdminDataSource(inner: MockAdminDataSource());
    await abrirBackoffice(tester, tamanho: const Size(1024, 900), dataSource: fonte);
    fonte.nextError = const AdminDataFailure('Não foi possível conectar ao servidor.');
    await irPara(tester, 'Pedidos do titular');

    expect(find.text('Não foi possível conectar ao servidor.'), findsOneWidget);
    await _tocar(tester, find.text('Tentar novamente'));
    expect(find.text('Não foi possível conectar ao servidor.'), findsNothing);
    expect(find.byKey(const Key('data_request_req-a18f')), findsOneWidget);

    // Sessão vencida no meio de uma decisão: volta ao login, sem retry.
    await _abrirDetalhe(tester, 'req-7c2e');
    fonte.nextError = const AdminSessionExpired();
    await _tocar(tester, find.byKey(const Key('start_review_button')));

    expect(find.text('Sessão encerrada. Entre novamente.'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsNothing);
  });

  testWidgets('AdminSessionExpired ao abrir a lista também leva ao login', (tester) async {
    final fonte = FailingAdminDataSource(inner: MockAdminDataSource());
    await tester.pumpWidget(SinalAdminApp(dataSource: fonte, auth: FakeAdminAuth()));
    await entrarComCredenciais(tester);
    fonte.nextError = const AdminSessionExpired();
    await irPara(tester, 'Pedidos do titular');

    expect(find.text('Sessão encerrada. Entre novamente.'), findsOneWidget);
  });

  testWidgets('estado vazio: "Nenhum pedido pendente."', (tester) async {
    await _abrir(tester, _FakePedidos([]));
    expect(find.text('Nenhum pedido pendente.'), findsOneWidget);
  });

  testWidgets('filtro por status pede ao servidor só aquele status', (tester) async {
    await _abrir(tester, _FakePedidos([vencido, emAnalise, atendido]));

    await _tocar(tester, find.byKey(const Key('data_requests_status_filter')));
    await _tocar(tester, find.text('Atendido').last);

    expect(find.byKey(const Key('data_request_req-3')), findsOneWidget);
    expect(find.byKey(const Key('data_request_req-1')), findsNothing);
    expect(find.byKey(const Key('data_request_req-2')), findsNothing);
  });

  testWidgets('nota com <script> é exibida como texto', (tester) async {
    const script = '<script>alert("x")</script>';
    await _abrir(
      tester,
      _FakePedidos([
        _pedido(
          'req-9',
          type: DataRequestType.correction,
          status: DataRequestStatus.rejected,
          dueAt: _agora.add(const Duration(days: 2)),
          details: script,
          resolution: '<b>$script</b>',
          decidedAt: _agora,
        ),
      ]),
    );
    await _abrirDetalhe(tester, 'req-9');

    expect(find.text(script), findsOneWidget);
    expect(find.text('<b>$script</b>'), findsOneWidget);
  });
}
