/// Certificado por aparelho (#94) no emulador, contra o BANCO DE TESTE:
/// emissão → conexão → dois aparelhos → limpeza remota → recusa.
///
/// Montagem de produção (`main.dart`) no que a prova mede: o id da instalação
/// (`SecureStorageDeviceIdStore`), o certificado e a chave no Keystore
/// (`SecureStorageDeviceCertificateStore`), o feed MQTT que pede o certificado
/// ao backend, o banco real `sinalacs_acs.db`, os tokens de envio e o diário da
/// limpeza remota. O refresh token fica no `SecureStorageSessionTokenStore`
/// (desbloqueio `notRequired`), como nos outros e2e do ACS.
///
/// Roteiro (o script `scripts/qa/acs_device_cert_e2e.sh` faz a parte do banco,
/// do broker e do segundo aparelho, `tool/device_cert_second_device.dart`):
///   1. o ACS entra pela tela; o feed emite o certificado e conecta
///      ("Alertas em tempo real") → E2E_CERT_PAINEL;
///   2. o coordenador entra (relé `/coordenador`, MFA, TOTP) e espera o
///      SEGUNDO aparelho do ACS aparecer em `admin.acsDevices`;
///   3. pede um alerta (E2E_DISPARAR_ALERTA) e o vê chegar na tela;
///   4. pede a limpeza do segundo aparelho (E2E_WIPE_DEV2_PEDIDO);
///   5. o emulador fica conectado o tempo todo e recebe um segundo alerta
///      (E2E_DISPARAR_ALERTA2): revogar um aparelho não derruba o outro;
///   6. pede a limpeza do PRÓPRIO aparelho (E2E_WIPE_DEV1_PEDIDO): fluxo da #81
///      até `device_wiped`; "Entrar de novo" abre o painel com id novo e
///      certificado novo, conectado (E2E_CERT_OK).
///
/// Só roda pelo script (sufixo `_e2e`: a descoberta do `flutter test
/// integration_test` não o encontra).
///
/// PRIVACIDADE: só fixtures sintéticas geradas por execução. Chave privada,
/// senhas, tokens e o segredo TOTP nunca são impressos.
@Timeout(Duration(minutes: 12))
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/database/sqlcipher_visit_store.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/network/backend_config.dart';
import 'package:sinalacs_acs/core/security/biometric_gate.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/security/secure_device_certificate_store.dart';
import 'package:sinalacs_acs/core/security/secure_session_token_store.dart';
import 'package:sinalacs_acs/core/security/secure_upload_token_store.dart';
import 'package:sinalacs_acs/core/services/micro_area_directory_factory.dart';
import 'package:sinalacs_acs/core/services/remote_wipe.dart';
import 'package:sinalacs_client/sinalacs_client.dart' as api;

import 'support/e2e_acs.dart';
import 'support/totp.dart';

class _SemBiometria implements BiometricGate {
  @override
  Future<bool> get isAvailable async => false;
  @override
  Future<UnlockResult> authenticate({required String reason}) async => UnlockResult.unavailable;
}

