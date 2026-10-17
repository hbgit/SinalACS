import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/acs_devices_dialog.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

import 'support/layout_harness.dart';

/// Duplo cujo pedido é recusado com o texto fixo do app (#81).
class _MockQueRecusa extends MockAdminDataSource {
  @override
  Future<DeviceWipeOrderResult> orderDeviceWipe({
    required String acsId,
    required String deviceId,
    required DeviceWipeReason reason,
  }) async => throw const AdminDataFailure('Aparelho não encontrado.');
}

/// Duplo que já tinha o pedido quando o operador confirmou.
class _MockJaPedido extends MockAdminDataSource {
  @override
  Future<DeviceWipeOrderResult> orderDeviceWipe({
    required String acsId,
    required String deviceId,
    required DeviceWipeReason reason,
  }) async => DeviceWipeOrderResult(
    orderId: 'ord-1',
    requestedAt: DateTime.utc(2026, 10, 17, 9, 0),
    alreadyOrdered: true,
  );
}

Future<void> _abrirAparelhos(
  WidgetTester tester, {
  MockAdminDataSource? dataSource,
  Size tamanho = const Size(1024, 768),
  double escala = 1.0,
}) async {
  await abrirBackoffice(tester, tamanho: tamanho, dataSource: dataSource ?? MockAdminDataSource(), escalaDeFonte: escala);
  await irPara(tester, 'Microáreas');
  final botao = find.byKey(const Key('acs_devices_acs-1'));
  if (botao.evaluate().isEmpty) {
    await tester.scrollUntilVisible(botao, 320, scrollable: find.byType(Scrollable).last);
  }
  await tester.ensureVisible(botao);
  await tester.pumpAndSettle();
  await tester.tap(botao);
  await tester.pumpAndSettle();
}

Future<void> _tocar(WidgetTester tester, String chave) async {
  final alvo = find.byKey(Key(chave));
  await tester.ensureVisible(alvo);
  await tester.pumpAndSettle();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> _escolherMotivo(WidgetTester tester, String rotulo) async {
  await tester.tap(find.byKey(const Key('wipe_reason')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(rotulo).last);
  await tester.pumpAndSettle();
  await _tocar(tester, 'continuar_motivo');
}

void main() {
  testWidgets('lista aparelhos com estado e último acesso', (tester) async {
    await _abrirAparelhos(tester);

    expect(find.text('Aparelho dev-aaaa'), findsOneWidget);
    expect(
      find.text('Último acesso em ${dataEHoraLocal(DateTime.utc(2026, 10, 16, 14, 5))}'),
      findsOneWidget,
    );
    // Sem pedido: sem linha de estado, com o botão.
    expect(find.byKey(const Key('estado_dev-aaaa1111')), findsNothing);
    expect(find.byKey(const Key('wipe_device_dev-aaaa1111')), findsOneWidget);
    expect(find.text('Limpar remotamente'), findsOneWidget);
    // Já limpo: estado visível e botão escondido.
    expect(find.textContaining('Aparelho limpo às '), findsOneWidget);
    expect(find.byKey(const Key('wipe_device_dev-bbbb2222')), findsNothing);
  });

  testWidgets('sem aparelho mostra o texto vazio', (tester) async {
    await abrirBackoffice(tester, tamanho: const Size(1024, 768), dataSource: MockAdminDataSource());
    await irPara(tester, 'Microáreas');
    await _tocar(tester, 'acs_devices_acs-2');
    expect(find.text('Nenhum aparelho com acesso registrado para este ACS.'), findsOneWidget);
  });

  testWidgets('cancelar a confirmação não chama orderDeviceWipe', (tester) async {
    final mock = MockAdminDataSource();
    await _abrirAparelhos(tester, dataSource: mock);

    await _tocar(tester, 'wipe_device_dev-aaaa1111');
    await _escolherMotivo(tester, 'Roubado');
    expect(find.text(consequenciaDaLimpezaRemota), findsOneWidget);
    expect(find.text('Limpar aparelho'), findsOneWidget);
    await _tocar(tester, 'cancelar_acao');

    expect(mock.limpezasPedidas, isEmpty);
    expect(find.byKey(const Key('wipe_device_dev-aaaa1111')), findsOneWidget);
  });

  testWidgets('cancelar o motivo também não chama o servidor', (tester) async {
    final mock = MockAdminDataSource();
    await _abrirAparelhos(tester, dataSource: mock);

    await _tocar(tester, 'wipe_device_dev-aaaa1111');
    await _tocar(tester, 'cancelar_motivo');

    expect(mock.limpezasPedidas, isEmpty);
  });

  testWidgets('confirmar envia o motivo escolhido e recarrega a lista', (tester) async {
    final mock = MockAdminDataSource();
    await _abrirAparelhos(tester, dataSource: mock);

    await _tocar(tester, 'wipe_device_dev-aaaa1111');
    await _escolherMotivo(tester, 'Substituído');
    await _tocar(tester, 'confirmar_acao');

    expect(mock.limpezasPedidas, hasLength(1));
    expect(mock.limpezasPedidas.single.deviceId, 'dev-aaaa1111');
    expect(mock.limpezasPedidas.single.reason, DeviceWipeReason.replaced);
    // Lista relida do servidor: agora com estado e sem o botão.
    expect(find.textContaining('Limpeza pedida às '), findsOneWidget);
    expect(find.byKey(const Key('wipe_device_dev-aaaa1111')), findsNothing);
    expect(find.byKey(const Key('aparelhos_aviso')), findsNothing);
  });

  testWidgets('alreadyOrdered mostra o aviso', (tester) async {
    await _abrirAparelhos(tester, dataSource: _MockJaPedido());

    await _tocar(tester, 'wipe_device_dev-aaaa1111');
    await _escolherMotivo(tester, 'Perdido');
    await _tocar(tester, 'confirmar_acao');

    expect(find.text('Este aparelho já tinha um pedido de limpeza.'), findsOneWidget);
  });

  testWidgets('recusa do servidor mostra texto fixo', (tester) async {
    await _abrirAparelhos(tester, dataSource: _MockQueRecusa());

    await _tocar(tester, 'wipe_device_dev-aaaa1111');
    await _escolherMotivo(tester, 'Perdido');
    await _tocar(tester, 'confirmar_acao');

    expect(find.text('Aparelho não encontrado.'), findsOneWidget);
    // O dialogo segue aberto e o botão volta, para tentar de novo.
    expect(find.byKey(const Key('wipe_device_dev-aaaa1111')), findsOneWidget);
  });

  for (final largura in const [360.0, 320.0]) {
    testWidgets('fonte 200% sem estouro em ${largura.toInt()}dp', (tester) async {
      await _abrirAparelhos(tester, tamanho: Size(largura, 800), escala: 2.0);
      esperarSemEstouroDeLayout(tester, 'diálogo de aparelhos (${largura.toInt()}dp, 200%)');

      await _tocar(tester, 'wipe_device_dev-aaaa1111');
      esperarSemEstouroDeLayout(tester, 'motivo (${largura.toInt()}dp, 200%)');
      await _escolherMotivo(tester, 'Roubado');
      esperarSemEstouroDeLayout(tester, 'confirmação (${largura.toInt()}dp, 200%)');
    });
  }
}
