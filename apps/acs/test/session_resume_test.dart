import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/biometric_gate.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show MicroAreaPatient;

import 'support/fake_rpc_server.dart';
import 'support/fakes.dart';
import 'support/layout_harness.dart' show assentar, irParaDaBarra, irParaDoMais;

/// Retomada da sessão por digital na partida, "Entrar com senha" na cobertura
/// do bloqueio e "Sair". Credenciais e pacientes sintéticos.
void main() {
  late FakeAlertFeed feed;
  late FakeBiometricGate gate;
  late OfflineVisitQueue fila;
  late GlobalKey<NavigatorState> navKey;

  setUp(() {
    gate = FakeBiometricGate();
    fila = OfflineVisitQueue();
    navKey = GlobalKey<NavigatorState>();
  });

  Future<void> abrirApp(WidgetTester tester, AcsBackend backend, {Duration? lockAfter}) async {
    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      visitQueue: fila,
      biometricGate: gate,
      navigatorKey: navKey,
      lockAfter: lockAfter,
      feedBuilder: (q) => feed = FakeAlertFeed(q),
    ));
    await assentar(tester);
  }

  Finder painel() => find.text('Painel operacional');
  Finder formulario() => find.byKey(const Key('login_button'));

  Future<void> entrarComSenha(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
    await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
    await tester.ensureVisible(formulario());
    await tester.pump();
    await tester.tap(formulario());
    await assentar(tester);
  }

  /// Segundo plano e volta: com `lockAfter: Duration.zero` sempre bloqueia.
  Future<void> irEVoltar(WidgetTester tester) async {
    for (final s in const [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused,
        AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await assentar(tester);
  }

  group('partida a frio', () {
    testWidgets('partida com refresh token salvo: digital OK → entra no painel sem digitar nada', (tester) async {
      final backend = FakeAcsBackend()..storedRefreshToken = 'refresh-salvo';
      await abrirApp(tester, backend);

      expect(gate.reasons, ['Entrar no SinalACS']);
      expect(backend.resumeCount, 1);
      expect(backend.loginCount, 0, reason: 'nenhuma senha digitada');
      expect(painel(), findsOneWidget);
      expect(formulario(), findsNothing);
      expect(feed.startedTopicMicroArea, seedMicroAreaId);
    });

    testWidgets('partida com token salvo e digital cancelada → fica na tela de login completa', (tester) async {
      gate.result = UnlockResult.cancelled;
      final backend = FakeAcsBackend()..storedRefreshToken = 'refresh-salvo';
      await abrirApp(tester, backend);

      expect(gate.calls, 1);
      expect(backend.resumeCount, 0, reason: 'sem desbloqueio não se toca no token');
      expect(formulario(), findsOneWidget);
      expect(painel(), findsNothing);
      expect(find.byKey(const Key('login_aviso')), findsNothing);
      expect(tester.widget<FilledButton>(formulario()).onPressed, isNotNull, reason: 'formulário utilizável');
      expect(tester.widget<TextField>(find.byKey(const Key('matricula_field'))).controller!.text, isEmpty,
          reason: 'nada da sessão guardada aparece no formulário');
    });

    testWidgets('partida sem token salvo → tela de login normal, sem prompt biométrico', (tester) async {
      final backend = FakeAcsBackend();
      await abrirApp(tester, backend);

      expect(gate.calls, 0);
      expect(backend.resumeCount, 0);
      expect(formulario(), findsOneWidget);
    });

    testWidgets('aparelho sem nenhum bloqueio de tela (unavailable) NÃO retoma a sessão salva (P5)', (tester) async {
      gate.available = false;
      final backend = FakeAcsBackend()..storedRefreshToken = 'refresh-salvo';
      await abrirApp(tester, backend);

      expect(gate.calls, 0);
      expect(backend.resumeCount, 0);
      expect(formulario(), findsOneWidget);
      expect(painel(), findsNothing);
    });

    testWidgets('sem rede na retomada → aviso com "Tentar de novo", token mantido; com rede entra', (tester) async {
      final backend = FakeAcsBackend()
        ..storedRefreshToken = 'refresh-salvo'
        ..resumeOffline = true;
      await abrirApp(tester, backend);

      expect(find.text('Sem conexão para retomar a sessão. Tente de novo ou entre com senha.'), findsOneWidget);
      expect(backend.storedRefreshToken, 'refresh-salvo');
      expect(formulario(), findsOneWidget);

      backend.resumeOffline = false;
      await tester.ensureVisible(find.byKey(const Key('resume_retry')));
      await tester.tap(find.byKey(const Key('resume_retry')));
      await assentar(tester);

      expect(gate.calls, 2, reason: 'a nova tentativa pede o desbloqueio de novo');
      expect(painel(), findsOneWidget);
    });
  });

  testWidgets('toque duplo em "Tentar de novo" faz UMA retomada só', (tester) async {
    final backend = FakeAcsBackend()
      ..storedRefreshToken = 'refresh-salvo'
      ..resumeOffline = true;
    await abrirApp(tester, backend);
    expect(gate.calls, 1);
    backend.resumeOffline = false;

    final tentar = find.byKey(const Key('resume_retry'));
    await tester.ensureVisible(tentar);
    await tester.pump();
    final prompt = Completer<UnlockResult>();
    gate.pending = prompt;
    final botao = tester.widget<OutlinedButton>(tentar);
    botao.onPressed!();
    botao.onPressed!();
    await tester.pump();
    expect(tester.widget<FilledButton>(formulario()).onPressed, isNull, reason: 'login desligado durante a retomada');
    expect(find.byKey(const Key('resume_retry')), findsNothing, reason: 'sem segundo toque possível');
    prompt.complete(UnlockResult.unlocked);
    await assentar(tester);

    expect(gate.calls, 2, reason: 'um prompt a mais, não dois');
    expect(backend.resumeCount, 2, reason: 'a primeira (offline) e UMA nova');
    expect(painel(), findsOneWidget);
  });

  group('cliente real contra servidor local', () {
    late FakeRpcServer server;
    late MemorySessionTokenStore store;
    late BackendClient backend;
    HttpOverrides? overridesDoTeste;

    setUp(() async {
      // O binding de widget troca o HttpClient por um que responde 400 a tudo;
      // aqui a chamada precisa chegar ao servidor local de verdade.
      overridesDoTeste = HttpOverrides.current;
      HttpOverrides.global = null;
      server = await FakeRpcServer.start();
      store = MemorySessionTokenStore();
      backend = BackendClient(host: server.host, tokenStore: store, deviceIds: MemoryDeviceIdStore());
    });

    tearDown(() async {
      backend.close();
      await server.stop();
      HttpOverrides.global = overridesDoTeste;
    });

    /// A requisição nasce no relógio falso do teste: o prazo (timeout) dela
    /// fica pendente nele. Desmonta e deixa o relógio passar do prazo.
    Future<void> encerrar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 5));
    }

    testWidgets('refresh recusado na partida → tela de login com aviso, token apagado', (tester) async {
      await tester.runAsync(() => store.write('refresh-revogado'));
      server.rejectRefresh = true;
      await abrirApp(tester, backend);

      expect(server.refreshCount, 1);
      expect(find.text('Sua sessão expirou. Entre novamente.'), findsOneWidget);
      expect(formulario(), findsOneWidget);
      expect(await tester.runAsync(store.read), isNull);
      await encerrar(tester);
    });

    testWidgets('após login completo, o token novo substitui o salvo', (tester) async {
      await tester.runAsync(() => store.write('refresh-antigo'));
      gate.result = UnlockResult.cancelled;
      await abrirApp(tester, backend);
      expect(formulario(), findsOneWidget);

      await entrarComSenha(tester);

      expect(painel(), findsOneWidget);
      expect(server.loginCount, 1);
      expect(await tester.runAsync(store.read), 'refresh-0');
      await encerrar(tester);
    });

    testWidgets('retomada da sessão respeita a microárea devolvida pelo servidor', (tester) async {
      await tester.runAsync(() => store.write('refresh-salvo'));
      server.microAreaId = otherMicroAreaId;
      await abrirApp(tester, backend);

      expect(painel(), findsOneWidget);
      expect(feed.startedTopicMicroArea, otherMicroAreaId, reason: 'o território vem do token novo, não de cache');
      expect(await tester.runAsync(store.read), 'refresh-1', reason: 'token rotacionado');
      await encerrar(tester);
    });
  });

  group('bloqueio com painel aberto', () {
    late FakeAcsBackend backend;

    Future<void> abrirPainel(WidgetTester tester) async {
      backend = FakeAcsBackend()
        ..patients = [
          MicroAreaPatient(patientId: syntheticPatientId(5), name: 'Paciente Sintético', isChronic: false, chronicConditions: const []),
        ];
      await fila.add(OfflineVisitRecord(patientId: seedPatientId, risk: 'red', status: 'PENDENTE'));
      await abrirApp(tester, backend, lockAfter: Duration.zero);
      await entrarComSenha(tester);
      expect(painel(), findsOneWidget);
      feed.deliver(testAlert(alertId: 'alerta-antes'));
      await assentar(tester);
    }

    testWidgets('alerta vermelho recebido com o app BLOQUEADO está na fila ao desbloquear', (tester) async {
      await abrirPainel(tester);
      gate.result = UnlockResult.cancelled;
      await irEVoltar(tester);
      expect(find.text('Aplicativo bloqueado'), findsOneWidget);

      feed.deliver(testAlert(alertId: 'alerta-no-bloqueio'));
      await assentar(tester);

      gate.result = UnlockResult.unlocked;
      await tester.tap(find.text('Desbloquear'));
      await assentar(tester);

      expect(find.text('Aplicativo bloqueado'), findsNothing);
      expect(find.byKey(const Key('alert_alerta-no-bloqueio')), findsOneWidget);
      expect(find.byKey(const Key('alert_alerta-antes')), findsOneWidget);
      expect(feed.stopped, isFalse);
    });

    testWidgets('"Entrar com senha" do bloqueio leva ao login completo e preserva o painel por baixo', (tester) async {
      await abrirPainel(tester);
      await irParaDaBarra(tester, 'Visita');
      await tester.enterText(find.byKey(const Key('patient_search')), 'busca em andamento');
      await tester.pump();

      gate.result = UnlockResult.cancelled;
      await irEVoltar(tester);
      expect(find.text('Aplicativo bloqueado'), findsOneWidget);

      await tester.tap(find.text('Entrar com senha'));
      await assentar(tester);

      // A cobertura sai, mas o que aparece é o formulário: o painel segue
      // escondido sob a rota opaca e não descartável.
      expect(find.text('Aplicativo bloqueado'), findsNothing);
      expect(formulario(), findsOneWidget);
      expect(find.byKey(const Key('patient_search')), findsNothing);
      await tester.binding.handlePopRoute();
      await assentar(tester);
      expect(formulario(), findsOneWidget, reason: 'voltar não descarta a reautenticação');

      // Alerta que chega durante a reautenticação também fica.
      feed.deliver(testAlert(alertId: 'alerta-na-senha'));
      await entrarComSenha(tester);

      expect(formulario(), findsNothing, reason: 'voltou ao painel');
      expect(tester.widget<TextField>(find.byKey(const Key('patient_search'))).controller!.text, 'busca em andamento');
      expect(feed.stopped, isFalse, reason: 'o feed MQTT não foi derrubado');
      expect(fila.pendingCount, 1);
      expect(navKey.currentState!.canPop(), isFalse, reason: 'sem rota-bloqueio esquecida');

      await irParaDaBarra(tester, 'Fila');
      expect(find.byKey(const Key('alert_alerta-antes')), findsOneWidget);
      expect(find.byKey(const Key('alert_alerta-na-senha')), findsOneWidget);

      // O gate recriado continua bloqueando.
      await irEVoltar(tester);
      expect(find.text('Aplicativo bloqueado'), findsOneWidget);
    });

    testWidgets('"Entrar com senha": o painel nunca fica à vista, tocável ou na semântica em quadro algum', (tester) async {
      final semantics = tester.ensureSemantics();
      await abrirPainel(tester);
      await irParaDaBarra(tester, 'Visita');
      gate.result = UnlockResult.cancelled;
      await irEVoltar(tester);
      expect(find.text('Aplicativo bloqueado'), findsOneWidget);

      void semPainel(String quadro) {
        expect(find.byKey(const Key('patient_search')), findsNothing, reason: 'visível no $quadro');
        expect(find.byKey(const Key('patient_search'), skipOffstage: false).hitTestable(), findsNothing,
            reason: 'tocável no $quadro');
        expect(find.bySemanticsLabel('Buscar paciente pelo nome'), findsNothing, reason: 'na semântica no $quadro');
      }

      await tester.tap(find.text('Entrar com senha'));
      await tester.pump();
      semPainel('1º quadro');
      for (var i = 2; i <= 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        semPainel('quadro $i');
      }
      await tester.pump(const Duration(milliseconds: 150));
      semPainel('meio da transição');
      await assentar(tester);
      semPainel('fim');
      expect(formulario(), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('"Entrar com senha" limpa senha e código digitados antes do bloqueio', (tester) async {
      backend = FakeAcsBackend()..expectedTotpCode = '123456';
      gate.result = UnlockResult.cancelled;
      await abrirApp(tester, backend, lockAfter: Duration.zero);
      await entrarComSenha(tester); // pede o código
      await tester.enterText(find.byKey(const Key('totp_field')), '654');
      await irEVoltar(tester);
      expect(find.text('Aplicativo bloqueado'), findsOneWidget);

      await tester.tap(find.text('Entrar com senha'));
      await assentar(tester);

      expect(find.text('Aplicativo bloqueado'), findsNothing);
      expect(tester.widget<TextField>(find.byKey(const Key('senha_field'))).controller!.text, isEmpty);
      expect(find.byKey(const Key('totp_field')), findsNothing);
    });

    testWidgets('"Entrar com senha" descarta a tela de ativação da MFA (segredo)', (tester) async {
      backend = FakeAcsBackend()..mfaEnrollmentRequired = true;
      gate.result = UnlockResult.cancelled;
      await abrirApp(tester, backend, lockAfter: Duration.zero);
      await entrarComSenha(tester);
      expect(find.byKey(const Key('mfa_secret')), findsOneWidget);
      await irEVoltar(tester);

      await tester.tap(find.text('Entrar com senha'));
      await assentar(tester);

      expect(find.byKey(const Key('mfa_secret'), skipOffstage: false), findsNothing);
      expect(formulario(), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('senha_field'))).controller!.text, isEmpty);
      expect(navKey.currentState!.canPop(), isFalse);
    });

    testWidgets('"Entrar com senha" e outro usuário entra: o painel anterior é descartado (RNF06)', (tester) async {
      await abrirPainel(tester);
      gate.result = UnlockResult.cancelled;
      await irEVoltar(tester);
      await tester.tap(find.text('Entrar com senha'));
      await assentar(tester);

      final feedAnterior = feed;
      backend.nextUserId = '00000000-0000-4000-8000-0000000000ff';
      await entrarComSenha(tester);

      expect(painel(), findsOneWidget);
      expect(find.byKey(const Key('alert_alerta-antes'), skipOffstage: false), findsNothing);
      expect(feedAnterior.stopped, isTrue);
      expect(navKey.currentState!.canPop(), isFalse);
    });

    testWidgets('"Sair" em Ajustes pede confirmação, chama logout e volta ao login', (tester) async {
      await abrirPainel(tester);
      await irParaDoMais(tester, 'Preferências');

      final sair = find.byKey(const Key('logout_button'));
      await tester.ensureVisible(sair);
      await tester.pump();
      await tester.tap(sair);
      await assentar(tester);
      expect(find.text('As visitas ainda não sincronizadas continuam salvas neste aparelho.'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await assentar(tester);
      expect(backend.logoutCount, 0);
      expect(painel(), findsOneWidget);

      await tester.tap(sair);
      await assentar(tester);
      final saida = Completer<void>();
      backend.logoutGate = saida;
      await tester.tap(find.byKey(const Key('logout_confirm')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('logout_progress')), findsOneWidget, reason: 'progresso enquanto sai');
      expect(tester.widget<FilledButton>(sair).onPressed, isNull);
      saida.complete();
      await assentar(tester);

      expect(backend.logoutCount, 1);
      expect(backend.storedRefreshToken, isNull);
      expect(formulario(), findsOneWidget);
      expect(painel(), findsNothing);
      expect(feed.stopped, isTrue, reason: 'o painel foi descartado e o feed parou');
      expect(fila.pendingCount, 1, reason: 'a visita não sincronizada continua no aparelho');
      expect(gate.calls, 0, reason: 'a tela depois de Sair não tenta retomar a sessão');
      expect(navKey.currentState!.canPop(), isFalse);
    });

    Future<void> abrirSair(WidgetTester tester) async {
      await irParaDoMais(tester, 'Preferências');
      final sair = find.byKey(const Key('logout_button'));
      await tester.ensureVisible(sair);
      await tester.pump();
      await tester.tap(sair);
      await assentar(tester);
    }

    testWidgets('"Sair" sem alerta pendente: texto e botão originais', (tester) async {
      await abrirPainel(tester);
      // O único alerta do painel já foi confirmado.
      await irParaDaBarra(tester, 'Fila');
      final ack = find.byKey(const Key('ack_alerta-antes'));
      await tester.ensureVisible(ack);
      await tester.pump();
      await tester.tap(ack);
      await assentar(tester);
      expect(backend.acknowledgedAlertIds, ['alerta-antes']);
      await abrirSair(tester);

      expect(find.text('As visitas ainda não sincronizadas continuam salvas neste aparelho.'), findsOneWidget);
      expect(find.byKey(const Key('logout_pending_alerts')), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('logout_confirm')), matching: find.text('Sair')), findsOneWidget);
    });

    testWidgets('"Sair" com 2 alertas não confirmados: diz quantos e o botão explicita a perda', (tester) async {
      await abrirPainel(tester);
      feed.deliver(testAlert(alertId: 'alerta-dois'));
      await assentar(tester);
      await abrirSair(tester);

      expect(find.text('As visitas ainda não sincronizadas continuam salvas neste aparelho.'), findsOneWidget);
      expect(
        find.text('Há 2 alertas ainda não confirmados. Eles saem deste aparelho, mas continuam pendentes no servidor.'),
        findsOneWidget,
      );
      expect(find.descendant(of: find.byKey(const Key('logout_confirm')), matching: find.text('Sair mesmo assim')),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('logout_confirm')));
      await assentar(tester);

      expect(backend.logoutCount, 1, reason: 'a saída não é bloqueada');
      expect(formulario(), findsOneWidget);
      expect(fila.pendingCount, 1, reason: 'a visita não sincronizada continua no aparelho');
    });

    testWidgets('"Sair" com 1 alerta não confirmado usa o singular', (tester) async {
      await abrirPainel(tester);
      await abrirSair(tester);
      expect(
        find.text('Há 1 alerta ainda não confirmado. Ele sai deste aparelho, mas continua pendente no servidor.'),
        findsOneWidget,
      );
    });
  });
}
