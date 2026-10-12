import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/admin_async_states.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/app/monitoring_controller.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

import 'support/scripted_pulse_data_source.dart';

/// Mock que conta as chamadas de `escalateAlert` e deixa o teste roteirizar o
/// resultado (atraso, falha, "já escalonado por outro coordenador").
class _Fonte extends MockAdminDataSource {
  _Fonte({super.now});

  final List<(String, EscalationReasonCode)> chamadas = [];
  int buscas = 0;

  /// Quando não nulo, a chamada espera por ele (para provar o duplo toque).
  Completer<void>? segura;

  /// Lançada pela próxima chamada, uma vez.
  Object? falha;

  /// Resultado fixo no lugar do mock (alerta já escalonado por outro).
  EscalationOutcome? resultado;
  final Map<String, DateTime> _sobreposto = {};

  @override
  Future<List<AlertSummary>> fetchAlerts({String? microAreaId, AlertStatus? status, int limit = 50, int offset = 0}) async {
    buscas++;
    final lista = await super.fetchAlerts(microAreaId: microAreaId, status: status, limit: limit, offset: offset);
    return [
      for (final a in lista)
        if (_sobreposto.containsKey(a.id))
          AlertSummary(
            id: a.id,
            patientLabel: a.patientLabel,
            microAreaName: a.microAreaName,
            riskLevel: a.riskLevel,
            status: a.status,
            triggeredAt: a.triggeredAt,
            escalatedAt: _sobreposto[a.id],
          )
        else
          a,
    ];
  }

  @override
  Future<EscalationOutcome> escalateAlert(String alertId, EscalationReasonCode reason) async {
    chamadas.add((alertId, reason));
    final espera = segura;
    if (espera != null) await espera.future;
    final erro = falha;
    if (erro != null) {
      falha = null;
      throw erro;
    }
    final fixo = resultado;
    if (fixo != null) {
      _sobreposto[alertId] = fixo.escalatedAt;
      return fixo;
    }
    return super.escalateAlert(alertId, reason);
  }
}

