import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/core/auth/admin_auth_backend.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

import 'support/fake_admin_auth.dart';
import 'support/layout_harness.dart';

/// Duplo que recusa o cadastro como o servidor recusa: [AdminValidationFailure]
/// carrega o texto sobre a entrada do próprio operador, e é esse texto que a
/// tela tem de mostrar (nunca uma mensagem genérica).
class _MockComRecusaDeValidacao extends MockAdminDataSource {
  @override
  Future<NewAcsCredential> createAcs({
    required String name,
    required String enrollmentId,
    required String microAreaId,
  }) async => throw const AdminValidationFailure('Já existe um ACS com esta matrícula.');
}

Future<void> _abrirMicroAreas(
  WidgetTester tester, {
  AdminDataSource? dataSource,
  AdminAuthBackend? auth,
}) async {
  await abrirBackoffice(tester, tamanho: const Size(1024, 768), dataSource: dataSource, auth: auth);
  await irPara(tester, 'Microáreas');
}

/// Preenche o formulário de cadastro e escolhe a microárea no dropdown.
Future<void> _preencherNovoAcs(
  WidgetTester tester, {
  String nome = 'Nova Agente',
  String matricula = 'ACS-999',
  String microArea = 'Microárea 07 — Centro',
}) async {
  await tester.enterText(find.byKey(const Key('acs_nome_field')), nome);
  await tester.enterText(find.byKey(const Key('acs_matricula_field')), matricula);
  await tester.tap(find.byKey(const Key('acs_microarea_field')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(microArea).last);
  await tester.pumpAndSettle();
}

Future<void> _tocar(WidgetTester tester, String chave) async {
  final alvo = find.byKey(Key(chave));
  await tester.ensureVisible(alvo);
  await tester.pumpAndSettle();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a tela Microáreas lista os ACS com estado e oferece o cadastro', (tester) async {
    await _abrirMicroAreas(tester);

    expect(find.text('Agentes de saúde (ACS)'), findsOneWidget);
    expect(find.byKey(const Key('novo_acs')), findsOneWidget);
    expect(find.byKey(const Key('acs_acs-1')), findsOneWidget);

    // O cartão diz o estado do acesso e da MFA, e oferece as ações da issue.
    final cartao = find.byKey(const Key('acs_acs-1'));
    expect(find.descendant(of: cartao, matching: find.text('Ativo')), findsOneWidget);
    expect(find.descendant(of: cartao, matching: find.text('MFA não ativada')), findsOneWidget);
    expect(find.byKey(const Key('vincular_acs_acs-1')), findsOneWidget);
    expect(find.byKey(const Key('redefinir_senha_acs-1')), findsOneWidget);
    expect(find.byKey(const Key('redefinir_mfa_acs-1')), findsOneWidget);
    expect(find.byKey(const Key('desativar_acs_acs-1')), findsOneWidget);
  });

  testWidgets('desativar só acontece DEPOIS da confirmação', (tester) async {
    final mock = MockAdminDataSource();
    await _abrirMicroAreas(tester, dataSource: mock);

    await _tocar(tester, 'desativar_acs_acs-1');
    expect(find.byKey(const Key('confirmar_acao')), findsOneWidget);

    await _tocar(tester, 'cancelar_acao');
    expect(mock.desativados, isEmpty); // cancelar não chama nada

    await _tocar(tester, 'desativar_acs_acs-1');
    await _tocar(tester, 'confirmar_acao');
    expect(mock.desativados, ['acs-1']);
  });

  testWidgets('reativar é um passo só: sem diálogo de confirmação', (tester) async {
    final mock = MockAdminDataSource();
    await mock.setAcsActive(acsId: 'acs-2', active: false);
    await _abrirMicroAreas(tester, dataSource: mock);

    await _tocar(tester, 'ativar_acs_acs-2');

    expect(find.byKey(const Key('confirmar_acao')), findsNothing);
    final bruno = (await mock.fetchAcs()).firstWhere((a) => a.id == 'acs-2');
    expect(bruno.active, isTrue);
    expect(mock.desativados, ['acs-2'], reason: 'reativar não é uma desativação');
  });

  testWidgets('vincular é um passo só: escolher a microárea e confirmar', (tester) async {
    final mock = MockAdminDataSource();
    await _abrirMicroAreas(tester, dataSource: mock);

    await _tocar(tester, 'vincular_acs_acs-1');
    await tester.tap(find.byKey(const Key('vincular_microarea_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Microárea 03 — Vila Esperança').last);
    await tester.pumpAndSettle();
    await _tocar(tester, 'confirmar_acao');

    expect(mock.vinculados, ['acs-1']);
    expect(find.text('Território: Microárea 03 — Vila Esperança'), findsOneWidget);
  });

  testWidgets('toda ação destrutiva passa pela confirmação, e o código do staff aparece uma vez', (tester) async {
    final mock = MockAdminDataSource();
    await _abrirMicroAreas(tester, dataSource: mock);

    // Redefinir senha: cancelar não chama; confirmar chama e mostra a nova senha.
    await _tocar(tester, 'redefinir_senha_acs-1');
    await _tocar(tester, 'cancelar_acao');
    expect(mock.senhasRedefinidas, isEmpty);
    await _tocar(tester, 'redefinir_senha_acs-1');
    await _tocar(tester, 'confirmar_acao');
    expect(mock.senhasRedefinidas, ['acs-1']);
    expect(find.byKey(const Key('senha_inicial')), findsOneWidget);
    await _tocar(tester, 'fechar_credencial');

    // MFA do ACS: mesma regra.
    await _tocar(tester, 'redefinir_mfa_acs-2');
    await _tocar(tester, 'cancelar_acao');
    expect(mock.mfasRedefinidas, isEmpty);
    await _tocar(tester, 'redefinir_mfa_acs-2');
    await _tocar(tester, 'confirmar_acao');
    expect(mock.mfasRedefinidas, ['acs-2']);

    // MFA de uma conta de equipe: idem, com o código de ativação mostrado uma vez.
    await _tocar(tester, 'redefinir_mfa_staff_staff-1');
    await _tocar(tester, 'cancelar_acao');
    expect(mock.mfasRedefinidas, ['acs-2']);
    await _tocar(tester, 'redefinir_mfa_staff_staff-1');
    await _tocar(tester, 'confirmar_acao');
    expect(mock.mfasRedefinidas, ['acs-2', 'staff-1']);
    expect(find.byKey(const Key('codigo_ativacao')), findsOneWidget);
    await _tocar(tester, 'fechar_credencial');
    expect(find.text('ABCD-EFGH-JKLM-NPQR-STUV'), findsNothing);
  });

  testWidgets('a senha inicial aparece uma única vez, com botão de copiar, e não volta', (tester) async {
    final mock = MockAdminDataSource();
    final copiado = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (chamada) async {
      if (chamada.method == 'Clipboard.setData') {
        copiado.add((chamada.arguments as Map<Object?, Object?>)['text']! as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await _abrirMicroAreas(tester, dataSource: mock);
    await _tocar(tester, 'novo_acs');
    await _preencherNovoAcs(tester);
    await _tocar(tester, 'confirmar_acao');

    expect(find.byKey(const Key('senha_inicial')), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('SENHA-INICIAL-DE-TESTE'), findsOneWidget);

    expect(find.bySemanticsLabel('Copiar'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.copy_outlined));
    await tester.pumpAndSettle();
    expect(copiado, ['SENHA-INICIAL-DE-TESTE']);

    await _tocar(tester, 'fechar_credencial');
    expect(find.text('SENHA-INICIAL-DE-TESTE'), findsNothing);

    // Sai da tela e volta: a senha não reaparece em nenhum ponto da lista.
    await irPara(tester, 'Indicadores');
    await irPara(tester, 'Microáreas');
    expect(find.text('SENHA-INICIAL-DE-TESTE'), findsNothing);
    expect(find.byKey(const Key('senha_inicial')), findsNothing);
  });

  testWidgets('a seção Equipe só aparece para o papel admin', (tester) async {
    final coordenador = FakeAdminAuth()..role = 'coordinator';
    await _abrirMicroAreas(tester, auth: coordenador);

    expect(find.text('Agentes de saúde (ACS)'), findsOneWidget);
    expect(find.text('Equipe do backoffice'), findsNothing);
    expect(find.byKey(const Key('staff_staff-1')), findsNothing);
  });

  testWidgets('a seção Equipe aparece para o admin, com o reset de MFA de cada conta', (tester) async {
    await _abrirMicroAreas(tester);

    // A seção de equipe fica no fim de uma tela longa: rolar até ela é parte do
    // caso (um item fora da viewport não é pintado, logo nem existe para o teste).
    await tester.scrollUntilVisible(find.byKey(const Key('staff_staff-1')), 240, scrollable: find.byType(Scrollable).last);

    expect(find.text('Equipe do backoffice'), findsOneWidget);
    expect(find.byKey(const Key('staff_staff-1')), findsOneWidget);
    expect(find.byKey(const Key('redefinir_mfa_staff_staff-1')), findsOneWidget);
  });

  testWidgets('erro de validação do servidor aparece com a mensagem do servidor', (tester) async {
    await _abrirMicroAreas(tester, dataSource: _MockComRecusaDeValidacao());
    await _tocar(tester, 'novo_acs');
    await _preencherNovoAcs(tester);
    await _tocar(tester, 'confirmar_acao');

    expect(find.text('Já existe um ACS com esta matrícula.'), findsOneWidget);
    expect(find.byKey(const Key('senha_inicial')), findsNothing);
  });
}
