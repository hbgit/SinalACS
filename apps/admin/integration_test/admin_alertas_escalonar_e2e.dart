/// Escalonamento de alerta vermelho vencido e atualização quase em tempo real
/// do backoffice (issue #44) no emulador, contra o BANCO DE TESTE. Rodado por
/// `scripts/qa/admin_alertas_escalonar_e2e.sh`.
///
/// O coordenador sintético (relé, `/coordenador`) entra pela tela e, **sem
/// nenhuma atualização manual** nos trechos que provam o pulso (nem filtro, nem
/// pull-to-refresh, nem troca de aba: só `tester.pump` e o tempo real
/// passando), vê:
///
/// 1. no Painel, "Abertos (pendentes)" = 1 (o vencido semeado); o script insere
///    o alerta novo e o Painel passa a 2 SOZINHO, no próximo pulso (≤ ~31 s).
///    O Painel desenha `monitoring.lastPulse?.indicators`, e o
///    `fetchDashboardIndicators` só roda ao montar a tela — por isso a prova é
///    feita sem trocar de aba (trocar remontaria a tela e releria);
/// 2. em Alertas (aberta DEPOIS, com leitura nova): o vencido semeado com o
///    botão "Escalonar", e o novo ainda no prazo, **sem** o botão;
/// 3. com a aba de Alertas parada, o botão do novo aparece sozinho depois do
///    prazo (≤ 35 s nominais: um pulso de 30 s mais a recarga da lista, que o
///    pulso dispara porque `overdueRed` muda);
/// 4. o escalonamento pela tela, com motivo: a linha continua "Pendente" e
///    ganha "Escalonado às"; o painel continua contando o alerta como aberto;
/// 5. o reescalonamento por RPC direto devolve `alreadyEscalated` com o MESMO
///    `escalatedAt`;
/// 6. a perda de conexão (o script pausa o Traefik, a única rota do aparelho
///    até o backend; o backend e a conexão MQTT dele ficam no ar): o selo de
///    dado desatualizado aparece com os dados anteriores na tela e some
///    sozinho quando a rota volta.
///
/// Linha do tempo (relógio do banco; I = instante do INSERT do novo, ~1 s
/// depois de `E2E_DISPARAR_ALERTA`): `triggeredAt` = I + 20 s, prazo vence em
/// I + 50 s. Pulso de 30 s com fase qualquer: o Painel vê o 2 em ≤ I + 30 s; a
/// aba de Alertas abre em ≤ I + ~33 s, ainda ≥ 17 s antes do prazo (o novo
/// entra sem botão); o botão aparece no 1º pulso depois de I + 50 s, ou seja
/// em ≤ I + 80 s mais a recarga.
///
/// **A conversa com o script** é por linhas marcadoras impressas aqui
/// (`E2E_DISPARAR_ALERTA`, `E2E_CORTAR_BACKEND`; `E2E_PAINEL_ATUALIZOU` e
/// `E2E_BOTAO_APARECEU` são só evidência, com o atraso medido): o teste roda no aparelho e
/// não alcança o banco nem o Docker; o script lê a saída do `flutter test` em
/// tempo real e age no host. Os ids dos alertas chegam por `--dart-define`
/// (UUIDs sintéticos, não são segredo).
///
/// Sufixo `_e2e.dart` (não `_test.dart`): `flutter test integration_test`
/// descobre `*_test.dart` e o `e2e.sh --full` rodaria isto contra a stack de
/// desenvolvimento, onde não há fixtures, relé nem o prazo de 30 s.
///
/// PRIVACIDADE: só fixtures sintéticas. Senha, código de ativação, segredo TOTP
/// e token nunca vão para log; as linhas impressas levam só ids sintéticos.
@Timeout(Duration(minutes: 12))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/core/auth/admin_auth_backend.dart' show AdminSession;
import 'package:sinalacs_admin/core/auth/admin_auth_bootstrap.dart';
import 'package:sinalacs_admin/core/auth/backend_config.dart';
import 'package:sinalacs_client/sinalacs_client.dart' as api;

import 'support/e2e_admin.dart' show relayBase;
import 'support/totp.dart';

/// Alerta semeado já vencido (`E2E_SEED_ALERT_ESCALATION=1`).
const _alertaVencido = String.fromEnvironment('E2E_ALERTA_VENCIDO');

