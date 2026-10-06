/// Login real do backoffice (staff) contra o BANCO DE TESTE, pela tela, no
/// emulador: senha errada recusada, primeiro acesso -> ativação da MFA (QR/segredo
/// na tela) -> login com o código -> "Painel de Indicadores", e código errado
/// recusado. Rodada por `scripts/qa/admin_login_e2e.sh`.
///
/// Os dados do painel seguem no `MockAdminDataSource` (issue #41): só o LOGIN é
/// real aqui. A credencial é a do administrador sintético da execução (bloco
/// `staff` do manifesto), entregue pelo relé em `/admin` uma única vez.
///
/// Os testes dependem da ordem (o segredo TOTP nasce na ativação e é usado nos
/// seguintes), como em `apps/acs/integration_test/full_journey_e2e.dart`.
///
/// Sufixo `_e2e.dart` (não `_test.dart`): `flutter test integration_test` descobre
/// `*_test.dart` e o `e2e.sh --full` rodaria isto sem fixtures nem relé.
///
/// PRIVACIDADE: só fixtures sintéticas; a senha e o segredo nunca vão para log.
@Timeout(Duration(minutes: 4))
library;

import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/core/auth/admin_auth_bootstrap.dart';
import 'package:sinalacs_admin/core/auth/backend_config.dart';

import 'support/e2e_admin.dart';
import 'support/totp.dart';