void main() {
  final agora = DateTime(2026, 10, 11, 9, 5);
  late MonitoringController monitoramento;
  late bool sessaoVencida;

  Future<void> montar(WidgetTester tester, AdminDataSource fonte, {double escala = 1, Size? tamanho}) async {
    sessaoVencida = false;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = tamanho ?? const Size(800, 1600);
    addTearDown(tester.view.reset);
    monitoramento = MonitoringController(dataSource: fonte, now: () => agora);
    await tester.pumpWidget(MaterialApp(
      theme: buildAdminTheme(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(escala), size: tamanho ?? const Size(800, 1600)),
        child: AdminSessionScope(
          aoVencer: () => sessaoVencida = true,
          child: Scaffold(body: AlertsScreen(dataSource: fonte, monitoring: monitoramento)),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  /// Desmonta a tela: o controlador para o timer e nada fica pendente.
  Future<void> encerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    monitoramento.dispose();
  }

  final botao = find.widgetWithText(OutlinedButton, 'Escalonar');
  final confirmar = find.widgetWithText(FilledButton, 'Confirmar escalonamento');

  Future<void> abrirDialogo(WidgetTester tester) async {
    await tester.ensureVisible(botao);
    await tester.pump();
    await tester.tap(botao);
    await tester.pumpAndSettle();
  }

  Future<void> escolherMotivo(WidgetTester tester, EscalationReasonCode m) async {
    await tester.ensureVisible(find.text(m.label));
    await tester.tap(find.text(m.label));
    await tester.pumpAndSettle();
  }

  testWidgets('botão visível só para alerta com overdue=true', (tester) async {
    await montar(tester, _Fonte(now: () => agora));
    expect(botao, findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('alert_alert-1')), matching: botao), findsOneWidget);
    await encerrar(tester);
  });

  testWidgets('oculto para amarelo, confirmado, já escalonado e antes do prazo', (tester) async {
    // Antes do prazo: 1 min depois do disparo do alerta-1.
    final cedo = _Fonte(now: () => DateTime(2026, 9, 11, 8, 13));
    await montar(tester, cedo);
    expect(botao, findsNothing);
    await encerrar(tester);

    // Amarelo (alert-3), confirmado vermelho (alert-2) e escalado (alert-5)
    // nunca ganham botão, mesmo bem depois do prazo.
    final fonte = _Fonte(now: () => agora);
    await montar(tester, fonte);
    for (final id in ['alert-2', 'alert-3', 'alert-5']) {
      expect(find.descendant(of: find.byKey(Key('alert_$id')), matching: botao), findsNothing, reason: id);
    }
    // Já escalonado: depois de escalonar o alerta-1 o botão some.
    await abrirDialogo(tester);
    await escolherMotivo(tester, EscalationReasonCode.noAckTimeout);
    await tester.tap(confirmar);
    await tester.pumpAndSettle();
    expect(botao, findsNothing);
    await encerrar(tester);
  });

  testWidgets('a tela não decide vencimento com o relógio do aparelho', (tester) async {
    // Servidor diz overdue=false para um alerta antiquíssimo: sem botão.
    final fonte = _AlertaFixo([
      AlertSummary(
        id: 'x',
        patientLabel: 'Paciente #0001',
        microAreaName: 'Microárea 01',
        riskLevel: RiskLevel.red,
        status: AlertStatus.pending,
        triggeredAt: DateTime(2020),
      ),
    ]);
    await montar(tester, fonte);
    expect(botao, findsNothing);
    await encerrar(tester);
  });

  testWidgets('toque abre confirmação; sem motivo o Confirmar fica desabilitado', (tester) async {
    final fonte = _Fonte(now: () => agora);
    await montar(tester, fonte);
    await abrirDialogo(tester);

    expect(find.text('Escalonar alerta #A18F?'), findsOneWidget);
    expect(find.textContaining('não será encerrado'), findsOneWidget);
    for (final m in EscalationReasonCode.values) {
      expect(find.text(m.label), findsOneWidget);
    }
    expect(find.byType(TextField), findsNothing, reason: 'motivo é conjunto fechado, sem texto livre');
    expect(tester.widget<FilledButton>(confirmar).onPressed, isNull);

    await escolherMotivo(tester, EscalationReasonCode.acsUnreachable);
    expect(tester.widget<FilledButton>(confirmar).onPressed, isNotNull);
    expect(fonte.chamadas, isEmpty);
    await encerrar(tester);
  });

  testWidgets('Cancelar não chama o servidor', (tester) async {
    final fonte = _Fonte(now: () => agora);
    await montar(tester, fonte);
    await abrirDialogo(tester);
    await escolherMotivo(tester, EscalationReasonCode.noAckTimeout);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(fonte.chamadas, isEmpty);
    expect(find.text('Escalonar alerta #A18F?'), findsNothing);
    expect(botao, findsOneWidget);
    await encerrar(tester);
  });

  testWidgets('Confirmar chama escalateAlert uma vez, mesmo com toque duplo', (tester) async {
    final fonte = _Fonte(now: () => agora)..segura = Completer<void>();
    await montar(tester, fonte);
    await abrirDialogo(tester);
    await escolherMotivo(tester, EscalationReasonCode.patientRecontact);

    await tester.tap(confirmar);
    await tester.tap(confirmar, warnIfMissed: false);
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull, reason: 'desabilitado em curso');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    fonte.segura!.complete();
    await tester.pumpAndSettle();
    expect(fonte.chamadas, [('alert-1', EscalationReasonCode.patientRecontact)]);
    await encerrar(tester);
  });

  testWidgets('abrir o diálogo com toque duplo no botão abre um só', (tester) async {
    await montar(tester, _Fonte(now: () => agora));
    await tester.tap(botao);
    await tester.tap(botao, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Escalonar alerta #A18F?'), findsOneWidget);
    await encerrar(tester);
  });

  testWidgets('após escalonar a linha continua, status Pendente, selo "Escalonado às HH:mm", sem botão', (tester) async {
    final fonte = _Fonte(now: () => agora);
    await montar(tester, fonte);
    await abrirDialogo(tester);
    await escolherMotivo(tester, EscalationReasonCode.noAckTimeout);
    await tester.tap(confirmar);
    await tester.pumpAndSettle();

    final linha = find.byKey(const Key('alert_alert-1'));
    expect(linha, findsOneWidget);
    expect(find.descendant(of: linha, matching: find.text('Status: Pendente')), findsOneWidget);
    expect(find.descendant(of: linha, matching: find.text('Escalonado às 09:05')), findsOneWidget);
    expect(find.descendant(of: linha, matching: botao), findsNothing);
    expect(fonte.buscas, greaterThanOrEqualTo(2), reason: 'a lista recarrega sem esperar o pulso de 30 s');
    await encerrar(tester);
  });

  testWidgets('alreadyEscalated mostra aviso e atualiza a linha', (tester) async {
    final fonte = _Fonte(now: () => agora)
      ..resultado = EscalationOutcome(escalatedAt: DateTime(2026, 10, 11, 8, 47), alreadyEscalated: true);
    await montar(tester, fonte);
    await abrirDialogo(tester);
    await escolherMotivo(tester, EscalationReasonCode.noAckTimeout);
    await tester.tap(confirmar);
    await tester.pumpAndSettle();

    expect(find.text('Este alerta já havia sido escalonado às 08:47.'), findsOneWidget);
    expect(find.text('Escalonado às 08:47'), findsOneWidget);
    expect(botao, findsNothing);
    await encerrar(tester);
  });

  testWidgets('erro do servidor mostra mensagem em português e mantém o botão', (tester) async {
    final fonte = _Fonte(now: () => agora)..falha = const AdminDataFailure('Não foi possível conectar ao servidor.');
    await montar(tester, fonte);
    await abrirDialogo(tester);
    await escolherMotivo(tester, EscalationReasonCode.noAckTimeout);
    await tester.tap(confirmar);
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível conectar ao servidor.'), findsOneWidget);
    expect(botao, findsOneWidget);
    expect(find.textContaining('Escalonado às'), findsNothing);

    // Falha de validação: texto do servidor, e a lista é relida (o estado mudou).
    await tester.pump(const Duration(seconds: 5));
    final antes = fonte.buscas;
    fonte.falha = const AdminValidationFailure('Alerta já confirmado.');
    await abrirDialogo(tester);
    await escolherMotivo(tester, EscalationReasonCode.noAckTimeout);
    await tester.tap(confirmar);
    await tester.pumpAndSettle();
    expect(find.text('Alerta já confirmado.'), findsOneWidget);
    expect(fonte.buscas, greaterThan(antes));
    await encerrar(tester);
  });

  testWidgets('sessão expirada segue o caminho existente', (tester) async {
    final fonte = _Fonte(now: () => agora)..falha = const AdminSessionExpired();
    await montar(tester, fonte);
    await abrirDialogo(tester);
    await escolherMotivo(tester, EscalationReasonCode.noAckTimeout);
    await tester.tap(confirmar);
    await tester.pumpAndSettle();

    expect(sessaoVencida, isTrue);
    expect(find.text('Escalonar alerta #A18F?'), findsNothing);
    await encerrar(tester);
  });

  testWidgets('não existe controle de descartar/ocultar/silenciar na UI', (tester) async {
    await montar(tester, _Fonte(now: () => agora));
    await abrirDialogo(tester);
    final proibidos = RegExp('descartar|ocultar|silenciar|arquivar|dispensar|fechar alerta|reclassificar', caseSensitive: false);
    bool suspeito(String? s) => s != null && proibidos.hasMatch(s);
    for (final w in tester.widgetList<Text>(find.byType(Text))) {
      expect(suspeito(w.data), isFalse, reason: w.data);
    }
    for (final w in tester.widgetList<Tooltip>(find.byType(Tooltip))) {
      expect(suspeito(w.message), isFalse, reason: w.message);
    }
    for (final w in tester.widgetList<Semantics>(find.byType(Semantics))) {
      expect(suspeito(w.properties.label), isFalse, reason: w.properties.label);
    }
    expect(find.byType(Dismissible), findsNothing);
    await encerrar(tester);
  });

  testWidgets('alvo de toque >= 48dp e Semantics com o rótulo do paciente', (tester) async {
    final semantica = tester.ensureSemantics();
    await montar(tester, _Fonte(now: () => agora));
    expect(tester.getSize(botao).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(botao).width, greaterThanOrEqualTo(48));
    expect(find.bySemanticsLabel('Escalonar alerta #A18F'), findsOneWidget);

    await abrirDialogo(tester);
    for (final f in [confirmar, find.widgetWithText(TextButton, 'Cancelar')]) {
      expect(tester.getSize(f).height, greaterThanOrEqualTo(48));
    }
    semantica.dispose();
    await encerrar(tester);
  });

  for (final (escala, tamanho) in [(2.0, const Size(360, 740)), (1.3, const Size(320, 640))]) {
    testWidgets('sem overflow com fonte a ${(escala * 100).round()}% em ${tamanho.width.round()}dp', (tester) async {
      await montar(tester, _Fonte(now: () => agora), escala: escala, tamanho: tamanho);
      expect(tester.takeException(), isNull);
      await abrirDialogo(tester);
      expect(tester.takeException(), isNull);
      await escolherMotivo(tester, EscalationReasonCode.patientRecontact);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(confirmar);
      await tester.tap(confirmar);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Escalonado às 09:05', skipOffstage: false), findsOneWidget);
      await encerrar(tester);
    });
  }

  testWidgets('MonitoringController.refreshNow dispara um pulso imediato', (tester) async {
    final fonte = ScriptedPulseDataSource(now: () => agora);
    await montar(tester, fonte);
    final antes = fonte.pulsos;
    monitoramento.refreshNow();
    await tester.pump();
    await tester.pump();
    expect(fonte.pulsos, antes + 1);
    await encerrar(tester);
  });
}

class _AlertaFixo extends MockAdminDataSource {
  _AlertaFixo(this._alertas);
  final List<AlertSummary> _alertas;

  @override
  Future<List<AlertSummary>> fetchAlerts({String? microAreaId, AlertStatus? status, int limit = 50, int offset = 0}) async => _alertas;
}
