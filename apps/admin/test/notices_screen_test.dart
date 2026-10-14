import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/admin_async_states.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/app/notices_screen.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

import 'support/failing_admin_data_source.dart';
import 'support/layout_harness.dart';

/// Aba "Avisos" (#46). Dados sintéticos.
final _agora = DateTime(2026, 10, 14, 9);

/// Devolve itens forjados (ex.: enviado) e conta/segura os cancelamentos.
class _FakeAvisos extends MockAdminDataSource {
  _FakeAvisos(this.itens) : super(now: () => _agora);

  final List<NoticeHistoryItem> itens;
  final List<String> cancelados = [];
  Completer<void>? portao;
  Object? erroNoCancelamento;
  Object? erroNaCarga;
  final List<(String, String)> acessos = [];
  final List<(int, int)> leituras = [];

  @override
  Future<void> recordAccess({required String actionType, required String resourceType}) async {
    acessos.add((actionType, resourceType));
  }

  @override
  Future<List<NoticeHistoryItem>> fetchNoticeHistory({String? microAreaId, int limit = 50, int offset = 0}) async =>
      _ler(limit, offset);

  Future<List<NoticeHistoryItem>> _ler(int limit, int offset) async {
    leituras.add((limit, offset));
    final erro = erroNaCarga;
    if (erro != null) throw erro;
    return [for (final i in itens) i];
  }

  @override
  Future<void> cancelScheduledNotice(String id) async {
    cancelados.add(id);
    final erro = erroNoCancelamento;
    if (erro != null) throw erro;
    if (portao != null) await portao!.future;
    final i = itens.indexWhere((a) => a.id == id);
    final a = itens[i];
    itens[i] = _item(id, status: NoticeStatus.cancelled, titulo: a.title);
  }
}

NoticeHistoryItem _item(
  String id, {
  required NoticeStatus status,
  String titulo = 'Vacinação na quinta',
  int? recipients,
  int? accepted,
  String? failureReason,
}) =>
    NoticeHistoryItem(
      id: id,
      microAreaId: 'ma-1',
      microAreaName: 'Microárea 01',
      audience: NoticeAudience.chronic,
      title: titulo,
      status: status,
      scheduledFor: DateTime(2026, 10, 15, 8, 30),
      createdByLabel: 'ADM-001',
      recipients: recipients,
      accepted: accepted,
      failureReason: failureReason,
    );

Future<void> _abrir(WidgetTester tester, AdminDataSource fonte, {String role = 'admin', VoidCallback? aoVencer, bool assentar = true}) async {
  redimensionar(tester, const Size(1024, 900));
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAdminTheme(),
      home: Scaffold(
        body: AdminSessionScope(
          aoVencer: aoVencer ?? () {},
          child: NoticesScreen(dataSource: fonte, role: role, now: () => _agora),
        ),
      ),
    ),
  );
  // Sessão vencida deixa um spinner girando: pumpAndSettle nunca assentaria.
  if (assentar) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
}

Future<void> _tocar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pumpAndSettle();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

