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

/// Chaves `alert_<id>` dos cartões construídos agora.
Iterable<ValueKey<String>> _chavesDeCartao() => find
    .byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('alert_'))
    .evaluate()
    .map((e) => e.widget.key! as ValueKey<String>);

/// Percorre a lista do topo ao fim e devolve, por cartão (`alert_<id>`), os
/// textos vistos. A lista é preguiçosa: um cartão além da dobra não existe na
/// árvore até ser rolado para dentro.
Future<Map<String, Set<String>>> _cartoesAoRolar(WidgetTester tester) async {
  final vistos = <String, Set<String>>{};
  final rolavel = find.byType(Scrollable).last;
  for (var passo = 0; passo < 12; passo++) {
    for (final chave in _chavesDeCartao()) {
      final textos = find
          .descendant(of: find.byKey(chave), matching: find.byType(Text))
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '');
      vistos.putIfAbsent(chave.value, () => <String>{}).addAll(textos);
    }
    await tester.drag(rolavel, const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 300));
  }
  return vistos;
}

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
  final fiacao = buildAdminWiring(caBytes: ca);
  await tester.pumpWidget(SinalAdminApp(auth: fiacao.auth, dataSourceFor: fiacao.dataSourceFor));
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

  testWidgets('código de ativação errado: recusado, e o QR não aparece (#48)', (tester) async {
    await _abrirApp(tester);
    final cred = await adminCredentialFromRelay();
    await _digitar(tester, 'matricula_field', cred.matricula);
    await _digitar(tester, 'senha_field', cred.senha);
    await _tocar(tester, 'login_button');

    // Conta sem MFA: o app abre a etapa do código de ativação, ainda sem segredo.
    await _pumpUntil(tester, () => _existe('activation_code_field'));
    expect(_existe('mfa_secret'), isFalse);

    // O código certo com o último caractere trocado: não vale em lugar nenhum.
    final c = cred.activationCode;
    final errado = '${c.substring(0, c.length - 1)}${c.endsWith('A') ? 'B' : 'A'}';
    await _digitar(tester, 'activation_code_field', errado);
    await _tocar(tester, 'activation_continue');
    await _pumpUntil(tester, () => _existe('activation_error'));

    expect(tester.widget<Text>(find.byKey(const Key('activation_error'))).data, 'Código de ativação inválido ou expirado.');
    expect(_existe('mfa_secret'), isFalse);
    expect(find.text('Painel de Indicadores'), findsNothing);
  });

  testWidgets('primeiro acesso: pede a ativação da MFA, mostra o segredo e confirma com o código', (tester) async {
    await _abrirApp(tester);
    final cred = await adminCredentialFromRelay();
    await _digitar(tester, 'matricula_field', cred.matricula);
    await _digitar(tester, 'senha_field', cred.senha);
    await _tocar(tester, 'login_button');

    // Conta sem TOTP ativado: o servidor responde MfaEnrollmentRequired e o app abre a
    // etapa do código de ativação (#48); só com ele o servidor devolve o segredo.
    await _pumpUntil(tester, () => _existe('activation_code_field'));
    await _digitar(tester, 'activation_code_field', cred.activationCode);
    await _tocar(tester, 'activation_continue');
    await _pumpUntil(tester, () => _existe('mfa_secret'));
    expect(find.text('Painel de Indicadores'), findsNothing);
    final segredoBase32 = tester.widget<SelectableText>(find.byKey(const Key('mfa_secret'))).data!;
    _segredo = base32Decode(segredoBase32);
    expect(_segredo, isNotEmpty);

    // Um único instante: o passo registrado é o do código enviado (dois
    // `DateTime.now()` na virada de 30 s dariam passos diferentes).
    final instanteDaAtivacao = DateTime.now();
    _passoDaAtivacao = _passo(instanteDaAtivacao);
    await _digitar(tester, 'mfa_code_field', totpCode(_segredo!, instanteDaAtivacao));
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
    final instante = DateTime.now();
    expect(_passo(instante), greaterThan(_passoDaAtivacao!));
    await _digitar(tester, 'totp_field', totpCode(_segredo!, instante));
    await _tocar(tester, 'login_button');
    await _pumpUntil(tester, () => find.text('Painel de Indicadores').evaluate().isNotEmpty || _existe('login_error'));

    expect(_existe('login_error'), isFalse,
        reason: _existe('login_error') ? (tester.widget<Text>(find.byKey(const Key('login_error'))).data ?? '') : '');
    expect(find.text('Painel de Indicadores'), findsOneWidget);

    // Dados REAIS (#40): o seed semeia 4 alertas na microárea (vermelho pendente,
    // vermelho reconhecido 60 s depois, verde pendente e, desde a #87, um vermelho
    // concluído, reconhecido aos 60 s), então o painel deve mostrar Vermelho 3,
    // Amarelo 0, Verde 1, 1 aberto, 1 reconhecido, 1 concluído e TMRAV 60s.
    await _pumpUntil(tester, () => find.text('60s').evaluate().isNotEmpty);
    expect(find.text('3'), findsOneWidget, reason: 'Vermelho = 3');
    expect(find.text('0'), findsOneWidget, reason: 'Amarelo = 0 (nenhuma outra linha mostra 0)');
    expect(find.text('Concluídos'), findsOneWidget, reason: 'a linha da #87 existe');
    expect(find.text('—'), findsNothing, reason: 'há amostra: o TMRAV não pode ser o traço');

    // Alertas: 4 cartões, só com rótulo (`Paciente #XXXX`), nunca nome de paciente.
    // A lista é preguiçosa e, no celular, o 4º cartão fica além da dobra (a
    // faixa de vencidos e o selo da #87 empurram): os cartões são reunidos
    // rolando, pela chave `alert_<id>`, em vez de contados numa só tela.
    await tester.tap(find.text('Alertas').last);
    await tester.pump(const Duration(milliseconds: 300));
    final rotulo = RegExp(r'^Paciente #[0-9A-F]{4}$');
    await _pumpUntil(tester, () => _chavesDeCartao().isNotEmpty);
    final cartoes = await _cartoesAoRolar(tester);
    expect(cartoes, hasLength(4), reason: '4 alertas semeados: ${cartoes.keys}');
    for (final textos in cartoes.values) {
      expect(textos.where(rotulo.hasMatch), hasLength(1), reason: 'cada cartão tem um rótulo minimizado');
      expect(textos.any((t) => t.contains('Paciente E2E')), isFalse, reason: 'nome de paciente nunca aparece');
    }
    expect(cartoes.values.where((t) => t.contains('Risco: Vermelho')), hasLength(3));
    expect(cartoes.values.where((t) => t.contains('Risco: Verde')), hasLength(1));
    final concluidos = cartoes.values.where((t) => t.contains('Status: Concluído')).toList();
    expect(concluidos, hasLength(1), reason: 'o concluído mostra o estado (#87)');
    expect(concluidos.single.any((t) => t.startsWith('Concluído às ')), isTrue, reason: 'e a hora da conclusão (#87)');

    // Auditoria: a leitura do próprio admin ficou registrada pelo servidor.
    final auditoriaPorTexto = find.text('Auditoria');
    await tester.tap((auditoriaPorTexto.evaluate().isNotEmpty ? auditoriaPorTexto : find.byTooltip('Auditoria')).last);
    await tester.pump(const Duration(milliseconds: 300));
    // Desde a #45 o painel da cadeia e os filtros ficam acima da lista, que é
    // preguiçosa: num celular a linha de indicadores nasce abaixo da dobra.
    await _pumpUntil(tester, () => find.byKey(const Key('audit_count')).evaluate().isNotEmpty);
    // A verificação da cadeia (#45) é a 5ª leitura `admin_*` que o script
    // confere no banco: espera-se ela voltar, com o painel ainda no topo e
    // antes de rolar, para a chamada não ficar em voo quando o app fechar.
    await _pumpUntil(tester, () {
      final titulo = find.byKey(const Key('audit_chain_title'), skipOffstage: false);
      if (titulo.evaluate().isEmpty) return false;
      return tester.widget<Text>(titulo).data != 'Verificando a integridade da trilha…';
    });
    await tester.scrollUntilVisible(
      find.textContaining('admin_indicators'),
      300,
      scrollable: find.descendant(of: find.byType(AuditLogScreen), matching: find.byType(Scrollable)).first,
    );
    expect(find.textContaining('(Administrador)'), findsWidgets);
  });
}
