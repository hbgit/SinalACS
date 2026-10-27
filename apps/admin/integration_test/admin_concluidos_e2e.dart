/// Alerta vermelho concluído continua visível para a coordenação (issue #87,
/// INV-03) no emulador, contra o BANCO DE TESTE. Rodado por
/// `scripts/qa/admin_concluidos_e2e.sh`.
///
/// O coordenador sintético (relé, `/coordenador`) entra pela tela e, **sem
/// nenhuma atualização manual** nos trechos que provam o pulso (nem filtro,
/// nem troca de aba: só `tester.pump` e o tempo real passando), vê o Painel
/// acompanhar um alerta que percorre todos os estados:
///
/// 1. Painel com os 3 alertas de `E2E_SEED_ADMIN_ALERTS=1` (vermelho pendente,
///    vermelho reconhecido, verde pendente): Abertos 1, Reconhecidos 1,
///    Concluídos 0. **Antes da correção da #87 a linha "Concluídos" não
///    existe: é aqui que a reprodução falha.**
/// 2. O script reconhece o pendente no banco (o papel do ACS): Abertos 0,
///    Reconhecidos 2, Concluídos 0, no pulso seguinte (≤ 40 s).
/// 3. O script conclui o reconhecido: Reconhecidos 1, Concluídos 1 (≤ 40 s).
///    Em cada passo o cartão "Vermelho" segue 2: a soma fecha.
/// 4. O script insere um vermelho concluído SEM microárea: só o administrador
///    o conta; para o coordenador, Concluídos continua 1 (escopo da #40).
/// 5. Em Alertas, o cartão concluído mostra "Status: Concluído" e "Concluído
///    às HH:MM"; o filtro de status "Concluído" deixa só ele.
///
/// **A conversa com o script** é por linhas marcadoras impressas aqui
/// (`E2E_RECONHECER`, `E2E_CONCLUIR`, `E2E_CONCLUIR_SEM_MICROAREA`;
/// `E2E_PAINEL_RECONHECIDO`, `E2E_PAINEL_CONCLUIDO` e
/// `E2E_ALERTAS_CONCLUIDO_OK` são só evidência): o teste roda no aparelho e não
/// alcança o banco; o script lê a saída do `flutter test` em tempo real e age
/// no host. Os ids chegam por `--dart-define` (UUIDs sintéticos).
///
/// Sufixo `_e2e.dart` (não `_test.dart`): `flutter test integration_test`
/// descobre `*_test.dart` e o `e2e.sh --full` rodaria isto contra a stack de
/// desenvolvimento, onde não há fixtures nem relé.
///
/// PRIVACIDADE: só fixtures sintéticas. Senha, código de ativação e segredo
/// TOTP nunca vão para log; as linhas impressas levam só ids sintéticos.
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/core/auth/admin_auth_bootstrap.dart';
import 'package:sinalacs_admin/core/auth/backend_config.dart';

import 'support/e2e_admin.dart' show relayBase;
import 'support/totp.dart';

/// `adminAlertIds[0]` do manifesto: vermelho pendente semeado.
const _alertaPendente = String.fromEnvironment('E2E_ALERTA_PENDENTE');

/// `adminAlertIds[1]` do manifesto: vermelho reconhecido semeado.
const _alertaReconhecido = String.fromEnvironment('E2E_ALERTA_RECONHECIDO');

/// Atraso máximo aceito para o Painel refletir uma transição feita no banco:
/// um pulso (30 s) + o UPDATE (~1 s) + folga.
const _atrasoMaximoDoPainel = Duration(seconds: 40);

