/// Trilha de auditoria completa do backoffice (issue #45) no emulador, contra o
/// BANCO DE TESTE. Rodado só por `scripts/qa/admin_auditoria_e2e.sh`.
///
/// O seed (`E2E_SEED_AUDIT_TRAIL=1`) grava 60 linhas sintéticas encadeadas
/// (autores administrador, coordenador e ACS; linhas 30 e 31 com o mesmo
/// `timestamp`); as contagens esperadas chegam do manifesto por
/// `--dart-define`, nunca repetidas à mão aqui.
///
/// Jornada do administrador (1º teste):
/// 1. login pela tela (ativação da MFA da fixture);
/// 2. Auditoria: "Cadeia íntegra" ao abrir e depois de "Verificar novamente";
/// 3. filtros pela tela — ação, período (atalho de 30 dias + fim digitado no
///    seletor) e busca — e "Carregar mais" até o fim sem repetir nem pular
///    `sequence` (conferido também por RPC direto, página a página);
///    `E2E_FILTROS_OK`;
/// 4. `E2E_ADULTERAR sequence=<n>`: o SCRIPT faz `UPDATE` no banco de e2e e o
///    teste espera o servidor ver a linha `invalid` (RPC); depois de vencido o
///    cache de 60 s da verificação, "Verificar novamente" mostra "Falha de
///    integridade" com a linha `n` e, varrendo a lista inteira na tela, só a
///    linha `n` tem o selo "Adulterado?"; `E2E_ADULTERACAO_DETECTADA`;
/// 5. exportação do período: contagem e intervalo de `sequence` na tela,
///    "Copiar CSV" e leitura de volta pela área de transferência
///    (`Clipboard.getData`), conferindo o SHA-256 mostrado, as nove colunas e
///    a ausência de UUID, hash e IP; `E2E_EXPORT_FEITO`.
///
/// Jornada do coordenador (2º teste): vê só as linhas de autores da UBS dele
/// (o ACS das fixtures), não vê a seção "Exportar" em lugar nenhum da tela e o
/// `admin.exportAuditLogs` chamado direto é recusado; `E2E_FIM`.
///
/// O script confere depois, no banco, a linha `export`/`success` ligada a
/// `audit_exports`, a recusa `denied` do coordenador e o verificador CLI antes
/// e depois de restaurar a linha adulterada.
///
/// Sufixo `_e2e.dart` (não `_test.dart`): a descoberta do `flutter test
/// integration_test` e o `e2e.sh --full` não o rodam contra a stack de dev.
///
/// PRIVACIDADE: só fixtures sintéticas. Senha, código de ativação, segredo
/// TOTP, token e o conteúdo do CSV nunca vão para log; as linhas impressas
/// levam só números.
@Timeout(Duration(minutes: 12))
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/core/auth/admin_auth_backend.dart' show AdminSession;
import 'package:sinalacs_admin/core/auth/admin_auth_bootstrap.dart';
import 'package:sinalacs_admin/core/auth/backend_config.dart';
import 'package:sinalacs_client/sinalacs_client.dart' as api;

import 'support/e2e_admin.dart';
import 'support/totp.dart';

// Bloco `auditTrail` do manifesto, passado pelo script.
const _linhasSemeadas = int.fromEnvironment('E2E_AUDIT_ROWS');
const _linhasDeExportacao = int.fromEnvironment('E2E_AUDIT_EXPORT_ROWS');
const _linhasDoAcs = int.fromEnvironment('E2E_AUDIT_ACS_ROWS');
const _linhasNoPeriodo = int.fromEnvironment('E2E_AUDIT_PERIOD_ROWS');
const _primeiraNoPeriodo = int.fromEnvironment('E2E_AUDIT_PERIOD_FIRST');
const _ultimaNoPeriodo = int.fromEnvironment('E2E_AUDIT_PERIOD_LAST');
const _sequenciaAdulterada = int.fromEnvironment('E2E_AUDIT_TAMPER_SEQUENCE');

/// As nove colunas do CSV (D6), na ordem do servidor (`AuditCsv.columns`).
const _colunas = 'sequence,timestamp_utc,autor,papel_autor,acao,recurso,rotulo_recurso,resultado,selo';

