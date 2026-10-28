/// Reserva por HTTP dos alertas (#80, R2) no emulador, contra o BANCO DE TESTE.
///
/// O broker fica inalcançável a partir do aparelho (o script remove o
/// `adb reverse` da 8883), enquanto o backend segue no ar. O alerta é inserido
/// por SQL pelo script, sem linha no `alert_outbox`: só pode chegar à tela pela
/// consulta de 30 s, o intervalo de produção (não encurtado de propósito).
///
/// Só roda por `scripts/qa/acs_alert_fallback_e2e.sh` (sufixo `_e2e`: a
/// descoberta do `flutter test integration_test` não o encontra). Conversa com o
/// script por linhas marcadoras na saída:
///   E2E_DISPARAR_ALERTA id=<uuid>   → o script insere o alerta
///   E2E_ALERTA_VIA_HTTP atraso_ms=N → o cartão apareceu sem toque
///   E2E_ACK_OK / E2E_RESERVA_OK     → confirmado, e a reserva não o desfez
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

  testWidgets('com o MQTT fora, o alerta chega pela reserva HTTP e o ACK não é desfeito', (tester) async {
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

    // O cenário só prova algo se o tempo real estiver mesmo fora.
    await _ate(
      tester,
      () => find.byKey(const Key('alert_fallback_status')).evaluate().isNotEmpty,
      teto: const Duration(seconds: 60),
      oQue: 'reserva ligada (o MQTT conectou? o cenário não provaria nada)',
    );
    expect(find.text('Sem central'), findsOneWidget, reason: 'o chip diz que o tempo real caiu');

    final id = _uuidV4();
    final disparo = DateTime.now();
    // ignore: avoid_print
    print('E2E_DISPARAR_ALERTA id=$id');

    final cartao = find.byKey(Key('alert_$id'), skipOffstage: false);
    await _ate(tester, () => cartao.evaluate().isNotEmpty, teto: const Duration(seconds: 45), oQue: 'alerta pela reserva');
    // ignore: avoid_print
    print('E2E_ALERTA_VIA_HTTP atraso_ms=${DateTime.now().difference(disparo).inMilliseconds}');

    final confirmar = find.descendant(of: cartao, matching: find.text('Confirmar recebimento'));
    await Scrollable.ensureVisible(tester.element(confirmar), alignment: 0.5);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(confirmar);
    final confirmado = find.descendant(of: cartao, matching: find.text('Recebimento confirmado'));
    await _ate(tester, () => confirmado.evaluate().isNotEmpty, teto: const Duration(seconds: 20), oQue: 'ACK pela tela');
    // ignore: avoid_print
    print('E2E_ACK_OK');

    // Um tique inteiro da reserva depois do ACK: segue confirmado e único.
    final fim = DateTime.now().add(const Duration(seconds: 35));
    while (DateTime.now().isBefore(fim)) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(cartao, findsOneWidget);
    expect(confirmado, findsOneWidget);
    expect(find.descendant(of: cartao, matching: find.text('Confirmar recebimento')), findsNothing);
    // ignore: avoid_print
    print('E2E_RESERVA_OK');
  });
}
