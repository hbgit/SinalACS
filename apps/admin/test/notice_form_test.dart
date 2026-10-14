import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/admin_async_states.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/app/notices_screen.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

import 'support/layout_harness.dart';

/// Formulário de agendamento de aviso (#46). Dados sintéticos.
final _agora = DateTime(2026, 10, 14, 9);

class _Agendamento {
  _Agendamento(this.microAreaId, this.audience, this.title, this.message, this.scheduledFor);
  final String microAreaId;
  final NoticeAudience audience;
  final String title;
  final String message;
  final DateTime scheduledFor;
}

class _FakeAgendamento extends MockAdminDataSource {
  _FakeAgendamento() : super(now: () => _agora);

  final List<_Agendamento> agendados = [];
  Completer<void>? portao;
  Object? erro;
  bool semAreas = false;

  @override
  Future<List<MicroAreaSummary>> fetchMicroAreas() async => semAreas ? const [] : super.fetchMicroAreas();

  @override
  Future<String> scheduleNotice({
    required String microAreaId,
    required NoticeAudience audience,
    required String title,
    required String message,
    required DateTime scheduledFor,
  }) async {
    agendados.add(_Agendamento(microAreaId, audience, title, message, scheduledFor));
    if (portao != null) await portao!.future;
    final e = erro;
    if (e != null) throw e;
    return super.scheduleNotice(
      microAreaId: microAreaId,
      audience: audience,
      title: title,
      message: message,
      scheduledFor: scheduledFor,
    );
  }
}

Future<void> _abrir(
  WidgetTester tester,
  AdminDataSource fonte, {
  DateTime Function()? relogio,
  VoidCallback? aoVencer,
}) async {
  redimensionar(tester, const Size(1024, 1000));
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAdminTheme(),
      home: Scaffold(
        body: AdminSessionScope(
          aoVencer: aoVencer ?? () {},
          child: NoticesScreen(dataSource: fonte, role: 'admin', now: relogio ?? () => _agora),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('notice_new_button')));
  await tester.pumpAndSettle();
}

Future<void> _preencher(WidgetTester tester, {String titulo = '  Vacinação  ', String mensagem = '  Traga a caderneta.  '}) async {
  await tester.enterText(find.byKey(const Key('notice_title')), titulo);
  await tester.enterText(find.byKey(const Key('notice_message')), mensagem);
  await tester.pumpAndSettle();
}

FilledButton _submit(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(const Key('notice_submit')));

void main() {
  testWidgets('enviar fica desabilitado com campos vazios e habilita com título e mensagem; limites 60/240', (tester) async {
    await _abrir(tester, _FakeAgendamento());
    expect(_submit(tester).onPressed, isNull);
    expect(find.text('0/60'), findsOneWidget);
    expect(find.text('0/240'), findsOneWidget);
    expect(find.text('O texto do aviso não é gravado na trilha de auditoria.'), findsOneWidget);
    await _preencher(tester);
    expect(_submit(tester).onPressed, isNotNull);
    await tester.enterText(find.byKey(const Key('notice_title')), '   ');
    await tester.pumpAndSettle();
    expect(_submit(tester).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('notice_title')), 'x' * 61);
    await tester.pumpAndSettle();
    expect(find.text('60/60'), findsOneWidget);
  });

  testWidgets('horário a menos de 1 minuto: mostra erro e não chama scheduleNotice', (tester) async {
    var agora = _agora;
    final fonte = _FakeAgendamento();
    await _abrir(tester, fonte, relogio: () => agora);
    await _preencher(tester);
    // O padrão (10:00) fica a menos de 1 minuto do relógio.
    agora = DateTime(2026, 10, 14, 9, 59, 30);
    await tester.tap(find.byKey(const Key('notice_submit')));
    await tester.pumpAndSettle();
    expect(find.text('O horário do aviso deve ser pelo menos 1 minuto à frente.'), findsOneWidget);
    expect(fonte.agendados, isEmpty);
    expect(find.byKey(const Key('notice_title')), findsOneWidget);
  });

  testWidgets('envio válido: uma chamada com os valores escolhidos, fecha e recarrega o histórico', (tester) async {
    final fonte = _FakeAgendamento();
    await _abrir(tester, fonte);
    expect(find.text('Envio em 14/10/2026 10:00'), findsOneWidget);
    await tester.tap(find.text('Só crônicos'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notice_area')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Microárea 07').last);
    await tester.pumpAndSettle();
    await _preencher(tester);
    // Hora: abre o seletor e confirma com OK; a data fica a do padrão.
    await tester.tap(find.byKey(const Key('notice_date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notice_submit')));
    await tester.pumpAndSettle();

    expect(fonte.agendados, hasLength(1));
    final a = fonte.agendados.single;
    expect(a.microAreaId, 'ma-07');
    expect(a.audience, NoticeAudience.chronic);
    expect(a.title, 'Vacinação');
    expect(a.message, 'Traga a caderneta.');
    expect(a.scheduledFor, DateTime(2026, 10, 14, 10));
    expect(find.byKey(const Key('notice_submit')), findsNothing);
    expect(find.text('Aviso agendado.'), findsOneWidget);
    expect(find.text('Vacinação'), findsOneWidget);
    // (h) a mensagem digitada não aparece no histórico.
    expect(find.textContaining('caderneta'), findsNothing);
  });

  testWidgets('duplo toque em Agendar chama o data source uma única vez', (tester) async {
    final fonte = _FakeAgendamento()..portao = Completer<void>();
    await _abrir(tester, fonte);
    await _preencher(tester);
    final botao = find.byKey(const Key('notice_submit'));
    await tester.tap(botao);
    await tester.tap(botao, warnIfMissed: false);
    await tester.pump();
    expect(fonte.agendados, hasLength(1));
    fonte.portao!.complete();
    await tester.pumpAndSettle();
    expect(fonte.agendados, hasLength(1));
  });

  testWidgets('AdminValidationFailure aparece no diálogo, que continua aberto', (tester) async {
    final fonte = _FakeAgendamento()..erro = const AdminValidationFailure('Microárea não encontrada.');
    await _abrir(tester, fonte);
    await _preencher(tester);
    await tester.tap(find.byKey(const Key('notice_submit')));
    await tester.pumpAndSettle();
    expect(find.text('Microárea não encontrada.'), findsOneWidget);
    expect(find.byKey(const Key('notice_submit')), findsOneWidget);
    expect(_submit(tester).onPressed, isNotNull);
  });

  testWidgets('erro genérico mostra a mensagem fixa dentro do diálogo', (tester) async {
    final fonte = _FakeAgendamento()..erro = StateError('boom');
    await _abrir(tester, fonte);
    await _preencher(tester);
    await tester.tap(find.byKey(const Key('notice_submit')));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível agendar o aviso agora.'), findsOneWidget);
  });

  testWidgets('AdminSessionExpired aciona o callback do AdminSessionScope', (tester) async {
    var chamadas = 0;
    final fonte = _FakeAgendamento()..erro = const AdminSessionExpired();
    await _abrir(tester, fonte, aoVencer: () => chamadas++);
    await _preencher(tester);
    await tester.tap(find.byKey(const Key('notice_submit')));
    await tester.pumpAndSettle();
    expect(chamadas, 1);
  });

  testWidgets('sem microáreas: mostra a mensagem e desabilita o envio', (tester) async {
    await _abrir(tester, _FakeAgendamento()..semAreas = true);
    expect(find.text('Nenhuma microárea disponível.'), findsOneWidget);
    expect(_submit(tester).onPressed, isNull);
  });
}
