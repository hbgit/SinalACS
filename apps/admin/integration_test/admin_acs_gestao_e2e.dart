/// Gestão de contas do backoffice (issue #43) no emulador, contra o BANCO DE
/// TESTE: cadastro de ACS com senha inicial mostrada uma vez, vínculo de
/// microárea, redefinição da MFA do ACS e da equipe, (des)ativação do acesso e
/// o escopo do papel `coordinator`. Rodado por
/// `scripts/qa/admin_acs_gestao_e2e.sh`.
///
/// Cada mutação feita pela TELA é conferida por RPC direto no servidor real
/// (`sinalacs_client`), e o script confere o resto no banco de teste por SQL:
/// nenhuma prova se apoia só no que a tela desenhou.
///
/// O relé (`scripts/qa/otp_relay.py`) entrega as credenciais sintéticas da
/// execução: `/admin` (bloco `staff` do manifesto) e `/coordenador` (bloco
/// `coordinator`), cada uma **uma única vez** — daí a memorização.
///
/// Os testes dependem da ordem, como em `admin_login_e2e.dart`: o ACS criado no
/// primeiro é o que o coordenador enxerga e o que o administrador desativa e
/// redefine; o segredo TOTP nasce na ativação da MFA e é usado nos logins
/// seguintes; e o código de ativação do coordenador, emitido pelo reset do
/// administrador, é o que o RPC final consome.
///
/// Sufixo `_e2e.dart` (não `_test.dart`): `flutter test integration_test`
/// descobre `*_test.dart` e o `e2e.sh --full` rodaria isto contra a stack de
/// desenvolvimento, onde não há fixtures nem relé.
///
/// PRIVACIDADE: só fixtures sintéticas. Senha, código de ativação e segredo
/// TOTP nunca vão para log; a única linha impressa é a marcadora
/// `E2E_ACS_CRIADO`, com nome e matrícula sintéticos, que o script lê para os
/// asserts em SQL (o manifesto fica no host, o teste roda no aparelho).
@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_admin/app/admin_accounts.dart' show chaveConfirmarAcao;
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/core/auth/admin_auth_bootstrap.dart';
import 'package:sinalacs_admin/core/auth/backend_config.dart';
import 'package:sinalacs_client/sinalacs_client.dart';

import 'support/e2e_admin.dart';
import 'support/totp.dart';

/// Aparelho do login do ACS criado (D8 do plano 2026-10-03): com ele o login
/// emite refresh token, e é o token de envio diferido que a desativação revoga.
const _deviceId = 'e2e-dev-1';

int _passo(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ 30;

/// Credencial do relé: matrícula, senha e o código de ativação da MFA (#48).
typedef _CredencialDoRele = ({String matricula, String senha, String activationCode});

/// Estado de UMA conta do backoffice no aparelho.
///
/// O `segredoBase32` só existe na ativação da MFA (a tela mostra uma vez); o
/// `ultimoPasso` é o último passo TOTP ACEITO pelo servidor para esta conta —
/// o replay é barrado, então o próximo login precisa de um passo maior, e a
/// contagem é por conta (`user_credentials.totpLastStep`).
class _ContaDoBackoffice {
  _ContaDoBackoffice({required this.matricula, required this.senha, this.codigoDeAtivacao});

  final String matricula;
  final String senha;
  final String? codigoDeAtivacao;
  String? segredoBase32;
  int? ultimoPasso;

  Uint8List get segredo => base32Decode(segredoBase32!);
}

late _ContaDoBackoffice _admin;
late _ContaDoBackoffice _coordenador;

/// Id do ACS criado (o `sub` do token) e nome/matrícula sintéticos da execução:
/// é por eles que os testes seguintes acham o cartão e que o script monta os
/// asserts em SQL.
late String _acsCriadoId;
late String _acsCriadoNome;
late String _acsCriadaMatricula;

Client? _rpc;

/// Cliente RPC para as provas diretas no servidor — a MESMA CA e o mesmo host
/// que o app usa (`buildAdminWiring`), para a prova falar com o mesmo backend.
Future<Client> _clienteRpc() async {
  final existente = _rpc;
  if (existente != null) return existente;
  final ca = (await rootBundle.load(adminRpcCaAsset)).buffer.asUint8List();
  return _rpc = Client(
    AdminBackendConfig.requireSecureHost(AdminBackendConfig.host),
    securityContext: SecurityContext()..setTrustedCertificatesBytes(ca),
  )..connectivityMonitor = null;
}

/// Id do usuário que o servidor pôs no token (`sub`), lido **sem** verificar a
/// assinatura (papel do servidor, como em `AdminSession.fromToken`): a lista de
/// ACS mostra nome e matrícula, nunca o id, e é o id que endereça o cartão
/// (`acs_<id>`) — o ACS criado pela tela nasce com um UUID que só o servidor
/// conhece.
String _subDoToken(String accessToken) {
  final partes = accessToken.split('.');
  if (partes.length != 3) throw StateError('token sem três seções');
  final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(partes[1])))) as Map<String, dynamic>;
  return payload['sub'] as String;
}