int _passo(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ 30;

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

/// A linha [rotulo] do Painel mostra [valor]? A linha é a `_InfoRow` (o
/// `Padding` mais próximo do rótulo), para o número não casar com outro
/// contador da tela.
bool _linhaDoPainel(String rotulo, String valor) {
  final r = find.text(rotulo);
  if (r.evaluate().isEmpty) return false;
  final linha = find.ancestor(of: r, matching: find.byType(Padding)).first;
  return find.descendant(of: linha, matching: find.text(valor)).evaluate().isNotEmpty;
}

/// O cartão "Vermelho" do Painel mostra [valor]?
bool _vermelhoNoPainel(String valor) =>
    find.descendant(of: find.byKey(const Key('risk_counter_red')), matching: find.text(valor)).evaluate().isNotEmpty;

Finder _cartao(String alertId) => find.byKey(Key('alert_$alertId'));

bool _noCartao(String alertId, Finder alvo) =>
    find.descendant(of: _cartao(alertId), matching: alvo).evaluate().isNotEmpty;

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

/// Login do coordenador pela tela: primeiro acesso, com a ativação da MFA.
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

/// Espera o Painel mostrar [abertos]/[reconhecidos]/[concluidos] só pelo pulso
/// e devolve o atraso medido desde [pedido].
Future<Duration> _painelEm(
  WidgetTester tester, {
  required DateTime pedido,
  required String abertos,
  required String reconhecidos,
  required String concluidos,
  required String motivo,
}) async {
  await _pumpUntil(
    tester,
    () =>
        _linhaDoPainel('Abertos (pendentes)', abertos) &&
        _linhaDoPainel('Reconhecidos (em atendimento)', reconhecidos) &&
        _linhaDoPainel('Concluídos', concluidos),
    timeout: _atrasoMaximoDoPainel + const Duration(seconds: 20),
    motivo: motivo,
  );
  final atraso = DateTime.now().difference(pedido);
  expect(atraso, lessThanOrEqualTo(_atrasoMaximoDoPainel), reason: 'o painel demorou ${atraso.inSeconds}s: $motivo');
  // A soma fecha com o cartão Vermelho (INV-03), que não muda nesta jornada.
  expect(_vermelhoNoPainel('2'), isTrue, reason: 'o cartão Vermelho deveria seguir 2');
  return atraso;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('alerta vermelho concluído continua visível nos Indicadores e na lista (#87)', (tester) async {
    expect(AdminBackendConfig.host, startsWith('https://'));
    expect(_alertaPendente, isNotEmpty, reason: 'falta --dart-define=E2E_ALERTA_PENDENTE (rode pelo script)');
    expect(_alertaReconhecido, isNotEmpty, reason: 'falta --dart-define=E2E_ALERTA_RECONHECIDO (rode pelo script)');

    final ca = (await rootBundle.load(adminRpcCaAsset)).buffer.asUint8List();
    final fiacao = buildAdminWiring(caBytes: ca);
    await tester.pumpWidget(SinalAdminApp(auth: fiacao.auth, dataSourceFor: fiacao.dataSourceFor));
    await tester.pump(const Duration(milliseconds: 500));
    await _entrar(tester);
    expect(_painelAberto, isTrue);

    // 1. Painel parado, com os 3 alertas semeados.
    final rotuloAbertos = find.text('Abertos (pendentes)');
    await tester.scrollUntilVisible(rotuloAbertos, 200, scrollable: find.byType(Scrollable).last, maxScrolls: 30);
    await _pumpUntil(tester, () => _linhaDoPainel('Abertos (pendentes)', '1'), motivo: 'o painel com 1 vermelho aberto');
    expect(find.text('Concluídos'), findsOneWidget, reason: '#87: o Painel não tem a linha "Concluídos"');
    expect(_linhaDoPainel('Reconhecidos (em atendimento)', '1'), isTrue, reason: 'Reconhecidos (em atendimento) = 1');
    expect(_linhaDoPainel('Concluídos', '0'), isTrue, reason: 'Concluídos = 0');
    expect(_vermelhoNoPainel('2'), isTrue);

    // 2. O ACS reconhece o pendente (UPDATE pelo script). Só o pulso traz o
    // novo estado: nada de aba, filtro ou toque.
    var pedido = DateTime.now();
    // ignore: avoid_print
    print('E2E_RECONHECER id=$_alertaPendente');
    var atraso = await _painelEm(tester,
        pedido: pedido, abertos: '0', reconhecidos: '2', concluidos: '0', motivo: 'o pendente virar reconhecido');
    // ignore: avoid_print
    print('E2E_PAINEL_RECONHECIDO atraso_ms=${atraso.inMilliseconds}');

    // 3. O ACS conclui o reconhecido semeado: sai de Reconhecidos e ENTRA em
    // Concluídos — nunca some.
    pedido = DateTime.now();
    // ignore: avoid_print
    print('E2E_CONCLUIR id=$_alertaReconhecido');
    atraso = await _painelEm(tester,
        pedido: pedido, abertos: '0', reconhecidos: '1', concluidos: '1', motivo: 'o reconhecido virar concluído');
    // ignore: avoid_print
    print('E2E_PAINEL_CONCLUIDO atraso_ms=${atraso.inMilliseconds}');

    // 4. Um concluído SEM microárea é só do administrador (#40): o Painel do
    // coordenador não o conta. 40 s cobrem mais de um pulso.
    // ignore: avoid_print
    print('E2E_CONCLUIR_SEM_MICROAREA');
    await tester.pump(_atrasoMaximoDoPainel);
    await tester.pump();
    expect(_linhaDoPainel('Concluídos', '1'), isTrue, reason: 'o concluído sem microárea não é da UBS do coordenador');
    expect(_vermelhoNoPainel('2'), isTrue);

    // 5. Alertas (leitura nova): o cartão concluído com o estado e a hora.
    await _irPara(tester, const ['Alertas']);
    await _pumpUntil(tester, () => _cartao(_alertaReconhecido).evaluate().isNotEmpty, motivo: 'a lista de alertas');
    await tester.scrollUntilVisible(_cartao(_alertaReconhecido), 200, scrollable: find.byType(Scrollable).last, maxScrolls: 30);
    expect(_noCartao(_alertaReconhecido, find.text('Status: Concluído')), isTrue, reason: 'o cartão concluído mostra o estado');
    expect(_noCartao(_alertaReconhecido, find.textContaining('Concluído às')), isTrue, reason: 'o cartão concluído mostra a hora');
    await tester.scrollUntilVisible(_cartao(_alertaPendente), 200, scrollable: find.byType(Scrollable).last, maxScrolls: 30);
    expect(_noCartao(_alertaPendente, find.text('Status: Reconhecido')), isTrue);
    expect(_noCartao(_alertaPendente, find.textContaining('Concluído às')), isFalse);

    // O filtro "Concluído" deixa só o concluído. (Fora dos trechos de pulso:
    // aqui a leitura é pedida pela pessoa.)
    await _tocar(tester, find.byKey(const Key('alerts_status_filter')));
    await _tocar(tester, find.text('Concluído').last);
    await _pumpUntil(
      tester,
      () => _cartao(_alertaReconhecido).evaluate().isNotEmpty && _cartao(_alertaPendente).evaluate().isEmpty,
      motivo: 'o filtro Concluído deixar só o concluído',
    );
    // ignore: avoid_print
    print('E2E_ALERTAS_CONCLUIDO_OK');
  });
}