/// Cache da verificação global no servidor (`AuditChainStatusService.cacheTtl`)
/// mais folga: antes disso, "Verificar novamente" devolveria o retrato antigo.
const _cacheDaVerificacao = Duration(seconds: 62);

final _reSequencia = RegExp(r'· nº (\d+)$');
const _rotulosDeSelo = {'Íntegro', 'Adulterado?', 'Não verificável'};

int _passo(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ 30;

typedef _Credencial = ({String matricula, String senha, String activationCode});

/// Sessão aberta pelo login da tela (capturada na fábrica da fonte de dados):
/// é o token dela que as provas por RPC usam, sem segundo login.
AdminSession? _sessao;

api.Client? _rpc;

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

Future<_Credencial> _coordenadorDoRele() async {
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

String _textosDaTela() =>
    find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(40).join(' | ');

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
  fail('condição não atingida em ${timeout.inSeconds}s${motivo == null ? '' : ': $motivo'}; tela: ${_textosDaTela()}');
}

bool _existe(String chave) => find.byKey(Key(chave)).evaluate().isNotEmpty;

bool get _painelAberto => find.text('Painel de Indicadores').evaluate().isNotEmpty;

/// A lista da tela (o único rolável vertical do corpo). Os campos de texto
/// também têm um `Scrollable`, mas horizontal.
Finder get _lista => find
    .byWidgetPredicate((w) => w is Scrollable && axisDirectionToAxis(w.axisDirection) == Axis.vertical)
    .first;

ScrollPosition _posicao(WidgetTester tester) => tester.state<ScrollableState>(_lista).position;

/// A lista é preguiçosa: o que está fora da janela não existe na árvore. Pula
/// para o topo e desce de 300 em 300 até [alvo] existir; `false` se chegou ao
/// fim sem achar — que, por ter passado por tudo, é prova de ausência.
Future<bool> _rolarAte(WidgetTester tester, Finder alvo) async {
  _posicao(tester).jumpTo(0);
  await tester.pump(const Duration(milliseconds: 150));
  for (var i = 0; i < 400; i++) {
    if (alvo.evaluate().isNotEmpty) {
      await tester.ensureVisible(alvo.first);
      await tester.pump(const Duration(milliseconds: 200));
      return true;
    }
    final p = _posicao(tester);
    if (p.pixels >= p.maxScrollExtent) return false;
    p.jumpTo((p.pixels + 300).clamp(0, p.maxScrollExtent));
    await tester.pump(const Duration(milliseconds: 120));
  }
  return false;
}

Future<void> _tocar(WidgetTester tester, Finder alvo, {required String oQue}) async {
  if (!await _rolarAte(tester, alvo)) fail('$oQue não está na tela; tela: ${_textosDaTela()}');
  await tester.tap(alvo.first);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tocarChave(WidgetTester tester, String chave) =>
    _tocar(tester, find.byKey(Key(chave)), oQue: chave);

Future<void> _digitar(WidgetTester tester, String chave, String texto) async {
  final campo = find.byKey(Key(chave));
  if (!await _rolarAte(tester, campo)) fail('campo $chave não está na tela');
  await tester.enterText(campo, texto);
  await tester.pump(const Duration(milliseconds: 100));
}

/// Toque fora da lista da Auditoria (login, ativação): rola até o alvo e
/// deixa o quadro assentar ANTES do toque — sem o `pump`, o toque usa a
/// posição de antes da rolagem e erra o botão (1ª execução real).
Future<void> _tocarFora(WidgetTester tester, String chave) async {
  final alvo = find.byKey(Key(chave));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.ensureVisible(alvo);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(alvo);
  await tester.pump(const Duration(milliseconds: 300));
}

/// Login de uma conta de staff da fixture: primeiro acesso, sem MFA — ativa
/// pela tela com o código de ativação e entra com o passo TOTP seguinte (o da
/// ativação já foi aceito e o replay é barrado).
Future<void> _entrar(WidgetTester tester, _Credencial cred) async {
  await tester.enterText(find.byKey(const Key('matricula_field')), cred.matricula);
  await tester.enterText(find.byKey(const Key('senha_field')), cred.senha);
  await _tocarFora(tester, 'login_button');
  await _pumpUntil(
    tester,
    () => _existe('activation_code_field') || _existe('totp_field') || _existe('login_error') || _painelAberto,
    motivo: 'resposta do login',
  );
  expect(_existe('activation_code_field'), isTrue, reason: 'a conta da fixture deveria ativar a MFA');
  await tester.enterText(find.byKey(const Key('activation_code_field')), cred.activationCode);
  await _tocarFora(tester, 'activation_continue');
  await _pumpUntil(tester, () => _existe('mfa_secret') || _existe('mfa_error'), timeout: const Duration(seconds: 60));
  expect(_existe('mfa_error'), isFalse);
  final segredo = base32Decode(tester.widget<SelectableText>(find.byKey(const Key('mfa_secret'))).data!);
  final ativacao = DateTime.now();
  await tester.enterText(find.byKey(const Key('mfa_code_field')), totpCode(segredo, ativacao));
  await _tocarFora(tester, 'mfa_confirm_button');
  await _pumpUntil(tester, () => _existe('totp_field') || _existe('login_error') || _painelAberto,
      timeout: const Duration(seconds: 60));
  if (_existe('totp_field')) {
    await _pumpUntil(tester, () => _passo(DateTime.now()) > _passo(ativacao),
        timeout: const Duration(seconds: 40), step: const Duration(milliseconds: 500));
    await tester.enterText(find.byKey(const Key('totp_field')), totpCode(segredo, DateTime.now()));
    await _tocarFora(tester, 'login_button');
  }
  await _pumpUntil(tester, () => _painelAberto || _existe('login_error'), timeout: const Duration(seconds: 60));
  expect(_existe('login_error'), isFalse,
      reason: _existe('login_error') ? (tester.widget<Text>(find.byKey(const Key('login_error'))).data ?? '') : '');
}

Future<void> _abrirApp(WidgetTester tester) async {
  final ca = (await rootBundle.load(adminRpcCaAsset)).buffer.asUint8List();
  final fiacao = buildAdminWiring(caBytes: ca);
  _sessao = null;
  await tester.pumpWidget(SinalAdminApp(
    auth: fiacao.auth,
    dataSourceFor: (sessao) {
      _sessao = sessao;
      return fiacao.dataSourceFor(sessao);
    },
  ));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _abrirAuditoria(WidgetTester tester) async {
  final destino = find.text('Auditoria');
  expect(destino, findsWidgets, reason: 'a navegação não tem "Auditoria"');
  await tester.tap(destino.last);
  await tester.pump(const Duration(milliseconds: 500));
  await _pumpUntil(tester, () => _existe('audit_chain_status'), motivo: 'a tela de Auditoria (registro do acesso)');
}

String? _texto(String chave) {
  final f = find.byKey(Key(chave));
  if (f.evaluate().isEmpty) return null;
  final w = f.evaluate().first.widget;
  if (w is Text) return w.data;
  if (w is SelectableText) return w.data;
  return find.descendant(of: f, matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data).join(' ');
}

/// Espera a lista terminar de (re)carregar e devolve "N registros carregados"
/// como número (0 para "nenhum registro").
Future<int> _esperarLista(WidgetTester tester) async {
  final fim = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(fim)) {
    await tester.pump(const Duration(milliseconds: 250));
    _posicao(tester).jumpTo(0);
    await tester.pump(const Duration(milliseconds: 100));
    final contagem = find.byKey(const Key('audit_count'));
    final carregando = find.byKey(const Key('audit_loading'));
    final vazio = find.textContaining('Nenhum registro encontrado');
    await _rolarAte(tester, find.byWidgetPredicate((w) =>
        w.key == const Key('audit_count') ||
        w.key == const Key('audit_loading') ||
        // Só os textos de lista vazia: "Nenhum filtro aplicado" (subtítulo
        // dos filtros) também começa com "Nenhum" (3ª execução real).
        (w is Text && ((w.data ?? '').startsWith('Nenhum registro') || (w.data ?? '').startsWith('Nenhum acesso')))));
    if (carregando.evaluate().isNotEmpty) continue;
    if (vazio.evaluate().isNotEmpty) return 0;
    if (contagem.evaluate().isNotEmpty) {
      final m = RegExp(r'^(\d+) registros? carregados?$').firstMatch(_texto('audit_count') ?? '');
      if (m != null) return int.parse(m[1]!);
    }
  }
  fail('a lista não terminou de carregar; tela: ${_textosDaTela()}');
}

/// Abre os filtros se estiverem fechados. A pergunta "já está aberto?" exige
/// rolar até lá: com a lista rolada para baixo o formulário sai da árvore, e
/// um `_existe` cru diria "fechado" e o toque o FECHARIA (2ª execução real).
Future<void> _abrirFiltros(WidgetTester tester) async {
  if (await _rolarAte(tester, find.byKey(const Key('audit_filter_apply')))) return;
  await _tocar(tester, find.text('Filtros'), oQue: 'o título dos filtros');
  await tester.pump(const Duration(milliseconds: 400));
  expect(_existe('audit_filter_apply'), isTrue, reason: 'os filtros não abriram');
}

Future<int> _aplicar(WidgetTester tester) async {
  await _tocarChave(tester, 'audit_filter_apply');
  expect(_existe('audit_filter_error'), isFalse, reason: _texto('audit_filter_error'));
  return _esperarLista(tester);
}

Future<int> _limpar(WidgetTester tester) async {
  await _abrirFiltros(tester);
  await _tocarChave(tester, 'audit_filter_clear');
  return _esperarLista(tester);
}

/// Período de 30 dias atrás até ontem, pela tela: o atalho preenche o início e
/// o fim é digitado no seletor de data (dd/mm/aaaa) com a hora atual. As
/// linhas semeadas no período têm de 28 a ~2,3 dias: dias de folga nas duas
/// pontas, nenhuma linha gravada durante o teste cai dentro.
Future<void> _preencherPeriodo(WidgetTester tester) async {
  await _abrirFiltros(tester);
  await _tocarChave(tester, 'audit_filter_preset_30d');
  await _tocarChave(tester, 'audit_filter_to');
  await tester.pump(const Duration(milliseconds: 600));
  final ontem = DateTime.now().subtract(const Duration(days: 1));
  String dois(int v) => v.toString().padLeft(2, '0');
  final campoData = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
  expect(campoData, findsOneWidget, reason: 'o seletor de data deveria abrir no modo de digitação');
  await tester.enterText(campoData, '${dois(ontem.day)}/${dois(ontem.month)}/${ontem.year}');
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(find.text('Confirmar').last);
  await tester.pump(const Duration(milliseconds: 800));
  expect(find.text('Hora do fim'), findsOneWidget, reason: 'o seletor de hora deveria abrir depois da data');
  await tester.tap(find.text('Confirmar').last);
  await tester.pump(const Duration(milliseconds: 800));
  expect(find.byType(Dialog), findsNothing);
  expect(_texto('audit_filter_to'), isNot(contains('não definido')));
}

/// Sequências na ordem da tela (de cima para baixo) e o selo de cada uma,
/// varrendo a lista inteira — o que a tela realmente mostra.
Future<List<(int, String)>> _varrer(WidgetTester tester) async {
  final vistos = <int, String>{};
  final ordem = <int>[];
  final cartoes = find.byWidgetPredicate(
      (w) => w is Card && w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('audit_'));
  _posicao(tester).jumpTo(0);
  await tester.pump(const Duration(milliseconds: 150));
  for (var i = 0; i < 600; i++) {
    for (final el in cartoes.evaluate()) {
      final textos = find
          .descendant(of: find.byElementPredicate((e) => e == el), matching: find.byType(Text))
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>();
      int? seq;
      String? selo;
      for (final t in textos) {
        final m = _reSequencia.firstMatch(t);
        if (m != null) seq = int.parse(m[1]!);
        if (_rotulosDeSelo.contains(t)) selo = t;
      }
      if (seq != null && selo != null && !vistos.containsKey(seq)) {
        vistos[seq] = selo;
        ordem.add(seq);
      }
    }
    final p = _posicao(tester);
    if (p.pixels >= p.maxScrollExtent) break;
    p.jumpTo((p.pixels + 300).clamp(0, p.maxScrollExtent));
    await tester.pump(const Duration(milliseconds: 100));
  }
  return [for (final s in ordem) (s, vistos[s]!)];
}

/// Toca "Carregar mais" até o botão sumir; devolve quantas páginas vieram.
Future<int> _carregarTudo(WidgetTester tester) async {
  var paginas = 1;
  while (await _rolarAte(tester, find.byKey(const Key('audit_load_more')))) {
    final antes = await _esperarLista(tester);
    await _tocarChave(tester, 'audit_load_more');
    final fim = DateTime.now().add(const Duration(seconds: 30));
    var depois = antes;
    while (depois == antes && DateTime.now().isBefore(fim)) {
      await tester.pump(const Duration(milliseconds: 300));
      depois = await _esperarLista(tester);
    }
    expect(depois, greaterThan(antes), reason: '"Carregar mais" não trouxe nada');
    paginas++;
    if (paginas > 20) fail('paginação sem fim');
  }
  return paginas;
}

/// Todas as páginas da trilha por RPC direto (escopo da sessão).
Future<List<api.AdminAuditEntry>> _trilhaPorRpc({api.AdminAuditFilter? filtro, int? antesDe}) async {
  final client = await _clienteRpc();
  final itens = <api.AdminAuditEntry>[];
  int? cursor = antesDe;
  for (var i = 0; i < 50; i++) {
    final pagina =
        await client.admin.auditLogs(accessToken: _token, filter: filtro, limit: 50, beforeSequence: cursor);
    itens.addAll(pagina.items);
    cursor = pagina.nextBeforeSequence;
    if (cursor == null) return itens;
  }
  fail('paginação por RPC sem fim');
}

/// Instante em que a tela pediu a última verificação global.
late DateTime _ultimaVerificacao;

Future<String> _verificarCadeia(WidgetTester tester, {required String esperado}) async {
  _posicao(tester).jumpTo(0);
  await tester.pump(const Duration(milliseconds: 200));
  await _pumpUntil(tester, () {
    final b = find.byKey(const Key('audit_chain_retry'));
    return b.evaluate().isNotEmpty && tester.widget<OutlinedButton>(b).onPressed != null;
  }, timeout: const Duration(seconds: 60), motivo: 'o botão "Verificar novamente" livre');
  _ultimaVerificacao = DateTime.now();
  await tester.tap(find.byKey(const Key('audit_chain_retry')));
  await tester.pump(const Duration(milliseconds: 200));
  await _pumpUntil(tester, () => !_existe('audit_chain_verifying') && _texto('audit_chain_title') == esperado,
      timeout: const Duration(seconds: 90), motivo: 'o painel da cadeia com "$esperado"');
  return _texto('audit_chain_status') ?? '';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('admin consulta, filtra e pagina a trilha, vê a adulteração e exporta o CSV', (tester) async {
    expect(AdminBackendConfig.host, startsWith('https://'));
    expect(_linhasSemeadas, greaterThan(50), reason: 'faltam os --dart-define E2E_AUDIT_* (rode pelo script)');
    for (final (nome, valor) in [
      ('E2E_AUDIT_EXPORT_ROWS', _linhasDeExportacao),
      ('E2E_AUDIT_ACS_ROWS', _linhasDoAcs),
      ('E2E_AUDIT_PERIOD_ROWS', _linhasNoPeriodo),
      ('E2E_AUDIT_PERIOD_FIRST', _primeiraNoPeriodo),
      ('E2E_AUDIT_PERIOD_LAST', _ultimaNoPeriodo),
      ('E2E_AUDIT_TAMPER_SEQUENCE', _sequenciaAdulterada),
    ]) {
      expect(valor, greaterThan(0), reason: 'falta --dart-define=$nome (rode pelo script)');
    }
    expect(_sequenciaAdulterada, inInclusiveRange(_primeiraNoPeriodo, _ultimaNoPeriodo));

    await _abrirApp(tester);
    final cred = await adminCredentialFromRelay();
    await _entrar(tester, cred);
    expect(_sessao?.role, 'admin');
    await _abrirAuditoria(tester);

    // 1. Integridade: íntegra ao abrir e depois de "Verificar novamente".
    await _pumpUntil(tester, () => _texto('audit_chain_title') == 'Cadeia íntegra',
        timeout: const Duration(seconds: 60), motivo: 'a cadeia íntegra ao abrir');
    final painel = await _verificarCadeia(tester, esperado: 'Cadeia íntegra');
    expect(painel, contains('registros conferidos'));
    // ignore: avoid_print
    print('E2E_CADEIA_INTEGRA');

    // 2. Filtros pela tela.
    final total = await _esperarLista(tester);
    expect(total, 50, reason: 'a primeira página tem 50 (há $_linhasSemeadas linhas semeadas)');

    await _abrirFiltros(tester);
    await _tocarChave(tester, 'audit_filter_action');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Exportação').last);
    await tester.pump(const Duration(milliseconds: 600));
    expect(await _aplicar(tester), _linhasDeExportacao, reason: 'filtro por ação = export');
    final exportacoes = await _varrer(tester);
    expect(exportacoes, hasLength(_linhasDeExportacao));
    expect(await _rolarAte(tester, find.textContaining('export • ')), isTrue);

    expect(await _limpar(tester), 50);
    await _preencherPeriodo(tester);
    expect(await _aplicar(tester), _linhasNoPeriodo, reason: 'filtro por período (30 dias até ontem)');
    final noPeriodo = await _varrer(tester);
    expect(noPeriodo.map((e) => e.$1).toList(),
        [for (var s = _ultimaNoPeriodo; s >= _primeiraNoPeriodo; s--) s],
        reason: 'o período traz exatamente as semeadas nele, em ordem decrescente de sequence');
    // As linhas 30 e 31 têm o mesmo timestamp: a ordem é a da sequence.
    expect(noPeriodo.indexWhere((e) => e.$1 == 31), lessThan(noPeriodo.indexWhere((e) => e.$1 == 30)));

    expect(await _limpar(tester), 50);
    await _abrirFiltros(tester);
    await _digitar(tester, 'audit_filter_search', 'escalated');
    expect(await _aplicar(tester), 1, reason: 'busca "escalated"');
    expect(await _rolarAte(tester, find.textContaining('Resultado: escalated:no_ack_timeout · nº ')), isTrue);
    expect(find.textContaining('Resultado: escalated:no_ack_timeout · nº '), findsOneWidget);

    // 3. Paginação sem filtro: "Carregar mais" até o fim, sem repetir nem pular.
    expect(await _limpar(tester), 50);
    final paginas = await _carregarTudo(tester);
    expect(paginas, greaterThanOrEqualTo(2));
    final tudo = await _varrer(tester);
    final sequencias = tudo.map((e) => e.$1).toList();
    expect(sequencias.toSet(), hasLength(sequencias.length), reason: 'sequence repetida na tela');
    expect(sequencias, [for (var s = sequencias.first; s >= 1; s--) s],
        reason: 'a tela tem de mostrar de ${sequencias.first} a 1, sem buraco');
    expect(await _esperarLista(tester), sequencias.length);
    // Por RPC: página 2 começa depois da 1, sem interseção.
    final client = await _clienteRpc();
    final p1 = await client.admin.auditLogs(accessToken: _token, limit: 50);
    final p2 = await client.admin.auditLogs(accessToken: _token, limit: 50, beforeSequence: p1.nextBeforeSequence);
    final s1 = p1.items.map((e) => e.sequence).toSet();
    expect(p2.items.where((e) => s1.contains(e.sequence)), isEmpty);
    expect(p2.items.first.sequence, lessThan(p1.items.last.sequence));
    // ignore: avoid_print
    print('E2E_FILTROS_OK paginas=$paginas linhas=${sequencias.length}');

    // 4. Adulteração no banco de e2e, pelo script.
    // ignore: avoid_print
    print('E2E_ADULTERAR sequence=$_sequenciaAdulterada');
    final fimDaEspera = DateTime.now().add(const Duration(seconds: 90));
    api.AdminAuditEntry? vista;
    while (DateTime.now().isBefore(fimDaEspera)) {
      final pagina = await client.admin.auditLogs(
          accessToken: _token, limit: 1, beforeSequence: _sequenciaAdulterada + 1);
      vista = pagina.items.single;
      if (vista.integrity == api.AuditRowSeal.invalid) break;
      await tester.pump(const Duration(seconds: 2));
    }
    expect(vista?.sequence, _sequenciaAdulterada);
    expect(vista?.integrity, api.AuditRowSeal.invalid, reason: 'o script não adulterou a linha (ou o selo não viu)');

    // Só depois de vencido o cache da última verificação, senão o servidor
    // devolveria o retrato íntegro de antes da adulteração.
    while (DateTime.now().difference(_ultimaVerificacao) <= _cacheDaVerificacao) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    final quebra = await _verificarCadeia(tester, esperado: 'Falha de integridade na cadeia');
    expect(quebra, contains('Primeiro registro com falha: nº $_sequenciaAdulterada.'));
    expect(quebra, isNot(contains('Cadeia íntegra')));

    expect(await _limpar(tester), 50);
    await _carregarTudo(tester);
    final depois = await _varrer(tester);
    final adulteradas = [for (final (s, selo) in depois) if (selo == 'Adulterado?') s];
    expect(adulteradas, [_sequenciaAdulterada], reason: 'só a linha adulterada pode aparecer como "Adulterado?"');
    expect(depois.where((e) => e.$2 != 'Íntegro' && e.$1 != _sequenciaAdulterada), isEmpty,
        reason: 'toda outra linha é "Íntegro"');
    expect(depois.map((e) => e.$1).toList(), [for (var s = depois.first.$1; s >= 1; s--) s]);
    final porRpc = await _trilhaPorRpc();
    expect([for (final e in porRpc) if (e.integrity != api.AuditRowSeal.verified) e.sequence], [_sequenciaAdulterada]);
    // ignore: avoid_print
    print('E2E_ADULTERACAO_DETECTADA sequence=$_sequenciaAdulterada linhas=${depois.length}');

    // 5. Exportação do período, com a cadeia (ainda) adulterada.
    await _preencherPeriodo(tester);
    expect(await _aplicar(tester), _linhasNoPeriodo);
    await _tocarChave(tester, 'audit_export_button');
    await _pumpUntil(tester, () => _existe('audit_export_confirm'), motivo: 'a confirmação da exportação');
    expect(find.textContaining('registrad'), findsWidgets, reason: 'a confirmação avisa que fica registrado');
    await tester.tap(find.byKey(const Key('audit_export_confirm')));
    await tester.pump(const Duration(milliseconds: 500));
    await _pumpUntil(tester, () => _existe('audit_export_result') || _existe('audit_export_error'),
        timeout: const Duration(seconds: 60), motivo: 'o resultado da exportação');
    expect(_existe('audit_export_error'), isFalse, reason: _texto('audit_export_error'));
    expect(await _rolarAte(tester, find.byKey(const Key('audit_export_result'))), isTrue);
    expect(_texto('audit_export_summary'), '$_linhasNoPeriodo registros exportados');
    expect(find.text('Registros de nº $_primeiraNoPeriodo a nº $_ultimaNoPeriodo.'), findsOneWidget);
    expect(_texto('audit_export_chain'), contains('falha de integridade'),
        reason: 'a cadeia estava adulterada no momento da exportação');
    final shaNaTela = _texto('audit_export_sha256')!;
    expect(shaNaTela, matches(RegExp(r'^[0-9a-f]{64}$')));

    await _tocarChave(tester, 'audit_export_copy');
    await _pumpUntil(tester, () => _existe('audit_export_clipboard_warning'), motivo: 'o aviso da área de transferência');
    final copiado = await Clipboard.getData(Clipboard.kTextPlain);
    final csv = copiado?.text;
    if (csv == null || csv.isEmpty) {
      // ignore: avoid_print
      print('E2E_CLIPBOARD caminho=indisponivel');
      fail('Clipboard.getData não devolveu o CSV no aparelho');
    }
    // ignore: avoid_print
    print('E2E_CLIPBOARD caminho=clipboard');
    expect(sha256.convert(utf8.encode(csv)).toString(), shaNaTela,
        reason: 'o que foi copiado é exatamente o arquivo cujo SHA-256 o servidor devolveu');
    final linhas = csv.split('\r\n');
    expect(linhas.first, _colunas);
    expect(linhas.last, isEmpty, reason: 'CRLF no fim de cada linha');
    final dados = linhas.sublist(1, linhas.length - 1);
    expect(dados, hasLength(_linhasNoPeriodo));
    for (final l in dados) {
      expect(l.split(','), hasLength(9), reason: 'nove campos por linha');
    }
    final seqsNoCsv = [for (final l in dados) int.parse(l.split(',').first)];
    expect(seqsNoCsv.toSet(), {for (var s = _primeiraNoPeriodo; s <= _ultimaNoPeriodo; s++) s});
    final selos = {for (final l in dados) int.parse(l.split(',').first): l.split(',').last};
    expect(selos[_sequenciaAdulterada], 'invalid');
    expect(selos.entries.where((e) => e.key != _sequenciaAdulterada && e.value != 'verified'), isEmpty);
    expect(RegExp(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').hasMatch(csv), isFalse,
        reason: 'nenhum UUID no CSV');
    expect(RegExp(r'[0-9a-fA-F]{32,}').hasMatch(csv), isFalse, reason: 'nenhum hash no CSV');
    expect(RegExp(r'\b\d{1,3}(\.\d{1,3}){3}\b').hasMatch(csv), isFalse, reason: 'nenhum IP no CSV');
    expect(csv, isNot(contains('sem-requisicao-http')));
    // ignore: avoid_print
    print('E2E_EXPORT_FEITO linhas=${dados.length} primeira=$_primeiraNoPeriodo ultima=$_ultimaNoPeriodo');
  });

  testWidgets('coordenador vê só a UBS dele, não tem "Exportar" e a exportação por RPC é recusada', (tester) async {
    await _abrirApp(tester);
    await _entrar(tester, await _coordenadorDoRele());
    expect(_sessao?.role, 'coordinator');
    await _abrirAuditoria(tester);

    // Escopo: só as linhas cujo autor tem microárea na UBS dele — as do ACS
    // semeadas. As do administrador, as do próprio coordenador e as gravadas
    // pelo teste anterior (staff, sem microárea) não aparecem.
    expect(await _esperarLista(tester), _linhasDoAcs);
    final vistas = await _varrer(tester);
    expect(vistas, hasLength(_linhasDoAcs));
    expect(find.textContaining('(Administrador)'), findsNothing);
    final porRpc = await _trilhaPorRpc();
    expect(porRpc, hasLength(_linhasDoAcs));
    expect(porRpc.every((e) => e.userLabel.endsWith('(ACS)')), isTrue, reason: 'só autores ACS no escopo');

    // A cadeia segue adulterada (o script restaura depois): o coordenador não
    // a vê como íntegra.
    // O painel fica no topo: depois da varredura a lista está no fim e ele
    // saiu da árvore.
    _posicao(tester).jumpTo(0);
    await tester.pump(const Duration(milliseconds: 200));
    await _pumpUntil(tester, () => !_existe('audit_chain_verifying') && _texto('audit_chain_title') != null,
        timeout: const Duration(seconds: 60), motivo: 'o painel da cadeia do coordenador');
    expect(_texto('audit_chain_title'), 'Falha de integridade na cadeia');

    // Nenhuma seção de exportação em lugar nenhum da tela (varrida até o fim).
    expect(await _rolarAte(tester, find.byKey(const Key('audit_export_section'))), isFalse);
    expect(await _rolarAte(tester, find.text('Exportar CSV')), isFalse);

    // O servidor é a autoridade: o RPC direto é recusado (e auditado `denied`).
    final client = await _clienteRpc();
    final agora = DateTime.now().toUtc();
    await expectLater(
      client.admin.exportAuditLogs(
        accessToken: _token,
        filter: api.AdminAuditFilter(from: agora.subtract(const Duration(days: 30)), to: agora),
      ),
      throwsA(isA<api.AlertPermissionException>()),
    );
    // ignore: avoid_print
    print('E2E_COORDENADOR_OK linhas=${vistas.length}');
    // ignore: avoid_print
    print('E2E_FIM');
  });
}