/// Credencial do coordenador sintético (bloco `coordinator` do manifesto),
/// entregue pelo relé em `/coordenador` uma única vez.
///
/// A busca vive aqui, e não em `support/e2e_admin.dart`, porque aquele apoio
/// atende só `/admin` e esta tarefa não o altera; `relayBase` é o mesmo.
Future<_CredencialDoRele> _coordenadorDoRele() async {
  final jaBuscada = _credencialDoCoordenador;
  if (jaBuscada != null) return jaBuscada;
  return _credencialDoCoordenador = await _buscar('/coordenador');
}

_CredencialDoRele? _credencialDoCoordenador;

Future<_CredencialDoRele> _buscar(String rota) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(relayBase).replace(path: rota));
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode != 200) throw StateError('o relé respondeu ${response.statusCode} a $rota');
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

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 30),
  Duration step = const Duration(milliseconds: 200),
}) async {
  final fim = DateTime.now().add(timeout);
  while (!done() && DateTime.now().isBefore(fim)) {
    await tester.pump(step);
  }
  if (done()) return;
  final telas = <String>[
    for (final k in const ['login_error', 'login_aviso', 'activation_error', 'mfa_error', 'cadastro_erro'])
      if (find.byKey(Key(k)).evaluate().isNotEmpty)
        '$k=${find.descendant(of: find.byKey(Key(k)), matching: find.byType(Text), matchRoot: true).evaluate().map((e) => (e.widget as Text).data).join(' ')}',
  ];
  fail('condição não atingida em ${timeout.inSeconds}s; tela: ${telas.isEmpty ? '(nada)' : telas.join('; ')}');
}

bool _existe(String chave) => find.byKey(Key(chave)).evaluate().isNotEmpty;

bool get _painelAberto => find.text('Painel de Indicadores').evaluate().isNotEmpty;

Finder get _lista => find.byType(Scrollable).last;