/// Alerta que o script insere quando este teste pede (`E2E_DISPARAR_ALERTA`).
const _alertaNovo = String.fromEnvironment('E2E_ALERTA_NOVO');

/// Prazo da stack de e2e (`RED_ALERT_ESCALATION_SECONDS` em
/// `docker-compose.e2e.yml`, `e2eEscalationThresholdSeconds` no backend).
const _prazo = Duration(seconds: 30);

/// Atraso máximo aceito entre o prazo vencer e o botão aparecer: 35 s
/// nominais (pulso de 30 s + a recarga da lista) mais 5 s de tolerância para a
/// diferença entre o relógio do aparelho e o do servidor.
const _atrasoMaximoDoBotao = Duration(seconds: 40);

/// Atraso máximo aceito para o Painel passar de 1 a 2 depois do pedido de
/// disparo: um pulso (30 s) + o INSERT (~1 s) + folga.
const _atrasoMaximoDoPainel = Duration(seconds: 40);

/// Quanto tempo o script deixa o Traefik pausado depois de `E2E_CORTAR_BACKEND`
/// (o nome do marcador ficou da 1ª versão, que pausava o backend).
/// O selo pode levar ~80–90 s depois do corte (último sucesso logo antes dele +
/// 2 pulsos falhos de 30 s com prazo de 20 s cada, e o selo só é redesenhado
/// quando um pulso falho notifica); 120 s deixa folga para vê-lo antes da volta.
const _segundosDeCorte = 120;

int _passo(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ 30;

/// A sessão que o login da tela abriu: a fábrica da fonte de dados recebe a
/// `AdminSession` do servidor, e é o token dela que o RPC direto usa — sem um
/// segundo login (que consumiria outro passo TOTP).
AdminSession? _sessao;

api.Client? _rpc;

/// Cliente RPC para as provas diretas — a MESMA CA e o mesmo host que o app
/// usa (`buildAdminWiring`).
Future<api.Client> _clienteRpc() async {
  final existente = _rpc;
  if (existente != null) return existente;
  final ca = (await rootBundle.load(adminRpcCaAsset)).buffer.asUint8List();
  return _rpc = api.Client(
    AdminBackendConfig.requireSecureHost(AdminBackendConfig.host),
    securityContext: SecurityContext()..setTrustedCertificatesBytes(ca),
  )..connectivityMonitor = null;
}

String get _token {
  final sessao = _sessao;
  if (sessao == null) fail('o login não abriu sessão (a fábrica da fonte de dados não foi chamada)');
  return sessao.accessToken;
}

/// Credencial do coordenador sintético (bloco `coordinator` do manifesto),
/// entregue pelo relé em `/coordenador` uma única vez.
Future<({String matricula, String senha, String activationCode})> _coordenadorDoRele() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(relayBase).replace(path: '/coordenador'));
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode != 200) throw StateError('o relé respondeu ${response.statusCode} a /coordenador');
    final json = jsonDecode(body) as Map;
    return (
      matricula: json['matricula'] as String,
      senha: json['senha'] as String,
      activationCode: json['activationCode'] as String,
    );
  } on SocketException {
    throw StateError('o relé não está no ar (scripts/qa/otp_relay.py + adb reverse tcp:8765 tcp:8765)');
  } finally {
    client.close(force: true);
  }
}

/// Espera [done] só bombeando quadros e deixando o tempo real passar — nunca
/// rola, toca ou troca filtro. É o que sustenta o "sem atualização manual".
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 30),
  Duration step = const Duration(milliseconds: 200),
  String? motivo,
}) async {
  final fim = DateTime.now().add(timeout);
  while (!done() && DateTime.now().isBefore(fim)) {
    await tester.pump(step);
  }
  if (done()) return;
  final textos = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(40).join(' | ');
  fail('condição não atingida em ${timeout.inSeconds}s${motivo == null ? '' : ': $motivo'}; tela: $textos');
}

bool _existe(String chave) => find.byKey(Key(chave)).evaluate().isNotEmpty;

bool get _painelAberto => find.text('Painel de Indicadores').evaluate().isNotEmpty;