Future<void> _ate(WidgetTester tester, bool Function() feito, {required Duration teto, required String oQue}) async {
  final fim = DateTime.now().add(teto);
  while (!feito()) {
    if (DateTime.now().isAfter(fim)) fail('$oQue: não aconteceu em ${teto.inSeconds} s');
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<T> _ateValor<T extends Object>(
  WidgetTester tester,
  Future<T?> Function() valor, {
  required Duration teto,
  required String oQue,
  Duration passo = const Duration(seconds: 2),
}) async {
  final fim = DateTime.now().add(teto);
  while (true) {
    final v = await valor();
    if (v != null) return v;
    if (DateTime.now().isAfter(fim)) fail('$oQue: não aconteceu em ${teto.inSeconds} s');
    await tester.pump(passo);
  }
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

int _passo(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ 30;

/// Coordenador pela rede real, fora do app (mesmo roteiro de
/// `remote_wipe_e2e.dart`): ativa a MFA e entra com o TOTP do passo seguinte.
Future<String> _tokenDoCoordenador(api.Client cliente) async {
  final cred = await coordinatorCredentialFromRelay();
  final inicio = await cliente.auth.beginStaffTotpEnrollment(
    matricula: cred.matricula,
    password: cred.senha,
    activationCode: cred.activationCode,
  );
  final segredo = base32Decode(inicio.secretBase32);
  final confirmacao = DateTime.now();
  await cliente.auth.confirmStaffTotpEnrollment(
    matricula: cred.matricula,
    password: cred.senha,
    activationCode: cred.activationCode,
    code: totpCode(segredo, confirmacao),
  );
  while (_passo(DateTime.now()) <= _passo(confirmacao)) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  final login = await cliente.auth.loginStaff(
    matricula: cred.matricula,
    password: cred.senha,
    totpCode: totpCode(segredo, DateTime.now()),
  );
  return login.accessToken;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('certificado por aparelho: emissão, dois aparelhos, limpeza remota e reemissão', (tester) async {
    final ca = (await rootBundle.load(BackendConfig.rpcCaAsset)).buffer.asUint8List();
    const host = String.fromEnvironment('SINALACS_HOST', defaultValue: 'https://10.0.2.2/');
    final cred = await acsCredentialFromRelay();

    // 0) Montagem de produção, a partir de um aparelho sem restos: sessão,
    //    tokens de envio, diário, banco, certificado e id da instalação.
    final deviceIds = SecureStorageDeviceIdStore();
    final certificados = SecureStorageDeviceCertificateStore();
    final uploadTokens = SecureStorageUploadTokenStore();
    final diario = SharedPreferencesWipeJournal();
    final sessao = SecureStorageSessionTokenStore();
    await sessao.clear();
    await uploadTokens.clearAll();
    await diario.clear();
    await certificados.delete(deviceId: await deviceIds.readOrCreate());
    await deviceIds.delete();
    const arquivo = 'sinalacs_acs.db';
    await EncryptedLocalDatabase.deleteDatabaseFile(arquivo);

    final backend = BackendClient(
      trustedCaBytes: ca,
      tokenStore: sessao,
      deviceIds: deviceIds,
      uploadTokens: uploadTokens,
    );
    addTearDown(backend.close);

    await tester.pumpWidget(
      SinalAcsApp(
        backend: backend,
        biometricGate: _SemBiometria(),
        syncInterval: const Duration(hours: 2),
        visitStorage: SqlCipherVisitStorage(keyStore: SecureStorageDatabaseKeyStore()),
        microAreaDirectory: buildMicroAreaDirectory(backend: backend),
        uploadTokens: uploadTokens,
        deviceIds: deviceIds,
        deviceCertificates: certificados,
        wipeJournal: diario,
      ),
    );

    final emTempoReal = find.text('Alertas em tempo real');
    Future<void> entrar() async {
      await _ate(
        tester,
        () => find.byKey(const Key('matricula_field')).evaluate().isNotEmpty,
        teto: const Duration(seconds: 30),
        oQue: 'tela de login',
      );
      await tester.enterText(find.byKey(const Key('matricula_field')), cred.matricula);
      await tester.enterText(find.byKey(const Key('senha_field')), cred.senha);
      final entrarBotao = find.byKey(const Key('login_button'));
      await tester.ensureVisible(entrarBotao);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(entrarBotao);
      await _ate(
        tester,
        () => entrarBotao.evaluate().isEmpty || find.byKey(const Key('login_error')).evaluate().isNotEmpty,
        teto: const Duration(seconds: 30),
        oQue: 'login',
      );
      expect(find.byKey(const Key('login_error')), findsNothing);
      // O feed pede o certificado ao backend e conecta com ele.
      await _ate(
        tester,
        () => emTempoReal.evaluate().isNotEmpty,
        teto: const Duration(seconds: 60),
        oQue: 'conexão ao broker com o certificado do aparelho',
      );
    }

    // 1) Entra; o certificado é emitido para ESTE aparelho e o broker o aceita.
    await entrar();
    final acsId = backend.session!.userId;
    final dev1 = await deviceIds.readOrCreate();
    final cert1 = await certificados.read(acsId: acsId, deviceId: dev1);
    expect(cert1, isNotNull, reason: 'o certificado fica no Keystore');
    expect(cert1!.microAreaId, backend.session!.microAreaId, reason: 'CN = microárea da sessão');
    // ignore: avoid_print
    print('E2E_CERT_PAINEL acs=$acsId device=$dev1 serial=${cert1.serial}');

    // 2) O coordenador, pela rede real, espera o segundo aparelho do ACS.
    final cliente = api.Client(host, securityContext: SecurityContext()..setTrustedCertificatesBytes(ca))
      ..connectivityMonitor = null;
    addTearDown(cliente.close);
    final tokenCoordenador = await _tokenDoCoordenador(cliente);
    final dev2 = await _ateValor<String>(
      tester,
      () async {
        final aparelhos = await cliente.admin.acsDevices(accessToken: tokenCoordenador, acsId: acsId);
        final outros = aparelhos.where((a) => a.deviceId != dev1).map((a) => a.deviceId).toList();
        return outros.isEmpty ? null : outros.single;
      },
      teto: const Duration(minutes: 3),
      oQue: 'segundo aparelho do ACS no backoffice',
    );

    // 3) Um alerta: o script o insere e o despacha pelo outbox.
    final alerta1 = _uuidV4();
    // ignore: avoid_print
    print('E2E_DISPARAR_ALERTA id=$alerta1 dev2=$dev2');
    await _ate(
      tester,
      () => find.byKey(Key('alert_$alerta1'), skipOffstage: false).evaluate().isNotEmpty,
      teto: const Duration(seconds: 90),
      oQue: 'primeiro alerta na tela',
    );
    expect(emTempoReal, findsOneWidget, reason: 'chegou pelo broker, não pela reserva HTTP');
    // ignore: avoid_print
    print('E2E_ALERTA_NA_TELA id=$alerta1');
    // O mesmo publish chega ao segundo aparelho; folga antes de revogá-lo
    // (o script confere a ordem: recebido ANTES de derrubado).
    await tester.pump(const Duration(seconds: 3));

    // 4) Limpeza remota do SEGUNDO aparelho.
    final pedido2 = await cliente.admin.orderDeviceWipe(
      accessToken: tokenCoordenador,
      acsId: acsId,
      deviceId: dev2,
      reason: api.DeviceWipeReason.lost,
    );
    expect(pedido2.alreadyOrdered, isFalse);
    // ignore: avoid_print
    print('E2E_WIPE_DEV2_PEDIDO order=${pedido2.orderId} device=$dev2');

    // 5) Este aparelho segue conectado durante a derrubada e a recarga da CRL.
    final fimJanela = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(fimJanela)) {
      expect(find.text('Sem central'), findsNothing, reason: 'revogar o outro aparelho derrubou este');
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byKey(const Key('device_wiped')), findsNothing);
    final alerta2 = _uuidV4();
    // ignore: avoid_print
    print('E2E_DISPARAR_ALERTA2 id=$alerta2');
    await _ate(
      tester,
      () => find.byKey(Key('alert_$alerta2'), skipOffstage: false).evaluate().isNotEmpty,
      teto: const Duration(seconds: 120),
      oQue: 'segundo alerta na tela',
    );
    expect(emTempoReal, findsOneWidget, reason: 'chegou pelo broker, não pela reserva HTTP');
    // ignore: avoid_print
    print('E2E_ALERTA2_NA_TELA id=$alerta2');

    // 6) Limpeza remota DESTE aparelho: fluxo da #81 até a tela final.
    final pedido1 = await cliente.admin.orderDeviceWipe(
      accessToken: tokenCoordenador,
      acsId: acsId,
      deviceId: dev1,
      reason: api.DeviceWipeReason.stolen,
    );
    expect(pedido1.alreadyOrdered, isFalse);
    // ignore: avoid_print
    print('E2E_WIPE_DEV1_PEDIDO order=${pedido1.orderId} device=$dev1');
    for (final estado in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(estado);
    }
    await _ate(
      tester,
      () => find.byKey(const Key('device_wiped')).evaluate().isNotEmpty,
      teto: const Duration(seconds: 30),
      oQue: 'tela device_wiped',
    );
    final fimDiario = DateTime.now().add(const Duration(seconds: 30));
    while (await diario.read() != null) {
      if (DateTime.now().isAfter(fimDiario)) fail('confirmação da limpeza não entregue em 30 s');
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(
      await certificados.read(acsId: acsId, deviceId: dev1),
      isNull,
      reason: 'o certificado saiu do Keystore',
    );

    // "Entrar de novo": id novo, certificado novo, conexão nova.
    final deNovo = find.byKey(const Key('device_wiped_login'));
    await tester.ensureVisible(deNovo);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(deNovo);
    await entrar();
    final dev3 = await deviceIds.readOrCreate();
    expect(dev3, isNot(dev1));
    final cert3 = await certificados.read(acsId: acsId, deviceId: dev3);
    expect(cert3, isNotNull);
    expect(cert3!.serial, isNot(cert1.serial));
    // ignore: avoid_print
    print('E2E_CERT_OK acs=$acsId novo=$dev3 serial=${cert3.serial}');

    // Desmonta o app aqui: o feed e os timers do painel ainda estão ativos.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