/// Vai ao topo da lista.
///
/// A lista das Microáreas é mais alta que a tela e **preguiçosa**: um cartão que
/// saiu de cena não existe mais na árvore, e `ensureVisible` não acha o que não
/// foi construído. Rolar não é zelo: um `tap` num widget fora da tela não lança
/// nada — apenas erra o alvo, e o teste seguiria como se tivesse tocado.
Future<void> _rolarAoTopo(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    if (find.byType(Scrollable).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 200));
      continue;
    }
    final posicao = tester.state<ScrollableState>(_lista).position;
    if (posicao.pixels <= 0) return;
    await tester.drag(_lista, const Offset(0, 400));
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Rola para baixo — em passos de 320dp, como o harness de layout — até
/// [condicao] valer, e FALHA dizendo o que faltou.
///
/// A condição é a própria asserção, e não "o cartão existe": depois de uma
/// escrita a tela troca a lista pelo indicador e a recarrega do servidor, então
/// um cartão achado no instante seguinte ao diálogo ainda é o antigo. Rolar
/// dentro da espera é o que faz a condição olhar para o item certo quando a
/// lista é preguiçosa.
Future<void> _rolarAte(
  WidgetTester tester,
  bool Function() condicao, {
  required String oQue,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final fim = DateTime.now().add(timeout);
  while (!condicao() && DateTime.now().isBefore(fim)) {
    if (find.byType(Scrollable).evaluate().isNotEmpty) {
      await tester.drag(_lista, const Offset(0, -320));
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
  if (!condicao()) fail('$oQue não aconteceu em ${timeout.inSeconds}s');
}

/// Rola até o fim da tela.
///
/// A ausência de uma seção só é significativa depois de passar por tudo: um
/// widget abaixo da dobra não está na árvore, e `findsNothing` passaria por ele
/// nunca ter sido construído — não por não existir.
Future<void> _rolarAteOFim(WidgetTester tester) async {
  var anterior = -1.0;
  for (var i = 0; i < 40; i++) {
    final posicao = tester.state<ScrollableState>(_lista).position;
    if (posicao.pixels >= posicao.maxScrollExtent || posicao.pixels == anterior) return;
    anterior = posicao.pixels;
    await tester.drag(_lista, const Offset(0, -320));
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _tocar(WidgetTester tester, Finder alvo) async {
  await _rolarAoTopo(tester);
  await _rolarAte(tester, () => alvo.evaluate().isNotEmpty, oQue: 'o alvo do toque na tela');
  await tester.ensureVisible(alvo);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(alvo);
}

/// Espera a seção sair do estado ocupado, olhando um botão dela.
///
/// Durante uma escrita a seção desabilita os botões, e tocar num botão
/// desabilitado **não lança**: apenas não acontece nada, e o passo seguinte
/// esperaria por um diálogo que nunca abriria. A segunda redefinição de MFA não
/// muda nada visível no cartão (a MFA já estava redefinida; o que muda é o
/// segredo pendente, que a tela não mostra) — então é este, e não o texto do
/// cartão, o sinal de que a escrita terminou.
Future<void> _esperarAcoesLivres(WidgetTester tester, String chaveDoBotao) => _rolarAte(
      tester,
      () {
        final botao = find.byKey(Key(chaveDoBotao));
        if (botao.evaluate().isEmpty) return false;
        return tester.widget<OutlinedButton>(botao).onPressed != null;
      },
      oQue: 'a seção livre para a próxima ação',
    );

Future<void> _digitar(WidgetTester tester, String chave, String texto) async {
  final campo = find.byKey(Key(chave));
  await tester.ensureVisible(campo);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.enterText(campo, texto);
}

/// Escolhe a microárea num dos dropdowns dos diálogos (#43).
///
/// `.last` no item: o nome também está no cartão da microárea, atrás do diálogo,
/// e no próprio botão quando ele já tem valor — o item aberto é o último.
Future<void> _escolherMicroArea(WidgetTester tester, String chaveDoCampo, String nome) async {
  await _tocar(tester, find.byKey(Key(chaveDoCampo)));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text(nome).last);
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _abrirApp(WidgetTester tester) async {
  final ca = (await rootBundle.load(adminRpcCaAsset)).buffer.asUint8List();
  final fiacao = buildAdminWiring(caBytes: ca);
  await tester.pumpWidget(SinalAdminApp(auth: fiacao.auth, dataSourceFor: fiacao.dataSourceFor));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _irPara(WidgetTester tester, String destino) async {
  await _tocar(tester, find.text(destino).last);
  await tester.pump(const Duration(milliseconds: 300));
}

/// Entra pela tela. No primeiro acesso a conta não tem MFA e a tela abre a
/// ativação (o código vem do relé); nas seguintes, o campo do código aparece
/// direto.
Future<void> _entrar(WidgetTester tester, _ContaDoBackoffice conta) async {
  await _digitar(tester, 'matricula_field', conta.matricula);
  await _digitar(tester, 'senha_field', conta.senha);
  await _tocar(tester, find.byKey(const Key('login_button')));

  await _pumpUntil(
    tester,
    () => _existe('activation_code_field') || _existe('totp_field') || _existe('login_error') || _painelAberto,
  );
  if (_existe('activation_code_field')) await _ativarMfa(tester, conta);

  await _pumpUntil(tester, () => _existe('totp_field') || _existe('login_error') || _painelAberto);
  if (_existe('totp_field')) await _informarCodigo(tester, conta);

  await _pumpUntil(tester, () => _painelAberto || _existe('login_error'));
  expect(
    _existe('login_error'),
    isFalse,
    reason: _existe('login_error') ? (tester.widget<Text>(find.byKey(const Key('login_error'))).data ?? '') : '',
  );
  expect(_painelAberto, isTrue, reason: 'o login não abriu o painel');
}

/// Ativação da MFA pela tela (primeiro acesso): o código de ativação libera o
/// segredo, e o código do autenticador confirma. O passo confirmado já foi
/// aceito pelo servidor, então o login seguinte precisa de um passo maior.
Future<void> _ativarMfa(WidgetTester tester, _ContaDoBackoffice conta) async {
  await _digitar(tester, 'activation_code_field', conta.codigoDeAtivacao!);
  await _tocar(tester, find.byKey(const Key('activation_continue')));
  await _pumpUntil(tester, () => _existe('mfa_secret') || _existe('mfa_error'), timeout: const Duration(seconds: 60));
  expect(_existe('mfa_error'), isFalse,
      reason: _existe('mfa_error') ? (tester.widget<Text>(find.byKey(const Key('mfa_error'))).data ?? '') : '');
  conta.segredoBase32 = tester.widget<SelectableText>(find.byKey(const Key('mfa_secret'))).data!;
  expect(conta.segredoBase32, isNotEmpty);

  final instante = DateTime.now();
  conta.ultimoPasso = _passo(instante);
  await _digitar(tester, 'mfa_code_field', totpCode(conta.segredo, instante));
  await _tocar(tester, find.byKey(const Key('mfa_confirm_button')));
}

/// Informa o código do autenticador num passo NOVO: o servidor barra o replay
/// (o `UPDATE` de `totpLastStep` só avança), então reentrar exige esperar o
/// relógio de 30 s passar do passo da ativação ou do login anterior.
Future<void> _informarCodigo(WidgetTester tester, _ContaDoBackoffice conta) async {
  await _pumpUntil(
    tester,
    () => _passo(DateTime.now()) > conta.ultimoPasso!,
    timeout: const Duration(seconds: 40),
    step: const Duration(milliseconds: 500),
  );
  final instante = DateTime.now();
  conta.ultimoPasso = _passo(instante);
  await _digitar(tester, 'totp_field', totpCode(conta.segredo, instante));
  await _tocar(tester, find.byKey(const Key('login_button')));
}

/// Cadastro de ACS pela tela: "Novo ACS" → nome, matrícula e microárea →
/// confirmar → a senha inicial aparece uma única vez. Devolve a senha lida.
Future<String> _cadastrarAcs(
  WidgetTester tester, {
  required String nome,
  required String matricula,
  required String microArea,
}) async {
  await _tocar(tester, find.byKey(const Key('novo_acs')));
  await _pumpUntil(tester, () => _existe('acs_nome_field'));
  // O botão de confirmar só habilita com os três campos preenchidos.
  expect(
    tester.widget<FilledButton>(find.byKey(chaveConfirmarAcao)).onPressed,
    isNull,
    reason: 'o formulário vazio não pode habilitar o cadastro',
  );
  await _digitar(tester, 'acs_nome_field', nome);
  await _digitar(tester, 'acs_matricula_field', matricula);
  await _escolherMicroArea(tester, 'acs_microarea_field', microArea);
  expect(tester.widget<FilledButton>(find.byKey(chaveConfirmarAcao)).onPressed, isNotNull);

  await _tocar(tester, find.byKey(chaveConfirmarAcao));
  // Derivar o Argon2id da senha inicial é do servidor: o diálogo da credencial
  // só abre depois da resposta.
  await _pumpUntil(tester, () => _existe('senha_inicial') || _existe('cadastro_erro'), timeout: const Duration(seconds: 60));
  expect(_existe('cadastro_erro'), isFalse,
      reason: _existe('cadastro_erro') ? (tester.widget<Text>(find.byKey(const Key('cadastro_erro'))).data ?? '') : '');
  final senha = tester.widget<SelectableText>(find.byKey(const Key('senha_inicial'))).data!;
  expect(senha, isNotEmpty);
  await _tocar(tester, find.byKey(const Key('fechar_credencial')));
  await _pumpUntil(tester, () => !_existe('senha_inicial'));
  return senha;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('admin cadastra um ACS, vincula, redefine a MFA e desativa — cada passo provado por RPC',
      (tester) async {
    expect(AdminBackendConfig.host, startsWith('https://'));
    await _abrirApp(tester);
    final cred = await adminCredentialFromRelay();
    _admin = _ContaDoBackoffice(matricula: cred.matricula, senha: cred.senha, codigoDeAtivacao: cred.activationCode);
    await _entrar(tester, _admin);

    await _irPara(tester, 'Microáreas');
    await _pumpUntil(tester, () => _existe('novo_acs'));

    // 1. Cadastro pela tela (passos 1 do plano 12).
    final carimbo = DateTime.now().millisecondsSinceEpoch;
    _acsCriadoNome = 'E2E ACS $carimbo';
    _acsCriadaMatricula = 'E2E-ACS-$carimbo';
    final senhaInicial = await _cadastrarAcs(
      tester,
      nome: _acsCriadoNome,
      matricula: _acsCriadaMatricula,
      microArea: 'Microárea E2E',
    );

    // A ponte aparelho → host: o manifesto (com o id) fica no host, o teste roda
    // no emulador, e o script precisa da matrícula e do nome para os asserts em
    // SQL. Nome e matrícula são sintéticos — nada de dado real.
    // ignore: avoid_print
    print('E2E_ACS_CRIADO matricula=$_acsCriadaMatricula nome=$_acsCriadoNome');

    // 2. Prova por RPC: a senha mostrada uma única vez é a credencial de
    // verdade. Com `deviceId` o login emite o refresh token que a desativação
    // vai ter de revogar.
    final client = await _clienteRpc();
    final login = await client.auth.loginInstitutional(
      matricula: _acsCriadaMatricula,
      password: senhaInicial,
      deviceId: _deviceId,
    );
    expect(login.accessToken, isNotEmpty);
    expect(login.refreshToken, isNotNull, reason: 'login com deviceId emite refresh token');
    final tokenDeRefresh = login.refreshToken!;
    _acsCriadoId = _subDoToken(login.accessToken);

    // 3. MFA do ACS ativada por RPC: a tela do ACS não é o assunto deste e2e; o
    // que se prova adiante é que a redefinição da coordenação apaga este
    // segredo, e o `beginTotpEnrollment` seguinte já responde outro.
    final inicio = await client.auth.beginTotpEnrollment(
      matricula: _acsCriadaMatricula,
      password: senhaInicial,
    );
    final segredoDoAcs = base32Decode(inicio.secretBase32);
    await client.auth.confirmTotpEnrollment(
      matricula: _acsCriadaMatricula,
      password: senhaInicial,
      code: totpCode(segredoDoAcs, DateTime.now()),
    );

    // 4. Vínculo de microárea pela tela. O diálogo não pede segunda confirmação,
    // mas só habilita com uma microárea DIFERENTE da atual.
    final cartaoDoAcs = find.byKey(Key('acs_$_acsCriadoId'));
    await _tocar(tester, find.byKey(Key('vincular_acs_$_acsCriadoId')));
    await _pumpUntil(tester, () => _existe('vincular_microarea_field'));
    expect(
      tester.widget<FilledButton>(find.byKey(chaveConfirmarAcao)).onPressed,
      isNull,
      reason: 'sem uma microárea nova escolhida o vínculo não pode habilitar',
    );
    await _escolherMicroArea(tester, 'vincular_microarea_field', 'Outra Microárea E2E');
    expect(tester.widget<FilledButton>(find.byKey(chaveConfirmarAcao)).onPressed, isNotNull);
    await _tocar(tester, find.byKey(chaveConfirmarAcao));

    // O estado que a tela mostra vem do servidor: o cartão passa a exibir o
    // território novo depois de a lista recarregar.
    await _rolarAte(
      tester,
      () => find.descendant(of: cartaoDoAcs, matching: find.text('Território: Outra Microárea E2E')).evaluate().isNotEmpty,
      oQue: 'o cartão do ACS no território novo',
    );

    // 5. Redefinição da MFA do ACS pela tela (ação destrutiva: confirmação).
    await _tocar(tester, find.byKey(Key('redefinir_mfa_$_acsCriadoId')));
    await _pumpUntil(tester, () => _existe('confirmar_acao'));
    await _tocar(tester, find.byKey(chaveConfirmarAcao));
    await _rolarAte(
      tester,
      () => find.descendant(of: cartaoDoAcs, matching: find.text('MFA não ativada')).evaluate().isNotEmpty,
      oQue: 'o cartão do ACS com a MFA redefinida',
    );

    // Prova por RPC: com o segredo apagado, `beginTotpEnrollment` volta a
    // responder — e com um segredo NOVO, que é o que prova que o antigo não
    // vale mais.
    final reinicio = await client.auth.beginTotpEnrollment(
      matricula: _acsCriadaMatricula,
      password: senhaInicial,
    );
    expect(reinicio.secretBase32, isNotEmpty);
    expect(reinicio.secretBase32, isNot(equals(inicio.secretBase32)));

    // A prova acima gravou um segredo PENDENTE (`totpSecretEncrypted`), e o
    // assert final do script exige a conta com as quatro colunas `totp*` nulas:
    // a última palavra sobre a MFA desta conta tem de ser a redefinição.
    await _tocar(tester, find.byKey(Key('redefinir_mfa_$_acsCriadoId')));
    await _pumpUntil(tester, () => _existe('confirmar_acao'));
    await _tocar(tester, find.byKey(chaveConfirmarAcao));
    await _rolarAte(
      tester,
      () => find.descendant(of: cartaoDoAcs, matching: find.text('MFA não ativada')).evaluate().isNotEmpty,
      oQue: 'o cartão do ACS sem MFA pendente',
    );
    await _esperarAcoesLivres(tester, 'desativar_acs_$_acsCriadoId');

    // 6. Desativação pela tela (destrutiva: confirmação).
    await _tocar(tester, find.byKey(Key('desativar_acs_$_acsCriadoId')));
    await _pumpUntil(tester, () => _existe('confirmar_acao'));
    await _tocar(tester, find.byKey(chaveConfirmarAcao));
    await _rolarAte(
      tester,
      () => find.descendant(of: cartaoDoAcs, matching: find.text('Inativo')).evaluate().isNotEmpty,
      oQue: 'o cartão do ACS desativado',
    );

    // 7. Prova por RPC: o login passa a recusar com a mensagem de acesso
    // inativo, e a renovação da sessão cai — a família inteira foi revogada na
    // mesma transação da flag.
    await expectLater(
      client.auth.loginInstitutional(matricula: _acsCriadaMatricula, password: senhaInicial, deviceId: _deviceId),
      throwsA(isA<AuthenticationFailedException>().having((e) => e.message, 'message', 'Este acesso está inativo.')),
    );
    await expectLater(
      client.auth.refreshSession(refreshToken: tokenDeRefresh, deviceId: _deviceId),
      throwsA(isA<SessionExpiredException>()),
    );
  });

  testWidgets('coordenador entra, não vê a equipe do backoffice e cadastra outro ACS na própria UBS',
      (tester) async {
    await _abrirApp(tester);
    final cred = await _coordenadorDoRele();
    _coordenador =
        _ContaDoBackoffice(matricula: cred.matricula, senha: cred.senha, codigoDeAtivacao: cred.activationCode);
    await _entrar(tester, _coordenador);

    await _irPara(tester, 'Microáreas');
    await _pumpUntil(tester, () => _existe('novo_acs'));

    // Escopo POSITIVO: o ACS criado pelo administrador é da mesma UBS (as duas
    // microáreas são dela), então o coordenador o enxerga.
    final cartaoDoAcs = find.byKey(Key('acs_$_acsCriadoId'));
    await _rolarAte(tester, () => cartaoDoAcs.evaluate().isNotEmpty, oQue: 'o ACS criado pelo administrador na lista do coordenador');
    expect(
      find.descendant(of: cartaoDoAcs, matching: find.text('Território: Outra Microárea E2E')),
      findsOneWidget,
    );

    // Escopo do PAPEL: a seção de equipe do backoffice não existe para o
    // coordenador (o servidor também recusa essa listagem para ele). A
    // asserção vale depois de rolar a tela inteira — um rodapé que nunca foi
    // construído também não apareceria.
    await _rolarAteOFim(tester);
    expect(find.text('Equipe do backoffice'), findsNothing);
    expect(find.textContaining('A redefinição de MFA é feita por outro administrador'), findsNothing);

    // E o coordenador cadastra na própria UBS: cadastro não é exclusividade do
    // administrador, é escopo.
    final carimbo = DateTime.now().millisecondsSinceEpoch;
    final senhaInicial = await _cadastrarAcs(
      tester,
      nome: 'E2E ACS B $carimbo',
      matricula: 'E2E-ACS-B-$carimbo',
      microArea: 'Microárea E2E',
    );
    await _rolarAte(
      tester,
      () => find.text('E2E ACS B $carimbo').evaluate().isNotEmpty,
      oQue: 'o segundo ACS cadastrado pelo coordenador',
    );

    // Prova por RPC: a senha inicial que a tela mostrou entra no servidor de
    // verdade (mesma prova do primeiro cadastro, agora pelo caminho do papel
    // `coordinator`).
    final client = await _clienteRpc();
    final login = await client.auth.loginInstitutional(
      matricula: 'E2E-ACS-B-$carimbo',
      password: senhaInicial,
      deviceId: _deviceId,
    );
    expect(login.accessToken, isNotEmpty);
  });

  testWidgets('admin redefine a MFA do coordenador e o código emitido pela tela ativa a MFA nova',
      (tester) async {
    await _abrirApp(tester);
    await _entrar(tester, _admin);
    await _irPara(tester, 'Microáreas');
    await _pumpUntil(tester, () => _existe('novo_acs'));

    // O relé entrega matrícula, senha e código de ativação, nunca o UUID — quem
    // lê o id do manifesto é o script. O cartão se acha pela matrícula, e o
    // botão é o único do cartão (é ele que carrega a chave
    // `redefinir_mfa_staff_<id>`).
    final cartaoDoCoordenador = find.ancestor(
      of: find.text('Matrícula: ${_coordenador.matricula} • Coordenador'),
      matching: find.byType(Card),
    );
    await _rolarAte(tester, () => cartaoDoCoordenador.evaluate().isNotEmpty, oQue: 'o cartão do coordenador');
    final botaoRedefinirMfa = find.descendant(of: cartaoDoCoordenador, matching: find.byType(OutlinedButton));
    expect(botaoRedefinirMfa, findsOneWidget);

    await _tocar(tester, botaoRedefinirMfa);
    await _pumpUntil(tester, () => _existe('confirmar_acao'));
    await _tocar(tester, find.byKey(chaveConfirmarAcao));

    // O código de ativação novo existe só nesta resposta (#48): a tela mostra
    // uma vez e o servidor guarda só o hash.
    await _pumpUntil(tester, () => _existe('codigo_ativacao'), timeout: const Duration(seconds: 60));
    final codigoNovo = tester.widget<SelectableText>(find.byKey(const Key('codigo_ativacao'))).data!;
    expect(codigoNovo, isNotEmpty);
    expect(codigoNovo, isNot(equals(_coordenador.codigoDeAtivacao)));
    await _tocar(tester, find.byKey(const Key('fechar_credencial')));
    await _pumpUntil(tester, () => !_existe('codigo_ativacao'));

    // Prova por RPC: o código emitido pela tela ativa a MFA nova — e o segredo
    // é outro, porque o antigo foi apagado pela redefinição.
    final client = await _clienteRpc();
    final reinicio = await client.auth.beginStaffTotpEnrollment(
      matricula: _coordenador.matricula,
      password: _coordenador.senha,
      activationCode: codigoNovo,
    );
    expect(reinicio.secretBase32, isNotEmpty);
    expect(reinicio.secretBase32, isNot(equals(_coordenador.segredoBase32)));
  });
}