/// "Abertos (pendentes)" do Painel mostra [valor]? A linha é a `_InfoRow`
/// (o `Padding` mais próximo do rótulo), para o número não casar com outro
/// contador da tela.
bool _abertosNoPainel(Finder rotulo, String valor) {
  if (rotulo.evaluate().isEmpty) return false;
  final linha = find.ancestor(of: rotulo, matching: find.byType(Padding)).first;
  return find.descendant(of: linha, matching: find.text(valor)).evaluate().isNotEmpty;
}

Finder _cartao(String alertId) => find.byKey(Key('alert_$alertId'));

bool _noCartao(String alertId, Finder alvo) =>
    find.descendant(of: _cartao(alertId), matching: alvo).evaluate().isNotEmpty;

/// O botão é `OutlinedButton.icon` (uma subclasse privada): `find.byType` não o
/// acharia, o rótulo exato acha — e o título do diálogo ("Escalonar alerta
/// #…?") não casa com ele.
bool _temBotaoEscalonar(String alertId) => _noCartao(alertId, find.text('Escalonar'));

bool _temSeloEscalonado(String alertId) => _noCartao(alertId, find.textContaining('Escalonado às'));

Future<void> _tocar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(alvo);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _digitar(WidgetTester tester, String chave, String texto) async {
  final campo = find.byKey(Key(chave));
  await tester.ensureVisible(campo);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.enterText(campo, texto);
}

/// Troca de aba pela navegação: no celular o painel se chama "Painel" na barra
/// inferior; no trilho lateral, "Indicadores".
Future<void> _irPara(WidgetTester tester, List<String> rotulos) async {
  for (final rotulo in rotulos) {
    final alvo = find.text(rotulo);
    if (alvo.evaluate().isNotEmpty) {
      await _tocar(tester, alvo.last);
      return;
    }
  }
  fail('nenhum destino ${rotulos.join('/')} na navegação');
}

Future<void> _entrar(WidgetTester tester) async {
  final cred = await _coordenadorDoRele();
  await _digitar(tester, 'matricula_field', cred.matricula);
  await _digitar(tester, 'senha_field', cred.senha);
  await _tocar(tester, find.byKey(const Key('login_button')));

  await _pumpUntil(
    tester,
    () => _existe('activation_code_field') || _existe('totp_field') || _existe('login_error') || _painelAberto,
    motivo: 'resposta do login',
  );
  // Primeiro acesso: o coordenador da fixture nasce sem MFA.
  expect(_existe('activation_code_field'), isTrue, reason: 'o coordenador da fixture deveria ativar a MFA');
  await _digitar(tester, 'activation_code_field', cred.activationCode);
  await _tocar(tester, find.byKey(const Key('activation_continue')));
  await _pumpUntil(tester, () => _existe('mfa_secret') || _existe('mfa_error'), timeout: const Duration(seconds: 60));
  expect(_existe('mfa_error'), isFalse);
  final segredo = base32Decode(tester.widget<SelectableText>(find.byKey(const Key('mfa_secret'))).data!);
  final ativacao = DateTime.now();
  await _digitar(tester, 'mfa_code_field', totpCode(segredo, ativacao));
  await _tocar(tester, find.byKey(const Key('mfa_confirm_button')));

  await _pumpUntil(tester, () => _existe('totp_field') || _existe('login_error') || _painelAberto,
      timeout: const Duration(seconds: 60));
  if (_existe('totp_field')) {
    // O passo da ativação já foi aceito e o replay é barrado: o login usa o
    // passo seguinte.
    await _pumpUntil(tester, () => _passo(DateTime.now()) > _passo(ativacao),
        timeout: const Duration(seconds: 40), step: const Duration(milliseconds: 500));
    await _digitar(tester, 'totp_field', totpCode(segredo, DateTime.now()));
    await _tocar(tester, find.byKey(const Key('login_button')));
  }
  await _pumpUntil(tester, () => _painelAberto || _existe('login_error'), timeout: const Duration(seconds: 60));
  expect(_existe('login_error'), isFalse,
      reason: _existe('login_error') ? (tester.widget<Text>(find.byKey(const Key('login_error'))).data ?? '') : '');
}

