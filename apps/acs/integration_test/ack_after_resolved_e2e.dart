/// ACK no "aparelho B" de um alerta já concluído no "aparelho A" (#86), no
/// emulador, contra o BANCO DE TESTE.
///
/// O alerta chega `pending` só pela reserva HTTP (o script remove o
/// `adb reverse` da 8883 e o insere por SQL, sem `alert_outbox`, como na #80).
/// Com o cartão na tela, o script conclui o alerta no banco — o papel do
/// aparelho A. Para este aparelho o cartão segue pendente: a reserva nunca
/// devolve `resolved`, então só a resposta do ACK revela a conclusão.
///
/// Só roda por `scripts/qa/acs_ack_concluido_e2e.sh` (sufixo `_e2e`). Linhas
/// marcadoras:
///   E2E_DISPARAR_ALERTA id=<uuid>         → o script insere o alerta
///   E2E_CONCLUIR_NO_APARELHO_A id=<uuid>  → o script o conclui no banco
///   E2E_ACK_CONCLUIDO_OK / E2E_SEGUE_CONCLUIDO_OK → a tela não oferece
///                                           "Concluir atendimento"
///
/// PRIVACIDADE: só fixtures sintéticas geradas por execução.
@Timeout(Duration(minutes: 5))
library;

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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ACK no aparelho B de um alerta já concluído no A não oferece "Concluir atendimento"', (tester) async {
    final ca = (await rootBundle.load(BackendConfig.rpcCaAsset)).buffer.asUint8List();
    final backend = BackendClient(trustedCaBytes: ca);
    addTearDown(backend.close);
    final cred = await acsCredentialFromRelay();

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

    // O aparelho A conclui; este aparelho não fica sabendo.
    // ignore: avoid_print
    print('E2E_CONCLUIR_NO_APARELHO_A id=$id');
    final espera = DateTime.now().add(const Duration(seconds: 6));
    while (DateTime.now().isBefore(espera)) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    final confirmar = find.descendant(of: cartao, matching: find.text('Confirmar recebimento'));
    await Scrollable.ensureVisible(tester.element(confirmar), alignment: 0.5);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(confirmar);

    final concluido = find.byKey(Key('resolved_$id'), skipOffstage: false);
    final concluir = find.byKey(Key('resolve_$id'), skipOffstage: false);
    await _ate(
      tester,
      () => concluido.evaluate().isNotEmpty || concluir.evaluate().isNotEmpty,
      teto: const Duration(seconds: 20),
      oQue: 'resposta do ACK na tela',
    );
    if (concluir.evaluate().isNotEmpty) {
      fail('#86: "Concluir atendimento" reapareceu depois do ACK de um alerta já concluído');
    }
    expect(concluido, findsOneWidget);
    expect(concluir, findsNothing);
    expect(find.text('Este atendimento já foi concluído.'), findsOneWidget);
    // ignore: avoid_print
    print('E2E_ACK_CONCLUIDO_OK');

    // Um tique inteiro da reserva depois do ACK: segue concluído.
    final fim = DateTime.now().add(const Duration(seconds: 35));
    while (DateTime.now().isBefore(fim)) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(concluido, findsOneWidget);
    expect(concluir, findsNothing);
    // ignore: avoid_print
    print('E2E_SEGUE_CONCLUIDO_OK');
  });
}