int _passo(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ 30;

Future<void> _pumpUntil(WidgetTester tester, bool Function() done,
    {Duration timeout = const Duration(seconds: 30), Duration step = const Duration(milliseconds: 200)}) async {
  final fim = DateTime.now().add(timeout);
  while (!done() && DateTime.now().isBefore(fim)) {
    await tester.pump(step);
  }
  if (done()) return;
  final telas = <String>[
    for (final k in const ['login_error', 'login_aviso', 'mfa_error'])
      if (find.byKey(Key(k)).evaluate().isNotEmpty)
        '$k=${find.descendant(of: find.byKey(Key(k)), matching: find.byType(Text), matchRoot: true).evaluate().map((e) => (e.widget as Text).data).join(' ')}',
  ];
  fail('condição não atingida em ${timeout.inSeconds}s; tela: ${telas.isEmpty ? '(nada)' : telas.join('; ')}');
}

bool _existe(String chave) => find.byKey(Key(chave)).evaluate().isNotEmpty;

/// Toca num botão que pode estar abaixo da dobra (teclado virtual aberto).
Future<void> _tocar(WidgetTester tester, String chave) async {
  final alvo = find.byKey(Key(chave));
  await tester.ensureVisible(alvo);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(alvo);
}

Future<void> _digitar(WidgetTester tester, String chave, String texto) async {
  final campo = find.byKey(Key(chave));
  await tester.ensureVisible(campo);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.enterText(campo, texto);
}

Future<void> _abrirApp(WidgetTester tester) async {
  final ca = (await rootBundle.load(adminRpcCaAsset)).buffer.asUint8List();
  await tester.pumpWidget(SinalAdminApp(auth: buildAdminAuth(caBytes: ca)));
  await tester.pump(const Duration(milliseconds: 500));
}

/// Segredo TOTP lido da tela de ativação e o passo em que foi confirmado.
Uint8List? _segredo;
int? _passoDaAtivacao;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('senha errada: recusa com a mensagem genérica e o painel não abre', (tester) async {
    expect(AdminBackendConfig.host, startsWith('https://'));
    await _abrirApp(tester);
    final cred = await adminCredentialFromRelay();
    await _digitar(tester, 'matricula_field', cred.matricula);
    await _digitar(tester, 'senha_field', '${cred.senha}-errada');
    await _tocar(tester, 'login_button');
    await _pumpUntil(tester, () => _existe('login_error'));

    final texto = tester.widget<Text>(find.byKey(const Key('login_error'))).data;
    expect(texto, 'Matrícula ou senha inválidos.');
    expect(find.text('Painel de Indicadores'), findsNothing);
    expect(_existe('login_button'), isTrue);
  });

  testWidgets('primeiro acesso: pede a ativação da MFA, mostra o segredo e confirma com o código', (tester) async {
    await _abrirApp(tester);
    final cred = await adminCredentialFromRelay();
    await _digitar(tester, 'matricula_field', cred.matricula);
    await _digitar(tester, 'senha_field', cred.senha);
    await _tocar(tester, 'login_button');

    // Conta sem TOTP ativado: o servidor responde MfaEnrollmentRequired e o app abre a ativação.
    await _pumpUntil(tester, () => _existe('mfa_secret'));
    expect(find.text('Painel de Indicadores'), findsNothing);
    final segredoBase32 = tester.widget<SelectableText>(find.byKey(const Key('mfa_secret'))).data!;
    _segredo = base32Decode(segredoBase32);
    expect(_segredo, isNotEmpty);

    _passoDaAtivacao = _passo(DateTime.now());
    await _digitar(tester, 'mfa_code_field', totpCode(_segredo!, DateTime.now()));
    await _tocar(tester, 'mfa_confirm_button');

    // Confirmado: volta ao login, que agora pede o código do autenticador.
    await _pumpUntil(tester, () => _existe('totp_field'));
    expect(_existe('login_aviso'), isTrue);
    expect(find.text('Painel de Indicadores'), findsNothing);
  });

  testWidgets('código TOTP errado: recusado, e o painel não abre', (tester) async {
    expect(_segredo, isNotNull, reason: 'roda depois da ativação (o arquivo inteiro, em ordem)');
    await _abrirApp(tester);
    final cred = await adminCredentialFromRelay();
    await _digitar(tester, 'matricula_field', cred.matricula);
    await _digitar(tester, 'senha_field', cred.senha);
    await _tocar(tester, 'login_button');
    // Com a MFA ativa o servidor pede o código.
    await _pumpUntil(tester, () => _existe('totp_field'));

    // Um código que NÃO é válido em nenhum passo da janela de +-1 do servidor.
    final agora = DateTime.now();
    final validos = {
      for (final d in const [-30, 0, 30]) totpCode(_segredo!, agora.add(Duration(seconds: d))),
    };
    final errado = List.generate(1000000, (i) => i.toString().padLeft(6, '0')).firstWhere((c) => !validos.contains(c));
    await _digitar(tester, 'totp_field', errado);
    await _tocar(tester, 'login_button');
    await _pumpUntil(tester, () => _existe('login_error'));

    expect(tester.widget<Text>(find.byKey(const Key('login_error'))).data, 'Código de verificação inválido.');
    expect(find.text('Painel de Indicadores'), findsNothing);
  });

  testWidgets('com o código do passo seguinte à ativação, o login abre o Painel de Indicadores', (tester) async {
    expect(_segredo, isNotNull);
    await _abrirApp(tester);
    final cred = await adminCredentialFromRelay();
    await _digitar(tester, 'matricula_field', cred.matricula);
    await _digitar(tester, 'senha_field', cred.senha);
    await _tocar(tester, 'login_button');
    await _pumpUntil(tester, () => _existe('totp_field'));

    // O código da ativação já foi usado e o replay é barrado: espera o relógio
    // passar para um passo MAIOR que o da ativação e usa o do passo ATUAL
    // (dentro da janela de +-1 do servidor).
    await _pumpUntil(tester, () => _passo(DateTime.now()) > _passoDaAtivacao!, timeout: const Duration(seconds: 40));
    await _digitar(tester, 'totp_field', totpCode(_segredo!, DateTime.now()));
    await _tocar(tester, 'login_button');
    await _pumpUntil(tester, () => find.text('Painel de Indicadores').evaluate().isNotEmpty || _existe('login_error'));

    expect(_existe('login_error'), isFalse,
        reason: _existe('login_error') ? (tester.widget<Text>(find.byKey(const Key('login_error'))).data ?? '') : '');
    expect(find.text('Painel de Indicadores'), findsOneWidget);
  });
}
