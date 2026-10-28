import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/device_certificate_store.dart';
import 'package:sinalacs_acs/core/services/device_certificate_enroller.dart';

import 'support/fakes.dart';

/// Emissão do certificado MQTT do aparelho (#94): quando reemitir, quando
/// servir o guardado sem rede e quando desistir. Ids sintéticos; o "servidor"
/// é o [FakeAcsBackend], que assina o CSR com uma CA de teste.
void main() {
  const acsId = seedAcsId;
  const deviceId = '00000000-0000-4000-8000-0000000000d1';
  const microArea = seedMicroAreaId;
  const semRede = BackendFailure('Sem conexão com o servidor. Verifique a rede e tente de novo.');

  late FakeAcsBackend backend;
  late InMemoryDeviceCertificateStore store;
  late DateTime relogio;
  late DeviceCertificateEnroller enroller;

  setUp(() {
    relogio = DateTime.utc(2026, 10, 27, 12);
    backend = FakeAcsBackend()..serverClock = () => relogio;
    store = InMemoryDeviceCertificateStore();
    enroller = DeviceCertificateEnroller(store: store, backend: backend, now: () => relogio);
  });

  Future<StoredDeviceCertificate> garantir({String microAreaId = microArea}) =>
      enroller.ensure(acsId: acsId, deviceId: deviceId, microAreaId: microAreaId);

  test('sem certificado emite, grava e devolve', () async {
    final cert = await garantir();

    expect(backend.issueCertificateCount, 1);
    expect(cert.acsId, acsId);
    expect(cert.deviceId, deviceId);
    expect(cert.microAreaId, microArea);
    expect(cert.serial, 'serial-1');
    expect(cert.certificatePem, contains('BEGIN CERTIFICATE'));
    expect(cert.privateKeyPem, contains('BEGIN EC PRIVATE KEY'));
    expect(cert.notAfter, relogio.add(const Duration(days: 30)));
    expect(backend.issuedCsrs.single, isNot(contains('PRIVATE')), reason: 'a chave privada nunca sai do aparelho');
    final guardado = await store.read(acsId: acsId, deviceId: deviceId);
    expect(guardado?.serial, 'serial-1');
    expect(guardado?.privateKeyPem, cert.privateKeyPem);
  });

  test('válido e longe de vencer não chama o servidor', () async {
    await garantir();
    relogio = relogio.add(const Duration(days: 19));

    final cert = await garantir();

    expect(backend.issueCertificateCount, 1);
    expect(cert.serial, 'serial-1');
  });

  test('faltando 9 dias reemite', () async {
    final primeiro = await garantir();
    relogio = relogio.add(const Duration(days: 21));

    final cert = await garantir();

    expect(backend.issueCertificateCount, 2);
    expect(cert.serial, 'serial-2');
    expect(cert.privateKeyPem, isNot(primeiro.privateKeyPem), reason: 'par novo a cada emissão');
    expect((await store.read(acsId: acsId, deviceId: deviceId))?.serial, 'serial-2');
  });

  test('faltando 9 dias e sem rede devolve o guardado', () async {
    await garantir();
    relogio = relogio.add(const Duration(days: 21));
    backend.issueCertificateFailure = semRede;

    final cert = await garantir();

    expect(backend.issueCertificateCount, 2);
    expect(cert.serial, 'serial-1');
  });

  test('vencido e sem rede lança DeviceCertificateUnavailable(expired: true)', () async {
    await garantir();
    relogio = relogio.add(const Duration(days: 31));
    backend.issueCertificateFailure = semRede;

    await expectLater(
      garantir(),
      throwsA(isA<DeviceCertificateUnavailable>().having((e) => e.expired, 'expired', isTrue)),
    );
  });

  test('vencido, sem rede, depois rede volta → reemite na chamada seguinte', () async {
    await garantir();
    relogio = relogio.add(const Duration(days: 31));
    backend.issueCertificateFailure = semRede;
    await expectLater(garantir(), throwsA(isA<DeviceCertificateUnavailable>()));

    backend.issueCertificateFailure = null;
    final cert = await garantir();

    expect(cert.serial, 'serial-3');
    expect(cert.notAfter, relogio.add(const Duration(days: 30)));
  });

  test('sem certificado e sem rede lança DeviceCertificateUnavailable(expired: false)', () async {
    backend.issueCertificateFailure = semRede;

    await expectLater(
      garantir(),
      throwsA(isA<DeviceCertificateUnavailable>().having((e) => e.expired, 'expired', isFalse)),
    );
    expect(await store.read(acsId: acsId, deviceId: deviceId), isNull);
  });

  test('microárea da sessão diferente do CN reemite', () async {
    await garantir();

    final cert = await garantir(microAreaId: otherMicroAreaId);

    expect(backend.issueCertificateCount, 2);
    expect(cert.microAreaId, otherMicroAreaId);
    expect((await store.read(acsId: acsId, deviceId: deviceId))?.microAreaId, otherMicroAreaId);
  });

  test('relógio do aparelho 30 min adiantado não reemite um certificado recém-emitido (usa serverNow)', () async {
    // Folha que vence 20 min depois da janela de renovação, no relógio do
    // servidor. Pelo relógio do aparelho (30 min à frente), já estaria dentro
    // da janela; pela hora do servidor, não.
    backend.certificateLifetime = const Duration(days: 10, minutes: 20);
    final servidor = relogio;
    backend.serverClock = () => servidor;
    relogio = servidor.add(const Duration(minutes: 30));

    await garantir();
    final cert = await garantir();

    expect(backend.issueCertificateCount, 1);
    expect(cert.serial, 'serial-1');
  });

  test('duas chamadas simultâneas fazem uma emissão', () async {
    backend.issueCertificateGate = Completer<void>();

    final a = garantir();
    final b = garantir();
    await Future<void>.delayed(Duration.zero);
    backend.issueCertificateGate!.complete();

    final resultados = await Future.wait([a, b]);
    expect(backend.issueCertificateCount, 1);
    expect(resultados[0].serial, resultados[1].serial);
  });

  test('DeviceWipeRequiredFailure sobe sem gravar nada', () async {
    await garantir();
    final antes = await store.read(acsId: acsId, deviceId: deviceId);
    relogio = relogio.add(const Duration(days: 31));
    backend.issueCertificateFailure = const DeviceWipeRequiredFailure('ordem-1');

    await expectLater(
      garantir(),
      throwsA(isA<DeviceWipeRequiredFailure>().having((f) => f.orderId, 'orderId', 'ordem-1')),
    );
    expect(store.writeCount, 1, reason: 'só a primeira emissão gravou');
    expect((await store.read(acsId: acsId, deviceId: deviceId))?.serial, antes?.serial);
  });

  test('recusa não recuperável do servidor sobe como veio', () async {
    backend.issueCertificateFailure = const BackendFailure('CSR recusado.', isRecoverable: false);

    await expectLater(
      garantir(),
      throwsA(isA<BackendFailure>().having((f) => f.message, 'message', 'CSR recusado.')),
    );
    expect(store.writeCount, 0);
  });
}