/// A linha do alerta como o SERVIDOR a vê agora (`admin.alerts`, escopo do
/// coordenador). Cada chamada grava uma linha `read` — o script conta.
Future<api.AdminAlert> _alertaNoServidor(String alertId) async {
  final client = await _clienteRpc();
  final pagina = await client.admin.alerts(accessToken: _token, limit: 100, offset: 0);
  return pagina.items.singleWhere((a) => a.id == alertId,
      orElse: () => fail('o alerta $alertId não está na lista do coordenador'));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('coordenador escalona o alerta vencido sem atualizar a tela e vê o selo de desatualizado na queda',
      (tester) async {
    expect(AdminBackendConfig.host, startsWith('https://'));
    expect(_alertaVencido, isNotEmpty, reason: 'falta --dart-define=E2E_ALERTA_VENCIDO (rode pelo script)');
    expect(_alertaNovo, isNotEmpty, reason: 'falta --dart-define=E2E_ALERTA_NOVO (rode pelo script)');

    final ca = (await rootBundle.load(adminRpcCaAsset)).buffer.asUint8List();
    final fiacao = buildAdminWiring(caBytes: ca);
    await tester.pumpWidget(SinalAdminApp(
      auth: fiacao.auth,
      dataSourceFor: (sessao) {
        _sessao = sessao;
        return fiacao.dataSourceFor(sessao);
      },
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await _entrar(tester);
    expect(_painelAberto, isTrue);

    // 1. Painel parado: 1 vermelho aberto (o vencido semeado). Pede o alerta
    // novo e espera o 2 SEM trocar de aba — só o pulso pode trazê-lo.
    final rotuloAbertos = find.text('Abertos (pendentes)');
    await tester.scrollUntilVisible(rotuloAbertos, 200, scrollable: find.byType(Scrollable).last, maxScrolls: 30);
    await _pumpUntil(tester, () => _abertosNoPainel(rotuloAbertos, '1'), motivo: 'o painel com 1 vermelho aberto');
    final pedido = DateTime.now();
    // ignore: avoid_print
    print('E2E_DISPARAR_ALERTA id=$_alertaNovo');
    await _pumpUntil(tester, () => _abertosNoPainel(rotuloAbertos, '2'),
        timeout: _atrasoMaximoDoPainel + const Duration(seconds: 20),
        motivo: 'o painel passar a 2 abertos sozinho (pulso), sem troca de aba');
    final atrasoDoPainel = DateTime.now().difference(pedido);
    // ignore: avoid_print
    print('E2E_PAINEL_ATUALIZOU atraso_ms=${atrasoDoPainel.inMilliseconds}');
    expect(atrasoDoPainel, lessThanOrEqualTo(_atrasoMaximoDoPainel),
        reason: 'o painel demorou ${atrasoDoPainel.inSeconds}s para refletir o alerta novo');

    // 2. Alertas, aberta agora (leitura nova). Daqui até o escalonamento a aba
    // fica parada e ninguém a recarrega à mão.
    await _irPara(tester, const ['Alertas']);
    await _pumpUntil(tester, () => _cartao(_alertaVencido).evaluate().isNotEmpty && _cartao(_alertaNovo).evaluate().isNotEmpty,
        motivo: 'os dois alertas na lista do coordenador');
    expect(_temBotaoEscalonar(_alertaVencido), isTrue, reason: 'o alerta de 10 min já venceu o prazo de 30 s');
    expect(_temBotaoEscalonar(_alertaNovo), isFalse, reason: 'antes do prazo não há botão');
    expect(_noCartao(_alertaNovo, find.text('Status: Pendente')), isTrue);
    final novoNoServidor = await _alertaNoServidor(_alertaNovo);
    expect(novoNoServidor.overdue, isFalse, reason: 'o servidor também o vê no prazo');
    final vence = novoNoServidor.triggeredAt.toUtc().add(_prazo);

    // 3. Sem tocar em nada: o botão aparece depois do prazo (o pulso vê
    // `overdueRed` mudar e a lista recarrega).
    await _pumpUntil(tester, () => _temBotaoEscalonar(_alertaNovo),
        timeout: vence.difference(DateTime.now().toUtc()) + _atrasoMaximoDoBotao + const Duration(seconds: 10),
        motivo: 'o botão Escalonar aparecer sozinho depois do prazo');
    final atraso = DateTime.now().toUtc().difference(vence);
    // ignore: avoid_print
    print('E2E_BOTAO_APARECEU atraso_ms=${atraso.inMilliseconds}');
    expect(atraso, lessThanOrEqualTo(_atrasoMaximoDoBotao), reason: 'o botão demorou ${atraso.inSeconds}s após o prazo');

    // 4. Escalona pela tela, com motivo.
    await _tocar(tester, find.descendant(of: _cartao(_alertaNovo), matching: find.text('Escalonar')));
    await _pumpUntil(tester, () => find.text('Confirmar escalonamento').evaluate().isNotEmpty, motivo: 'o diálogo');
    final confirmar = find.widgetWithText(FilledButton, 'Confirmar escalonamento');
    expect(tester.widget<FilledButton>(confirmar).onPressed, isNull, reason: 'sem motivo não confirma');
    await _tocar(tester, find.text('Sem confirmação no prazo'));
    expect(tester.widget<FilledButton>(confirmar).onPressed, isNotNull);
    await _tocar(tester, confirmar);
    await _pumpUntil(tester, () => _temSeloEscalonado(_alertaNovo), timeout: const Duration(seconds: 60),
        motivo: 'a linha com "Escalonado às"');
    expect(_noCartao(_alertaNovo, find.text('Status: Pendente')), isTrue, reason: 'escalonar não confirma o alerta');
    expect(_temBotaoEscalonar(_alertaNovo), isFalse);
    expect(_temBotaoEscalonar(_alertaVencido), isTrue, reason: 'o outro alerta vencido não foi tocado');

    // 5. Reescalonar por RPC direto: idempotente, com o carimbo ORIGINAL.
    final escalonado = await _alertaNoServidor(_alertaNovo);
    expect(escalonado.escalatedAt, isNotNull);
    expect(escalonado.status, api.AlertStatus.pending);
    final client = await _clienteRpc();
    final repetido = await client.admin.escalateAlert(
      accessToken: _token,
      alertId: _alertaNovo,
      reason: api.EscalationReason.noAckTimeout,
    );
    expect(repetido.alreadyEscalated, isTrue);
    expect(repetido.escalatedAt.isAtSameMomentAs(escalonado.escalatedAt!), isTrue,
        reason: 'o reescalonamento devolve o escalatedAt original');

    // 6. O painel continua contando os dois vermelhos como abertos: escalonar
    // não tira o alerta da conta. (A troca de aba aqui não prova o pulso — essa
    // prova é a do passo 1; aqui só se confere que o número não caiu.)
    final indicadores = await client.admin.indicators(accessToken: _token);
    expect(indicadores.openRedAlerts, 2, reason: 'o vencido semeado + o novo escalonado, ambos pendentes');
    await _irPara(tester, const ['Painel', 'Indicadores']);
    await _pumpUntil(tester, () => _painelAberto, motivo: 'o painel');
    await tester.scrollUntilVisible(rotuloAbertos, 200, scrollable: find.byType(Scrollable).last, maxScrolls: 30);
    await _pumpUntil(tester, () => _abertosNoPainel(rotuloAbertos, '2'), motivo: 'o painel com 2 vermelhos abertos');

    // 7. Perda de conexão: o script pausa o Traefik (o backend fica no ar). O
    // selo aparece com o dado anterior na tela e some sozinho quando a rota volta.
    await _irPara(tester, const ['Alertas']);
    await _pumpUntil(tester, () => _temSeloEscalonado(_alertaNovo), motivo: 'a lista de volta, com o escalonado');
    expect(_existe('stale_badge'), isFalse, reason: 'com o backend no ar o dado está em dia');
    // ignore: avoid_print
    print('E2E_CORTAR_BACKEND segundos=$_segundosDeCorte');
    await _pumpUntil(tester, () => _existe('stale_badge'),
        timeout: const Duration(seconds: _segundosDeCorte + 30), step: const Duration(milliseconds: 500),
        motivo: 'o selo de desatualizado com o Traefik pausado');
    expect(find.descendant(of: find.byKey(const Key('stale_badge')), matching: find.textContaining('sem atualização há')),
        findsOneWidget);
    expect(_temSeloEscalonado(_alertaNovo), isTrue, reason: 'a queda não apaga o dado anterior');
    expect(_cartao(_alertaVencido), findsOneWidget);
    await _pumpUntil(tester, () => !_existe('stale_badge'),
        timeout: const Duration(seconds: _segundosDeCorte + 90), step: const Duration(milliseconds: 500),
        motivo: 'o selo sumir sozinho com a rota de volta');
    expect(_temSeloEscalonado(_alertaNovo), isTrue);
    // ignore: avoid_print
    print('E2E_ESCALONAMENTO_OK');
  });
}
