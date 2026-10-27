import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/network/backend_config.dart';
import 'package:sinalacs_acs/core/security/biometric_gate.dart';

import 'support/e2e_acs.dart';

class _SemBiometria implements BiometricGate {
  @override
  Future<bool> get isAvailable async => false;
  @override
  Future<UnlockResult> authenticate({required String reason}) async => UnlockResult.unavailable;
}

/// UUID v4 sintético, gerado no aparelho: o script o usa no INSERT.
String _uuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

Future<void> _ate(WidgetTester tester, bool Function() feito, {required Duration teto, required String oQue}) async {
  final fim = DateTime.now().add(teto);
  while (!feito()) {
    if (DateTime.now().isAfter(fim)) fail('$oQue: não aconteceu em ${teto.inSeconds} s');
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// ACK do ACS B sobre um alerta que o ACS A já confirmou (issue #88). Este
/// aparelho é o B (bloco `acsB` da fixture, mesma microárea do A); o A é
/// simulado pelo script, que confirma o alerta no banco a pedido do teste.
/// Decisão da #88 (opção 1): o ACK do B é registrado — resposta `acknowledged`,
/// cartão confirmado, "Concluir atendimento" oferecido — e `alerts.acsId`
/// continua sendo o A. O que a tela prova é a resposta; quem prova o `acsId`
/// é o script, no banco.
///
/// Marcadores lidos pelo script na saída do `flutter test`:
///   E2E_DISPARAR_ALERTA id=<uuid>           → o script insere o alerta (sem acsId)
///   E2E_CONFIRMAR_NO_APARELHO_A id=<uuid>   → o script o confirma no banco como A
///   E2E_ACK_B_OK                            → a resposta ao ACK do B chegou como esperado
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ACK do ACS B sobre alerta já confirmado pelo A é registrado sem erro na tela', (tester) async {
    final ca = (await rootBundle.load(BackendConfig.rpcCaAsset)).buffer.asUint8List();
    final backend = BackendClient(trustedCaBytes: ca);
    addTearDown(backend.close);
    final cred = await secondAcsCredentialFromRelay();

    await tester.pumpWidget(SinalAcsApp(backend: backend, biometricGate: _SemBiometria()));
    await tester.enterText(find.byKey(const Key('matricula_field')), cred.matricula);
    await tester.enterText(find.byKey(const Key('senha_field')), cred.senha);
    final entrar = find.byKey(const Key('login_button'));
    await tester.ensureVisible(entrar);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(entrar);
    await _ate(tester, () => entrar.evaluate().isEmpty, teto: const Duration(seconds: 30), oQue: 'login');

    await _ate(
      tester,
      () => find.byKey(const Key('alert_fallback_status')).evaluate().isNotEmpty,
      teto: const Duration(seconds: 60),
      oQue: 'reserva ligada (o MQTT conectou? o cenário não provaria nada)',
    );

    final id = _uuidV4();
    // ignore: avoid_print
    print('E2E_DISPARAR_ALERTA id=$id');
    final cartao = find.byKey(Key('alert_$id'), skipOffstage: false);
    await _ate(tester, () => cartao.evaluate().isNotEmpty, teto: const Duration(seconds: 45), oQue: 'alerta pela reserva');

    // O aparelho A confirma; este aparelho não fica sabendo (a reserva só
    // consulta de novo dali a 30 s, e o toque abaixo vem antes disso).
    // ignore: avoid_print
    print('E2E_CONFIRMAR_NO_APARELHO_A id=$id');
    final espera = DateTime.now().add(const Duration(seconds: 6));
    while (DateTime.now().isBefore(espera)) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    final confirmar = find.descendant(of: cartao, matching: find.text('Confirmar recebimento'));
    expect(confirmar, findsOneWidget, reason: 'a reserva já promoveu o cartão antes do toque; o cenário não prova nada');
    await Scrollable.ensureVisible(tester.element(confirmar), alignment: 0.5);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(confirmar);

    final confirmado = find.text('Recebimento confirmado à central.');
    final naoReconhecido = find.text('A central não reconheceu este alerta.');
    final concluir = find.byKey(Key('resolve_$id'), skipOffstage: false);
    final concluido = find.byKey(Key('resolved_$id'), skipOffstage: false);
    await _ate(
      tester,
      () => confirmado.evaluate().isNotEmpty || naoReconhecido.evaluate().isNotEmpty || concluido.evaluate().isNotEmpty,
      teto: const Duration(seconds: 20),
      oQue: 'resposta do ACK na tela',
    );
    if (naoReconhecido.evaluate().isNotEmpty) {
      fail('#88: o ACK do segundo ACS foi recusado ("não reconheceu"); a decisão é registrá-lo');
    }
    expect(confirmado, findsOneWidget);
    expect(concluir, findsOneWidget, reason: 'opção 1: o cartão vai a confirmado e oferece concluir');
    expect(concluido, findsNothing);
    // ignore: avoid_print
    print('E2E_ACK_B_OK');
    // Folga para a tela assentar; o ACK já foi auditado no RPC.
    final fim = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(fim)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  });
}
