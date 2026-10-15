/// Atendimento a pedidos do titular (#42) pela tela do backoffice, no emulador,
/// contra o BANCO DE TESTE: login com MFA (ativação pela tela), fila com o pedido
/// vencido primeiro e destacado, correção (iniciar análise -> atender com nota) e
/// exclusão (recusa sem motivo bloqueada -> atender com confirmação). As asserções
/// de banco (anonimização, auditoria, nota cifrada) ficam em
/// `scripts/qa/admin_titular_e2e.sh`. Sufixo `_e2e.dart` pelo mesmo motivo de
/// `admin_login_e2e.dart`: o `flutter test integration_test` não deve descobri-lo.
///
/// PRIVACIDADE: só fixtures sintéticas; senha e segredo nunca vão para log.
@Timeout(Duration(minutes: 6))
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/core/auth/admin_auth_bootstrap.dart';
import 'package:sinalacs_admin/core/auth/backend_config.dart';

import 'support/e2e_admin.dart';
import 'support/totp.dart';

/// Texto sintético da nota: o script confere que NÃO aparece nos logs do backend.
const notaDaCorrecao = 'E2E-NOTA telefone corrigido no cadastro';

int _passo(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ 30;

Future<void> _pumpUntil(WidgetTester tester, bool Function() done,
    {Duration timeout = const Duration(seconds: 30), String? motivo}) async {
  final fim = DateTime.now().add(timeout);
  while (!done() && DateTime.now().isBefore(fim)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  if (!done()) {
    final textos = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(40).join(' | ');
    fail('condição não atingida em ${timeout.inSeconds}s${motivo == null ? '' : ': $motivo'}; tela: $textos');
  }
}

bool _existe(String chave) => find.byKey(Key(chave)).evaluate().isNotEmpty;

Future<void> _tocar(WidgetTester tester, String chave) async {
  final alvo = find.byKey(Key(chave));
  if (alvo.evaluate().isEmpty) {
    // ListView preguiçoso: o que está abaixo da dobra ainda não foi construído.
    await tester.scrollUntilVisible(alvo, 200, scrollable: find.byType(Scrollable).last, maxScrolls: 30);
  }
  await tester.ensureVisible(alvo);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(alvo);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _digitar(WidgetTester tester, String chave, String texto) async {
  final campo = find.byKey(Key(chave));
  if (campo.evaluate().isEmpty) {
    await tester.scrollUntilVisible(campo, 200, scrollable: find.byType(Scrollable).last, maxScrolls: 30);
  }
  await tester.ensureVisible(campo);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.enterText(campo, texto);
  await tester.pump(const Duration(milliseconds: 100));
}

bool _textoNaTela(String trecho) => find.textContaining(trecho).evaluate().isNotEmpty;

/// O detalhe é um ListView preguiçoso: o que está abaixo da dobra ainda não existe.
Future<void> _rolarAte(WidgetTester tester, String trecho) async {
  await _pumpUntil(tester, () => _existe('data_request_back') && find.text('Texto do pedido').evaluate().isNotEmpty && find.byType(Scrollable).evaluate().isNotEmpty,
      motivo: 'detalhe carregado');
  await tester.scrollUntilVisible(find.textContaining(trecho), 200,
      scrollable: find.byType(Scrollable).last, maxScrolls: 30);
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('admin atende a correção e a exclusão do titular', (tester) async {
    expect(AdminBackendConfig.host, startsWith('https://'));
    final ca = (await rootBundle.load(adminRpcCaAsset)).buffer.asUint8List();
    final fiacao = buildAdminWiring(caBytes: ca);
    await tester.pumpWidget(SinalAdminApp(auth: fiacao.auth, dataSourceFor: fiacao.dataSourceFor));
    await tester.pump(const Duration(milliseconds: 500));

    // --- Login: ativação da MFA pela tela, depois o código do passo seguinte.
    final cred = await adminCredentialFromRelay();
    await _digitar(tester, 'matricula_field', cred.matricula);
    await _digitar(tester, 'senha_field', cred.senha);
    await _tocar(tester, 'login_button');
    await _pumpUntil(tester, () => _existe('activation_code_field'));
    await _digitar(tester, 'activation_code_field', cred.activationCode);
    await _tocar(tester, 'activation_continue');
    await _pumpUntil(tester, () => _existe('mfa_secret'));
    final segredo = base32Decode(tester.widget<SelectableText>(find.byKey(const Key('mfa_secret'))).data!);
    final instanteDaAtivacao = DateTime.now();
    final passoDaAtivacao = _passo(instanteDaAtivacao);
    await _digitar(tester, 'mfa_code_field', totpCode(segredo, instanteDaAtivacao));
    await _tocar(tester, 'mfa_confirm_button');
    await _pumpUntil(tester, () => _existe('totp_field'));

    await _digitar(tester, 'matricula_field', cred.matricula);
    await _digitar(tester, 'senha_field', cred.senha);
    // O código da ativação já foi usado e o replay é barrado: espera o passo seguinte.
    await _pumpUntil(tester, () => _passo(DateTime.now()) > passoDaAtivacao, timeout: const Duration(seconds: 40));
    await _digitar(tester, 'totp_field', totpCode(segredo, DateTime.now()));
    await _tocar(tester, 'login_button');
    await _pumpUntil(tester, () => find.text('Painel de Indicadores').evaluate().isNotEmpty);

    // --- Fila: o vencido vem primeiro e destacado.
    // Celular: a barra inferior usa o rótulo curto "Pedidos"; no trilho, o completo.
    final destino = find.text('Pedidos do titular').evaluate().isNotEmpty
        ? find.text('Pedidos do titular').last
        : find.descendant(of: find.byKey(const Key('admin_navigation_bar')), matching: find.text('Pedidos'));
    await tester.tap(destino);
    await tester.pump(const Duration(milliseconds: 500));
    await _pumpUntil(tester, () => find.byWidgetPredicate((w) => w.key.toString().contains('data_request_')).evaluate().length >= 2,
        motivo: 'os dois pedidos semeados');
    final cartoes = find.byWidgetPredicate(
        (w) => w is Card && (w.key?.toString().contains('data_request_') ?? false));
    expect(cartoes, findsNWidgets(2));
    expect(find.descendant(of: cartoes.first, matching: find.text('Correção de dados')), findsOneWidget,
        reason: 'o pedido vencido (correção) aparece primeiro');
    expect(find.descendant(of: cartoes.first, matching: find.byKey(const Key('overdue_icon'))), findsOneWidget);
    expect(find.descendant(of: cartoes.last, matching: find.byKey(const Key('overdue_icon'))), findsNothing);
    expect(find.textContaining('Fulano'), findsNothing);
    expect(find.textContaining('Paciente E2E'), findsNothing, reason: 'nome de titular nunca aparece');

    // --- Correção: lê o texto, inicia a análise e atende com a nota.
    await tester.tap(cartoes.first);
    await _rolarAte(tester, 'E2E-CORRECAO');
    await _tocar(tester, 'start_review_button');
    await _pumpUntil(tester, () => _existe('data_request_action_notice') && !_existe('start_review_button'),
        motivo: 'análise iniciada');
    await _digitar(tester, 'resolution_field', notaDaCorrecao);
    await _tocar(tester, 'complete_button');
    await _pumpUntil(tester, () => !_existe('complete_button'), motivo: 'correção atendida');
    await _rolarAte(tester, notaDaCorrecao);
    expect(_textoNaTela('Resposta ao titular'), isTrue);
    await _tocar(tester, 'data_request_back');

    // --- Exclusão: recusar sem motivo é bloqueado; atender pede confirmação.
    await _pumpUntil(tester, () => find.text('Exclusão dos dados').evaluate().isNotEmpty, motivo: 'lista de volta');
    await tester.tap(find.text('Exclusão dos dados').first);
    await _rolarAte(tester, 'E2E-EXCLUSAO');
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('reject_button'))).onPressed, isNull,
        reason: 'recusa sem motivo está bloqueada');
    await _tocar(tester, 'complete_button');
    await _pumpUntil(tester, () => _existe('confirm_action'), motivo: 'diálogo de confirmação da exclusão');
    await _tocar(tester, 'confirm_action');
    await _pumpUntil(tester, () => !_existe('complete_button') && _existe('data_request_action_notice'),
        motivo: 'exclusão atendida');
  });
}