void main() {
  test('noticeStatusLabel cobre os 6 status', () {
    expect(noticeStatusLabel(NoticeStatus.pending), 'Agendado');
    expect(noticeStatusLabel(NoticeStatus.sending), 'Enviando');
    expect(noticeStatusLabel(NoticeStatus.sent), 'Enviado');
    expect(noticeStatusLabel(NoticeStatus.unknown), 'Resultado desconhecido — confira antes de reenviar');
    expect(noticeStatusLabel(NoticeStatus.failed), 'Falhou');
    expect(noticeStatusLabel(NoticeStatus.cancelled), 'Cancelado');
  });

  testWidgets('coordenador não vê a sub-aba Termos; admin vê', (tester) async {
    await _abrir(tester, MockAdminDataSource(now: () => _agora), role: 'coordinator');
    expect(find.byKey(const Key('notices_tab_history')), findsOneWidget);
    expect(find.byKey(const Key('notices_tab_terms')), findsNothing);
    await _abrir(tester, MockAdminDataSource(now: () => _agora), role: 'admin');
    expect(find.byKey(const Key('notices_tab_terms')), findsOneWidget);
    expect(find.byKey(const Key('notice_new_button')), findsOneWidget);
  });

  testWidgets('histórico: título, microárea, status e contagens; a mensagem nunca aparece', (tester) async {
    final fonte = _FakeAvisos([]);
    final area = (await fonte.fetchMicroAreas()).first;
    await fonte.scheduleNotice(
      microAreaId: area.id,
      audience: NoticeAudience.everyone,
      title: 'Aviso do mock',
      message: 'SEGREDO-NAO-EXIBIR',
      scheduledFor: _agora.add(const Duration(hours: 2)),
    );
    fonte.itens.add(_item('n-sent', status: NoticeStatus.sent, recipients: 3, accepted: 2));
    fonte.itens.add(_item('n-fail', status: NoticeStatus.failed, titulo: 'Outro', failureReason: 'FCM indisponível'));
    await _abrir(tester, fonte);

    expect(find.byKey(const Key('notice_row_n-sent')), findsOneWidget);
    expect(find.text('Vacinação na quinta'), findsOneWidget);
    expect(find.textContaining('Microárea 01'), findsWidgets);
    expect(find.text('Enviado'), findsOneWidget);
    expect(find.textContaining('2 de 3'), findsOneWidget);
    expect(find.textContaining('15/10/2026 08:30'), findsWidgets);
    expect(find.textContaining('FCM indisponível'), findsOneWidget);
    expect(find.textContaining('ADM-001'), findsWidgets);
    expect(find.textContaining('SEGREDO'), findsNothing);
  });

  testWidgets('histórico do mock puro não expõe a mensagem', (tester) async {
    final fonte = MockAdminDataSource(now: () => _agora);
    final area = (await fonte.fetchMicroAreas()).first;
    await fonte.scheduleNotice(
      microAreaId: area.id,
      audience: NoticeAudience.everyone,
      title: 'Aviso do mock',
      message: 'SEGREDO-NAO-EXIBIR',
      scheduledFor: _agora.add(const Duration(hours: 2)),
    );
    await _abrir(tester, fonte);
    expect(find.text('Aviso do mock'), findsOneWidget);
    expect(find.text('Agendado'), findsOneWidget);
    expect(find.textContaining('SEGREDO'), findsNothing);
  });

  testWidgets('pendente tem Cancelar com confirmação e atualiza o selo; enviado não tem', (tester) async {
    final fonte = _FakeAvisos([
      _item('n-pend', status: NoticeStatus.pending),
      _item('n-sent', status: NoticeStatus.sent, recipients: 3, accepted: 2),
    ]);
    await _abrir(tester, fonte);

    expect(find.byKey(const Key('notice_cancel_n-sent')), findsNothing);
    await _tocar(tester, find.byKey(const Key('notice_cancel_n-pend')));
    // Diálogo de confirmação: nada foi chamado ainda.
    expect(fonte.cancelados, isEmpty);
    await _tocar(tester, find.byKey(const Key('notice_cancel_confirm')));

    expect(fonte.cancelados, ['n-pend']);
    expect(find.text('Aviso cancelado.'), findsOneWidget);
    expect(find.text('Cancelado'), findsOneWidget);
    expect(find.byKey(const Key('notice_cancel_n-pend')), findsNothing);
  });

  testWidgets('duplo toque em confirmar chama o cancelamento uma única vez', (tester) async {
    final fonte = _FakeAvisos([_item('n-pend', status: NoticeStatus.pending)])..portao = Completer<void>();
    await _abrir(tester, fonte);

    await _tocar(tester, find.byKey(const Key('notice_cancel_n-pend')));
    final confirmar = find.byKey(const Key('notice_cancel_confirm'));
    await tester.tap(confirmar);
    await tester.pump();
    // O diálogo fecha; um segundo toque no botão da linha é ignorado (desabilitado).
    await tester.pump(const Duration(milliseconds: 400));
    final botao = tester.widget<OutlinedButton>(find.byKey(const Key('notice_cancel_n-pend')));
    expect(botao.onPressed, isNull);
    expect(fonte.cancelados, ['n-pend']);

    fonte.portao!.complete();
    await tester.pumpAndSettle();
    expect(fonte.cancelados, ['n-pend']);
  });

  testWidgets('AdminValidationFailure no cancelamento mostra a mensagem do servidor', (tester) async {
    final fonte = _FakeAvisos([_item('n-pend', status: NoticeStatus.pending)])
      ..erroNoCancelamento = const AdminValidationFailure('Só avisos pendentes podem ser cancelados.');
    await _abrir(tester, fonte);
    await _tocar(tester, find.byKey(const Key('notice_cancel_n-pend')));
    await _tocar(tester, find.byKey(const Key('notice_cancel_confirm')));
    expect(find.text('Só avisos pendentes podem ser cancelados.'), findsOneWidget);
  });

  testWidgets('selos de unknown, failed e cancelled com texto exato e ícone', (tester) async {
    final fonte = _FakeAvisos([
      _item('n-unk', status: NoticeStatus.unknown),
      _item('n-fail', status: NoticeStatus.failed),
      _item('n-can', status: NoticeStatus.cancelled),
      _item('n-sent', status: NoticeStatus.sent),
    ]);
    await _abrir(tester, fonte);
    expect(find.text('Resultado desconhecido — confira antes de reenviar'), findsOneWidget);
    expect(find.text('Falhou'), findsOneWidget);
    expect(find.text('Cancelado'), findsOneWidget);
    for (final (id, icone) in [
      ('n-unk', Icons.help_outline),
      ('n-fail', Icons.error_outline),
      ('n-can', Icons.block),
      ('n-sent', Icons.check_circle_outline),
    ]) {
      expect(find.descendant(of: find.byKey(Key('notice_row_$id')), matching: find.byIcon(icone)), findsOneWidget, reason: id);
    }
  });

  testWidgets('a carga registra o acesso e lê o histórico com limit 50, offset 0', (tester) async {
    final fonte = _FakeAvisos([]);
    await _abrir(tester, fonte);
    expect(fonte.acessos, [('view', 'community_notices')]);
    expect(fonte.leituras, [(50, 0)]);
  });

  testWidgets('AdminSessionExpired na carga chama o callback da sessão', (tester) async {
    var chamadas = 0;
    final fonte = _FakeAvisos([])..erroNaCarga = const AdminSessionExpired();
    await _abrir(tester, fonte, aoVencer: () => chamadas++, assentar: false);
    expect(chamadas, greaterThanOrEqualTo(1));
  });

  testWidgets('AdminSessionExpired no cancelamento chama o callback da sessão', (tester) async {
    var chamadas = 0;
    final fonte = _FakeAvisos([_item('n-pend', status: NoticeStatus.pending)])
      ..erroNoCancelamento = const AdminSessionExpired();
    await _abrir(tester, fonte, aoVencer: () => chamadas++);
    await _tocar(tester, find.byKey(const Key('notice_cancel_n-pend')));
    await _tocar(tester, find.byKey(const Key('notice_cancel_confirm')));
    expect(chamadas, 1);
  });

  testWidgets('histórico vazio mostra mensagem própria', (tester) async {
    await _abrir(tester, MockAdminDataSource(now: () => _agora));
    expect(find.text('Nenhum aviso agendado ou enviado ainda.'), findsOneWidget);
  });

  testWidgets('falha de leitura mostra erro com Tentar novamente', (tester) async {
    final fonte = FailingAdminDataSource(inner: MockAdminDataSource(now: () => _agora))..failNextRecordAccess = true;
    await _abrir(tester, fonte);
    expect(find.text('Não foi possível carregar os avisos.'), findsOneWidget);
    await _tocar(tester, find.text('Tentar novamente'));
    expect(find.text('Nenhum aviso agendado ou enviado ainda.'), findsOneWidget);
  });

  testWidgets('o destino Avisos aparece na navegação do app completo', (tester) async {
    await abrirBackoffice(tester, tamanho: const Size(1024, 900), dataSource: MockAdminDataSource());
    await irPara(tester, 'Avisos');
    expect(find.byKey(const Key('notices_tab_history')), findsOneWidget);
    expect(find.byKey(const Key('notice_new_button')), findsOneWidget);
  });
}
